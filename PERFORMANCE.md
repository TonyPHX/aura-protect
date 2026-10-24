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
