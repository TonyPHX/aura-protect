# Aura Protect 1.2.1 release verification

Published November 3, 2026. **Release housekeeping completed.**

- Release: https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.1
- Latest published release verified as `v1.2.1`, not a draft or prerelease.
- Source merged through PR #6; release tag targets `ba37da646b40e29c7eb05c56e51926084f4baad0`.
- Universal asset: `Aura-Protect-1.2.1-macOS.zip`; uploaded size 34,947,318 bytes.
- Uploaded asset SHA-256 matches the extracted/verified local package: `9da98888a155dbfb07e5462db4f693be4ad0e29d163a06e0eda8f892dd6e1d9e`.
- Companion checksum file is uploaded with the release.
- Release body links the user guide, wiki Release Notes, performance guide, and tagged methodology.
- Wiki release commit: `5a71557` — Home, Getting Started, Release Notes, scan/console instructions, results/history, troubleshooting, sidebar, and housekeeping promoted to published 1.2.1. Internal links checked.
- Main/tag executable source matches the tested build. This final status update is documentation-only and does not require rebuilding or retagging.
- Release PR is merged. The final housekeeping PR is merged as part of publication closeout; no release-related PR is intentionally left open.

## Validation retained from the release build

Eleven regression tests, real-engine/archive checks, optimized arm64/x86_64 builds, and extracted universal ZIP verification passed. Executed on Apple silicon; Intel was cross-compiled. Finder registrations and deep/strict ad-hoc signature were checked. ClamAV remains 1.5.4.

The 1.2.0 console and existing features are preserved. PERFORMANCE.md and Benchmarks/1.2.1-results.json document roughly 49% less preparation time and 64% less matching time on targeted fixtures. These are not full-disk, battery, or Intel runtime guarantees.

The superseded pre-1.2.0 experiment remains saved separately. Existing Windows and other unrelated untracked work was not included. No publication step remains outstanding.
