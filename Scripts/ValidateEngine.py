#!/usr/bin/env python3
"""Exercise bundled serial/parallel scanning with a harmless private test signature."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import time
import zipfile

RUNTIME = Path(__file__).resolve().parents[1] / 'Vendor' / 'ClamAV'
os.environ['CVD_CERTS_DIR'] = str(RUNTIME / 'etc/certs')


def run(*args, expected=0):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True, timeout=30)
    if result.returncode != expected:
        raise RuntimeError(f'{args}: exit {result.returncode}\n{result.stdout}\n{result.stderr}')
    return result.stdout


def main():
    # Keep the socket below the Unix-domain socket path length limit.
    with tempfile.TemporaryDirectory(prefix='aura-engine-', dir='/tmp') as temporary:
        root = Path(temporary).resolve()
        database = root / 'db'
        database.mkdir()
        marker = b'Aura Protect harmless regression fixture. This is not malware.\n'
        (database / 'test.hdb').write_text(f'{hashlib.md5(marker).hexdigest()}:{len(marker)}:Aura.Regression.Test\n')
        clean = root / 'clean.txt'
        clean.write_text('A clean document for scanner regression validation.\n')
        detected = root / 'detected.txt'
        detected.write_bytes(marker)
        archive = root / 'fixture.zip'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
            output.writestr('fixture.txt', marker)
        for executable in ['bin/clamscan', 'bin/clamdscan', 'bin/freshclam', 'sbin/clamd']:
            assert '1.5.4' in run(RUNTIME / executable, '--help')
        run(RUNTIME / 'bin/clamscan', f'--database={database}', clean)
        assert 'Aura.Regression.Test' in run(RUNTIME / 'bin/clamscan', f'--database={database}', detected, expected=1)
        assert 'Aura.Regression.Test' in run(RUNTIME / 'bin/clamscan', f'--database={database}', archive, expected=1)
        run(RUNTIME / 'bin/clamscan', f'--database={database}', '--scan-archive=no', archive)
        config = root / 'clamd.conf'
        config.write_text(f'LocalSocket {root / "clamd.sock"}\nLocalSocketMode 600\nDatabaseDirectory {database}\nForeground yes\nMaxThreads 4\nMaxQueue 100\nScanArchive yes\n')
        with (root / 'daemon.log').open('w') as log:
            daemon = subprocess.Popen([str(RUNTIME / 'sbin/clamd'), f'--config-file={config}'], stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if daemon.poll() is not None:
                        raise RuntimeError((root / 'daemon.log').read_text())
                    if (root / 'clamd.sock').exists():
                        break
                    time.sleep(0.1)
                file_list = root / 'files.txt'
                file_list.write_text('\n'.join(str(path) for path in [clean, detected, archive]) + '\n')
                output = run(RUNTIME / 'bin/clamdscan', f'--config-file={config}', '--multiscan', '--verbose', f'--file-list={file_list}', expected=1)
                assert f'{clean}: OK' in output, output
                assert output.count(' FOUND') == 2, output
            finally:
                daemon.terminate()
                daemon.wait(timeout=10)
        print('PASS: all four runtime tools, clean file, detection, archive inspection, archive opt-out, and parallel daemon scanning.')


if __name__ == '__main__':
    main()
