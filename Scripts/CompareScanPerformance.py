#!/usr/bin/env python3
"""Opt-in 1.2.0 comparison using the actual inventory functions and bundled engine.

The skewed fixture deliberately puts expensive, equal-sized ZIPs into one old
worker queue. This diagnoses scheduling imbalance, not typical disk throughput.
Use --database PATH to load real definitions; the default is a harmless signature.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import socket
import statistics
import subprocess
import tempfile
import time
import zipfile
import io


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', default='e856d96e31eff0e18a5f01740762ad6f80d5b5f5')
    parser.add_argument('--sdk')
    parser.add_argument('--database', type=Path)
    parser.add_argument('--trials', type=int, choices=range(1, 11), default=3)
    parser.add_argument('--skip-inventory-timing', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    scratch = Path(tempfile.mkdtemp(prefix='aura-compare-', dir='/private/tmp'))
    runtime = repo / 'Vendor/ClamAV'
    env = os.environ | {'DYLD_LIBRARY_PATH': str(runtime / 'lib'), 'CVD_CERTS_DIR': str(runtime / 'etc/certs')}
    source = (repo / 'Sources/ClamAVDesk/ScanController.swift').read_text()
    old = subprocess.check_output(['git', 'show', f'{args.baseline}:Sources/ClamAVDesk/ScanController.swift'], cwd=repo, text=True)

    def inventory(text, name):
        start = text.index('    nonisolated ', text.index('    nonisolated static func countFiles'))
        start = text.rfind('\n', 0, text.index('static func prepareScanFileList', start)) + 1
        end = text.index('    nonisolated static func lastUsefulLine', start)
        function = text[start:end].replace('nonisolated private static', 'nonisolated static')
        function = function.replace('prepareScanFileList(', f'{name}(')
        if 'inventoryDirectory: URL?' not in function:
            function = function.replace('cache: [String: CleanFileStamp])', 'cache: [String: CleanFileStamp], inventoryDirectory: URL? = nil)')
        return function.replace('let support = databaseDirectory.deletingLastPathComponent()', 'let support = inventoryDirectory!').replace('inventoryDirectory ?? databaseDirectory.deletingLastPathComponent()', 'inventoryDirectory!')

    types = source[source.index('    struct ScanPreparation:'):source.index('    private static let lastDefinitionsAttemptKey')]
    swift = 'import Foundation\n' + (repo / 'Sources/ClamAVDesk/Models.swift').read_text() + '\n' + (repo / 'Sources/ClamAVDesk/ScanSafety.swift').read_text()
    swift += '\nenum Inventory {\n' + types + inventory(old, 'baseline') + inventory(source, 'updated') + '}\n'
    swift += r'''
let target = URL(fileURLWithPath: CommandLine.arguments[1])
let support = URL(fileURLWithPath: CommandLine.arguments[2])
let baseline = CommandLine.arguments[3] == "baseline"
var settings = ScanSettings()
settings.workerCount = 4
let start = Date()
let result = try baseline ? Inventory.baseline(at: target, settings: settings, cache: [:], inventoryDirectory: support) : Inventory.updated(at: target, settings: settings, cache: [:], inventoryDirectory: support)
let value: [String: Any] = ["seconds": Date().timeIntervalSince(start), "count": result.count, "skipped": result.skippedCount, "lists": result.fileLists.map(\.path)]
print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self))
'''
    main_swift = scratch / 'main.swift'
    main_swift.write_text(swift)
    compiler = ['swiftc', '-O']
    if args.sdk:
        compiler += ['-sdk', args.sdk]
    subprocess.run(compiler + [str(main_swift), '-o', str(scratch / 'inventory')], check=True)

    def prepare(target, policy):
        support = scratch / f'lists-{policy}-{time.time_ns()}'
        support.mkdir()
        return json.loads(subprocess.check_output([str(scratch / 'inventory'), str(target), str(support), policy], text=True))

    small = scratch / 'small'
    small.mkdir()
    for index in range(20000):
        (small / f'{index:05}.txt').write_bytes((f'Clean file {index}. '.encode() * 64)[:512])
    preparation = {policy: [] for policy in ['baseline', 'updated']}
    for trial in range(0 if args.skip_inventory_timing else 6):
        for policy in (['baseline', 'updated'] if trial % 2 == 0 else ['updated', 'baseline']):
            result = prepare(small, policy)
            assert result['count'] == 20000 and result['skipped'] == 0, result
            preparation[policy].append(result['seconds'])
    if not args.skip_inventory_timing:
        print('Inventory medians:', {p: statistics.median(v) for p, v in preparation.items()}, flush=True)

    skew = scratch / 'skewed'
    skew.mkdir()
    for index in range(1024):
        (skew / f'{index:04}.dat').write_bytes((f'Clean file {index}. '.encode() * 4096)[:32768])
    old_plan = prepare(skew, 'baseline')
    # Same on-disk lengths, different inspection cost: one old lane gets the ZIPs.
    expensive = Path(old_plan['lists'][0]).read_text().splitlines()[::2]
    for index, path in enumerate(expensive):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('document.txt', (f'Clean archive payload {index}. '.encode() * 180000))
        payload = buffer.getvalue()
        assert len(payload) < 32768
        Path(path).write_bytes(payload + b'\0' * (32768 - len(payload)))
    plans = {p: prepare(skew, p) for p in ['baseline', 'updated']}
    database = args.database
    if database is None:
        database = scratch / 'db'
        database.mkdir()
        (database / 'fixture.ndb').write_text('AuraHarmlessFixture:0:*:4155524150524f5445435456414c49444154494f4e5349474e4154555245\n')
    results = []
    for trial in range(args.trials):
        for policy in (['baseline', 'updated'] if trial % 2 == 0 else ['updated', 'baseline']):
            socket_path = scratch / 'd.sock'
            socket_path.unlink(missing_ok=True)
            config = scratch / 'clamd.conf'
            config.write_text(f'LocalSocket {socket_path}\nForeground yes\nDatabaseDirectory {database}\nMaxThreads 5\nMaxQueue 100\nDisableCache yes\nScanArchive yes\nMaxFileSize 100M\nMaxScanSize 400M\nMaxScanTime 120000\nAlertExceedsMax yes\nAlertEncrypted yes\n')
            with (scratch / f'{policy}-{trial}.log').open('w') as log:
                daemon = subprocess.Popen([str(runtime / 'sbin/clamd'), f'--config-file={config}'], stdout=log, stderr=log, env=env)
                try:
                    for _ in range(1200):
                        if daemon.poll() is not None:
                            raise RuntimeError('Daemon failed; inspect scratch logs')
                        try:
                            with socket.socket(socket.AF_UNIX) as connection:
                                connection.connect(str(socket_path))
                                connection.sendall(b'zPING\0')
                                if b'PONG' in connection.recv(64):
                                    break
                        except OSError:
                            time.sleep(.05)
                    else:
                        raise RuntimeError('Daemon did not become ready')

                    def scan(file_list):
                        result = subprocess.run([str(runtime / 'bin/clamdscan'), f'--config-file={config}', '--stdout', '--verbose', '--no-summary', f'--file-list={file_list}'], capture_output=True, text=True, env=env, timeout=180)
                        assert result.returncode == 0, (result.stdout, result.stderr)
                        return sum(line.endswith(': OK') for line in result.stdout.splitlines())

                    started = time.perf_counter()
                    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as workers:
                        completed = sum(workers.map(scan, plans[policy]['lists']))
                    duration = time.perf_counter() - started
                    assert completed == 1024, completed
                    results.append({'policy': policy, 'trial': trial, 'matching_seconds': duration, 'files': completed, 'batches': len(plans[policy]['lists'])})
                    print(results[-1], flush=True)
                finally:
                    daemon.terminate()
                    daemon.wait(timeout=15)
    report = {'baseline': args.baseline, 'official_database': args.database is not None, 'inventory_seconds': preparation, 'skewed_matching': results}
    (scratch / 'results.json').write_text(json.dumps(report, indent=2))
    print(f'Results and fixtures: {scratch}')


if __name__ == '__main__':
    main()
