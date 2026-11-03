# Manual worker benchmark

Measured on 2026-10-24 with the bundled ClamAV 1.5.4 runtime on this Apple silicon Mac. The app’s byte-balanced inventory was split into the requested number of concurrent file-list clients; the daemon allowed that worker count plus one spare thread. Quiet also lowers priority in the app; this benchmark isolates worker counts rather than QoS.

The small-file corpus contains 256 harmless files of about 64 KiB each. The archive corpus contains 24 ZIPs, each with approximately 1.7 MB of harmless text. Three scans ran per corpus/daemon. The first scan and the median of the two repeats are shown separately; filesystem and ClamAV caches affect repeat timings.

| Scan workers | Small first (s) | Small repeat (s) | ZIP first (s) | ZIP repeat (s) | Peak daemon MB |
|---|---:|---:|---:|---:|---:|
| 1 | 0.2021 | 0.1653 | 0.3517 | 0.0218 | 26.6 |
| 2 | 0.1133 | 0.0856 | 0.2126 | 0.0176 | 28.9 |
| 4 | 0.0652 | 0.0530 | 0.1371 | 0.0163 | 32.6 |
| 8 | 0.0530 | 0.0488 | 0.1140 | 0.0218 | 37.0 |

The measurements support keeping Balanced at four workers, with eight available in Fast mode for workloads that benefit. Extra workers also increase memory and process overhead. Balanced therefore caps at four while Fast remains available. Hardware, thermal conditions, file types, and real database size can change the best choice.

**Scope:** these fixtures use one harmless test signature, not the official malware database. Memory figures substantially understate a normal full-database scan. The results validate worker coordination and provide a relative synthetic comparison; they are not advertised real-world throughput, battery, or memory guarantees. CPU usage is recorded by the manual script, but battery impact has not been measured. Use History to compare representative scans on your own Mac.


# 1.2.1 comparison against released 1.2.0

Measured November 3, 2026, on this Apple silicon Mac. Baseline: published 1.2.0 source at `e856d96e31eff0e18a5f01740762ad6f80d5b5f5`; candidate: 1.2.1. Both use ClamAV 1.5.4. The console, scan modes, and coverage settings are preserved.

## Changes

1. Prefetch readability during directory enumeration instead of issuing a separate permission lookup per file.
2. Keep a bounded shared queue of byte-balanced batches, with no more than the configured number of simultaneous scanner clients. For four workers, small inventories retain four lists; larger inventories grow to at most 32. Workers pull another batch when ready. Maximum configuration: 12 workers, 96 lists, and under 12 MiB of list buffers before flushing. The definition database remains shared by one daemon.
3. Keep worker lanes accurate as additional work is assigned. Compare each completed batch's result count with its inventory count. Report missing or duplicate results as unconfirmed coverage; retain worst exit status across all batches assigned to a lane.
4. Record preparation, scanner-startup, and file-scanning durations in new history entries and exported reports. Existing history entries do not require migration.
5. Retain inventory files for cleanup in the serial fallback and guard engine-update checks against starting during active scans/definition updates.

## Measured results

| Workload / measured stage | 1.2.0 | 1.2.1 | Reduction |
| --- | ---: | ---: | ---: |
| Inventory of 20,000 readable 512-byte files, six alternating-order trials, median | 0.436s | 0.223s | 49% |
| Uneven 1,024-file workload, harmless test signature, three alternating-order trials, median matching time | 3.820s | 1.368s | 64% |
| Same workload with full official definitions, confirmation after compilation finished, two trials per policy | 18.810s | 6.858s | 64% |

The full-database confirmation uses daily **28173**, main **63**, and bytecode **339**, freshly downloaded and tested in isolated storage. The average of each policy's two confirmation trials is shown. An earlier three-trial full-database run gave similar results (18.734s versus 6.940s); use the confirmation measurements because earlier trials overlapped build activity.

All scans accounted for exactly 1,024 file results. These timing measurements use the actual baseline and candidate inventory functions, the bundled engine, and the same four-client limit. Daemon startup is excluded from matching timings; a fresh daemon is launched for each scan and its hash cache is disabled in both configurations to avoid cross-policy cache advantages. The app's default engine cache remains enabled.

The uneven fixture deliberately places 128 expensive ZIPs into one baseline queue. Each has the same 32 KiB on-disk length as the cheap files, but expands to several MiB of harmless text. This models a failure of byte-size estimates to predict inspection cost. It is an intentionally skewed scheduling diagnostic, not a representative customer disk. The candidate uses 16 batches for this corpus. The other 896 files remain cheap to inspect. The complete database changes detection cost but does not make this fixture a full-disk scan.

Preparation tests use a warm filesystem cache, no optional incremental reuse, identical settings and exactly 20,000 candidates in both implementations. CPU, disk, file mix, permissions, archives, power mode, and definition changes affect actual results. No full-disk duration, battery benefit, or Intel-hardware runtime improvement is claimed. Both architectures compile; execution checks ran on Apple silicon.

## Reproduce

```sh
# Default uses a harmless test signature and preserves its scratch fixtures.
python3 Scripts/CompareScanPerformance.py

# Use an existing full definition database without updating it.
python3 Scripts/CompareScanPerformance.py --database /path/to/Database

# Matching-only confirmation after builds finish.
python3 Scripts/CompareScanPerformance.py --database /path/to/Database --trials 2 --skip-inventory-timing
```

The benchmark accepts `--sdk` for an explicit installed macOS SDK and `--baseline` for another comparison commit. It creates private temporary fixtures and an isolated daemon; it does not scan customer folders or modify installed definitions. Timings and fixture paths are printed; aggregate measurements from this review are preserved in [Benchmarks/1.2.1-results.json](Benchmarks/1.2.1-results.json).

## Validation

Eleven regression tests pass: bounded/exact-once scheduling; retained worker totals/errors; candidate coverage, permissions and list counts; small-scan and serial behavior; hidden, recursion and size filters; inventory cancellation; same-size content replacement invalidating reuse; old history decoding; a real 1,001-file engine scan with a harmless detection; missing-result refusal; and cancellation that does not launch waiting batches. The separate engine validation also checks archive inspection and the archive opt-out.

Local validation used the installed macOS 26.5 SDK because the default command-line SDK lacks a SwiftUI macro component. Tests used the installed Xcode testing frameworks. Both shipping architectures still target macOS 14 or later. App and extracted-package signatures are checked with deep/strict ad-hoc verification; signing and notarization policy is unchanged from 1.2.0.

## Remaining opportunity

A real full-disk trace is still needed to identify the next dominant cost. Preparation is faster, but enumeration still completes before matching begins so progress can retain an exact total. Streaming inventory into a bounded queue is the next architectural candidate if preparation remains substantial. A single very expensive archive still has to finish its own inspection; additional workers cannot split that one file's parser work. Keep archive inspection, hidden-file coverage, and explicit skipped/incomplete reporting intact when evaluating further changes.
