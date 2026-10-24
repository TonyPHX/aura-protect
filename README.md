# Aura Protect

A fast native macOS ClamAV front end. The official universal ClamAV runtime is bundled; Homebrew is not required.

The Aura Protect artwork in `Assets` is packaged as the application, Finder, and Dock icon.

## Build

```sh
chmod +x build_app.sh
./build_app.sh
```

Open `outputs/Aura Protect.app`. The app uses its bundled ClamAV engine and can also discover external installations.

The bundled runtime is ClamAV 1.5.4 from the official Cisco-Talos release. Its source, verified package digest, and GPLv2 license are recorded under `Vendor/ClamAV` and included in the app bundle.

## Safety

Detected files are reported but never automatically deleted or moved. Review detections before taking action; false positives are possible.

## Open source and attribution

Aura Protect is free and open-source software licensed under the [GNU General Public License, version 2 only](LICENSE). Copyright © 2026 Tony Simek and Aura Protect contributors.

Aura Protect is powered by [ClamAV](https://www.clamav.net), which is maintained by the ClamAV Team and Cisco Systems, Inc. The bundled ClamAV 1.5.4 runtime is licensed under GPLv2; its corresponding [source code](https://github.com/Cisco-Talos/clamav/tree/clamav-1.5.4), license, and official third-party notices are identified in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `Vendor/ClamAV/licenses`.

Aura Protect is an independent community project and is not affiliated with, sponsored by, or endorsed by Cisco Systems or the ClamAV project. Product names and trademarks belong to their respective owners.

## Aura Protect 1.1.9

- ClamAV 1.5.4 is bundled. Scanning remains available with a working installed engine and databases when online update checks fail. Updates shows the last successful definition check; protected folders still require Full Disk Access.
- Quiet, Balanced, and Fast modes offer 1, up to 4, and up to 8 scan workers respectively. Automatic tuning also respects CPU/RAM, Low Power Mode, and high thermal pressure. Byte-balanced concurrent queues feed the warm daemon, with a spare daemon thread budgeted for coordination. Quiet lowers process priority. Manual worker selection is available outside Quiet mode.
- Optional clean-result reuse checks file contents with SHA-256 and stable metadata before and after scanning. Changes to any database file, engine executable/version, or scan-affecting setting invalidate reuse. Hashing adds I/O, so leave this option off if it does not improve your workload.
- Encrypted files and files that reach inspection limits are reported as incomplete rather than confirmed clean or malware. Skipped, incomplete, scanned, and reused counts remain separate. Filenames containing line breaks are explicitly skipped because the command-line result protocol cannot safely represent them.
- Quarantine includes the detection name, digest, original location, and recovery metadata. Files changed since detection are refused. Restore requires confirmation, never overwrites an existing file, and preserves the original ordinary permission bits. Legacy records remain readable.
- History keeps the most recent 100 completed scans privately on this Mac, including duration, mode, worker count, result counts, and detections. Elapsed time includes inventory and scanner startup.
- Scan presets cover Downloads, Desktop, and Applications. Finder can send files/folders using **Services → Scan with Aura Protect**, after the built app has been launched and macOS registers its service. It may need enabling in System Settings → Keyboard → Keyboard Shortcuts → Services. Open With is also supported. Multiple requests are queued.
- Optional Downloads monitoring and daily scheduled scans run **only while Aura is open**. Monitoring covers new or changed regular files directly inside Downloads, waits for stable size/date across two checks, and ignores common partial-download extensions. Existing files and subfolders are not swept automatically. This is scanning after download, not access blocking.
- Background requests wait for readiness and idle time. Detected files are never moved automatically, and further background scans pause until detections are quarantined or explicitly marked reviewed. Settings can clear waiting requests. A daily scan runs once after the chosen local hour when Aura is available.
- Engine updates verify the published SHA-256 and the Cisco installer identity, then smoke-check all runtime programs before activation. The previous runtime is retained and can be restored from Updates. A publisher certificate identity change will require a reviewed app update.

The app continues to use ad-hoc signing. No Developer ID/notarization or automated build/test pipeline is configured.

## Manual performance measurements

Run `python3 Scripts/BenchmarkScanner.py` to compare 1/2/4/8 workers using harmless local fixtures and an isolated daemon. It prints timings, peak daemon memory, and the scratch directory. This is an opt-in developer tool, not a scheduled benchmark or an automated test suite. See [PERFORMANCE.md](PERFORMANCE.md) for results and limits.

Build options can be passed through to SwiftPM, for example `./build_app.sh --build-system native`. On hosts whose command-line tools lack SwiftUI macros, use a compatible Xcode toolchain or pass the installed matching plugin with `-Xswiftc -load-plugin-library -Xswiftc /path/to/libSwiftUIMacros.dylib`.
