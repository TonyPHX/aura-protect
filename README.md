# Aura Protect

A fast native macOS ClamAV front end. The official universal ClamAV runtime is bundled; Homebrew is not required.

The Aura Protect artwork in `Assets` is packaged as the application, Finder, and Dock icon.

The macOS Scan page brings target selection, live progress, worker queues, throughput, and scanner readiness into a single view. Expand the readiness row for engine, definitions, Full Disk Access, and worker checks.

## Download and user guide

- [Latest Mac release](https://github.com/TonyPHX/aura-protect/releases/latest)
- [User guide and release notes](https://github.com/TonyPHX/aura-protect/wiki)
- [Manual release housekeeping checklist](RELEASING.md)

## Build

```sh
chmod +x build_app.sh
./build_app.sh
```

Open `outputs/Aura Protect.app`. The app uses its bundled ClamAV engine and can also discover external installations.

The bundled runtime is ClamAV 1.5.5 from the official Cisco-Talos release. Its source, verified package digest, and GPLv2 license are recorded under `Vendor/ClamAV` and included in the app bundle.

## Safety

Detected files are reported but never automatically deleted or moved. Review detections before taking action; false positives are possible.

## Open source and attribution

Aura Protect is free and open-source software licensed under the [GNU General Public License, version 2 only](LICENSE). Copyright © 2026 Tony Simek and Aura Protect contributors.

Aura Protect is powered by [ClamAV](https://www.clamav.net), which is maintained by the ClamAV Team and Cisco Systems, Inc. The bundled ClamAV 1.5.5 runtime is licensed under GPLv2; its corresponding [source code](https://github.com/Cisco-Talos/clamav/tree/clamav-1.5.5), license, and official third-party notices are identified in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `Vendor/ClamAV/licenses`.

Aura Protect is an independent community project and is not affiliated with, sponsored by, or endorsed by Cisco Systems or the ClamAV project. Product names and trademarks belong to their respective owners.

## Aura Protect 1.2.11

[Download 1.2.11](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.11) · [Scan guide](https://github.com/TonyPHX/aura-protect/wiki/Running-a-Scan)

- Fixed a resume issue where one full worker pipe could leave other parallel scan workers idle.
- Added **Scan Home Folder (username)** as the first Quick Targets option. Your macOS home folder is selected when the app opens.

## Aura Protect 1.2.10

[Download 1.2.10](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.10) · [Scan guide](https://github.com/TonyPHX/aura-protect/wiki/Running-a-Scan)

Use **Pause Scan** to suspend inspection while file discovery continues. Choose **Resume Scan** to continue the same scan, or **Cancel Scan** to stop.

## Aura Protect 1.2.9

[Download 1.2.9](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.9) · [Release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes)

Scan History has controls for saving future results and clearing existing entries. History labels failed scans and reports local storage errors. The American flag stays visible in About & Licenses, with fireworks after the first completed scan.

## Aura Protect 1.2.8

[Download 1.2.8](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.8) · [Release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes)

File discovery overlaps scanner startup and feeds ClamAV in small batches. History and exported reports break out discovery, input delivery, and time to first result. Clean-file reuse defaults on when no preference has been saved.

## Aura Protect 1.2.7

[Download 1.2.7](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.7) · [Release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes)

Quick targets includes **Scan Entire Disk**. **About & Licenses** shows the installed app version.

## Aura Protect 1.2.6

[Download 1.2.6](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.6) · [Release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes)

The Performance Cockpit shows a digital **Files Scanned** counter. It updates during file discovery and keeps the final count visible after the scan. The About & Licenses flag now fades in with a blue-white shimmer.

## Aura Protect 1.2.5

[Download 1.2.5](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.5) · [Release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes)

The About & Licenses scan-completion flag now has a fireworks animation and stays visible until the app quits.

## Aura Protect 1.2.4

[Download 1.2.4](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.4) · [Release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes)

Scans begin during file discovery. About & Licenses includes a flag that reveals as a scan progresses.

## Aura Protect 1.2.3

[Download 1.2.3](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.3) · [Release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes)

Bundles ClamAV 1.5.5, explains scan coverage gaps, and validates downloaded engines before activation.

## Aura Protect 1.2.2 — Status dashboard

[Download 1.2.2](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.2) · [Status dashboard guide and native preview](https://github.com/TonyPHX/aura-protect/wiki/Status-Dashboard)

This release introduced the Status page as a native performance cockpit with three speedometer-style instruments: recent files per second, session-average files per second with a peak-interval reading, and eligible-inventory completion. It also shows a bounded recent-minute throughput trace, file activity, elapsed/estimated remaining time, result counts, scan-client availability, and engine/definition/access controls.

Rates come from observed file completions and monotonic elapsed intervals. The two speed dials share a visible adaptive range. Average speed covers scan-client processing through the last sample and excludes inventory/startup; peak is the highest observed interval across the session. Idle/preparation states have no invented speed, and a stopped scan is labeled. Retained last-session measurements stay distinct from live telemetry. Active clients do not imply CPU utilization.

The graphite/cyan/blue/violet design supports compact windows, readable status distinctions, keyboard buttons, accessibility labels, and Reduce Motion. Rendering uses native SwiftUI/Canvas and the existing bounded telemetry; no animation timer or synthetic activity stream was added. Quarantine, update safeguards, scan coverage, and the 1.2.1 scan scheduler remain unchanged. Fifteen tests cover telemetry and existing scan regressions. Native wide/compact/idle previews use explicitly labeled illustrative figures and are not embedded in the application.

## Aura Protect 1.2.1

Based on the published 1.2.0 source, preserving the graphical console, content-verified reuse, quarantine/recovery, Finder integration, offline readiness, and opt-in background scans.

- Large scans use a shared queue of smaller, byte-balanced batches. A worker takes another batch as soon as it finishes, reducing idle time when files have different inspection costs. The number of active workers still follows Quiet/Balanced/Fast and power/thermal limits. Small scans retain one batch per worker.
- Directory readability is prefetched with file metadata instead of checked separately for every file. Temporary lists are created only for batches that contain files.
- History and exported reports separate inventory preparation, scanner startup, and file-scanning time. Old history remains readable. Worker lanes show completed versus assigned files; additional batches are assigned while scanning.
- Each batch's returned file count is checked against the inventory. Missing results produce an error instead of a clean completion. Cancellation stops pending batches from launching.
- ClamAV 1.5.4 remains bundled and was confirmed as the latest stable engine on November 3, 2026. New definition downloads continue through the existing updater.
- The build script now builds and packages both Mac architectures explicitly.

[Download Aura Protect 1.2.1](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.1).

In targeted local comparisons against 1.2.0, inventory preparation improved by about 49%. A deliberately uneven 1,024-file workload improved from 18.81s to 6.86s with a freshly updated full ClamAV database. These are fixture results, not a guaranteed full-disk speedup. See [PERFORMANCE.md](PERFORMANCE.md) for methodology, limits, and reproducible measurements.

Run `swift test -c release` with a complete compatible Xcode toolchain. The suite includes a harmless real-engine scan, cancellation, coverage accounting, cache safety, and old-history compatibility. `python3 Scripts/ValidateEngine.py` checks clean files, detections, and archive inspection in isolated storage. Tests do not change the installed app, its definitions, or scan history.

## Aura Protect 1.2.0 scan console

The Scan screen now uses a native dark science-console design with cyan, amber, and muted violet accents. A segmented ring shows completed files against the known inventory; inventory preparation stays indeterminate until that total is available.

The console measures recent file completions per second, elapsed time, an approximate ETA, and actual worker-queue completion. The recent-minute chart retains at most 61 samples and updates at most once per second, plus a final partial interval. File activity is labeled **Current File** only when ClamAV reports a scanning event; otherwise it is **Last Reported File**. Long paths truncate with the full path available on hover.

Detections, skipped files, incomplete inspections, operational errors, and reused results stay separate. Start/Cancel controls remain visible while scrolling, narrow windows use a stacked layout, and ring/queue transitions respect macOS Reduce Motion. These graphics are drawn in SwiftUI; no generated mockup image is embedded in the app. Other screens keep their native appearance. Quarantine remains manual.

## Aura Protect 1.1.9

- ClamAV 1.5.4 is bundled. Scanning remains available with a working installed engine and databases when online update checks fail. Updates shows the last successful definition check; protected folders still require Full Disk Access.
- Quiet, Balanced, and Fast modes offer 1, up to 4, and up to 8 scan workers respectively. Automatic tuning also respects CPU/RAM, Low Power Mode, and high thermal pressure. Byte-balanced concurrent queues feed the warm daemon, with a spare daemon thread budgeted for coordination. Quiet lowers process priority. Manual worker selection is available outside Quiet mode.
- Optional clean-result reuse checks file contents with SHA-256 and stable metadata before and after scanning. Changes to any database file, engine executable/version, or scan-affecting setting invalidate reuse. Hashing adds I/O, so leave this option off if it does not improve your workload.
- Encrypted files and files that reach inspection limits are reported as incomplete rather than confirmed clean or malware. Skipped, incomplete, scanned, and reused counts remain separate. Filenames containing line breaks are explicitly skipped because the command-line result protocol cannot safely represent them.
- Quarantine includes the detection name, digest, original location, and recovery metadata. Files changed since detection are refused. Restore requires confirmation, never overwrites an existing file, and preserves the original ordinary permission bits. Legacy records remain readable.
- History can keep up to 100 scan results on this Mac, including outcome, duration, mode, worker count, result counts, and detections. Use **Save scan history** to control future entries or **Clear All History…** to delete saved entries. Elapsed time includes inventory and scanner startup.
- Scan presets cover Downloads, Desktop, and Applications. Finder can send files/folders using **Services → Scan with Aura Protect**, after the built app has been launched and macOS registers its service. It may need enabling in System Settings → Keyboard → Keyboard Shortcuts → Services. Open With is also supported. Multiple requests are queued.
- Optional Downloads monitoring and daily scheduled scans run **only while Aura is open**. Monitoring covers new or changed regular files directly inside Downloads, waits for stable size/date across two checks, and ignores common partial-download extensions. Existing files and subfolders are not swept automatically. This is scanning after download, not access blocking.
- Background requests wait for readiness and idle time. Detected files are never moved automatically, and further background scans pause until detections are quarantined or explicitly marked reviewed. Settings can clear waiting requests. A daily scan runs once after the chosen local hour when Aura is available.
- Engine updates verify the published SHA-256 and the Cisco installer identity, then smoke-check all runtime programs before activation. The previous runtime is retained and can be restored from Updates. A publisher certificate identity change will require a reviewed app update.

The app continues to use ad-hoc signing. No Developer ID/notarization or automated build/test pipeline is configured.

## Manual performance measurements

Run `python3 Scripts/BenchmarkScanner.py` to compare 1/2/4/8 workers using harmless local fixtures and an isolated daemon. It prints timings, peak daemon memory, and the scratch directory. This is an opt-in developer benchmark. The regression suite is run separately with `swift test`. See [PERFORMANCE.md](PERFORMANCE.md) for results and limits.

Build options can be passed through to SwiftPM, for example `./build_app.sh --build-system native`. On hosts whose command-line tools lack SwiftUI macros, use a compatible Xcode toolchain or pass the installed matching plugin with `-Xswiftc -load-plugin-library -Xswiftc /path/to/libSwiftUIMacros.dylib`.
