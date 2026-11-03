# Aura Protect 1.2.1 housekeeping status

Updated November 3, 2026. **Publication in progress.** The published release and remote main remain 1.2.0 at `e856d96e31eff0e18a5f01740762ad6f80d5b5f5` at the time of verification.

## Completed

- Verified the published/installed 1.2.0 baseline and preserved its graphical console and product features.
- Prepared candidate source on `codex/aura-protect-1.2.1`; retained the superseded older-checkout experiment separately.
- Confirmed bundled ClamAV 1.5.4 is current; no runtime or license version change was necessary.
- Passed eleven regression tests, real-engine/archive checks, optimized arm64/x86_64 builds, and extracted universal-package verification. Execution checks ran on Apple silicon; Intel was cross-compiled.
- Recorded reproducible measurements and limits in PERFORMANCE.md and Benchmarks/1.2.1-results.json.
- Built `Aura-Protect-1.2.1-macOS.zip`; SHA-256 `9da98888a155dbfb07e5462db4f693be4ad0e29d163a06e0eda8f892dd6e1d9e`.
- Updated wiki candidate release notes, Home, Getting Started, scan/console instructions, results/history, troubleshooting, sidebar links, and release housekeeping. Current-release download links remain on 1.2.0. Update, background, privacy, and recovery behavior did not change.

## Pending for publication

- Review and merge the candidate source into main.
- Tag the exact release commit and publish the matching verified ZIP.
- Verify remote asset digest, latest-release designation, tag/main relationship, and open PR status.
- Promote candidate wiki notes to released instructions, update public download links, and add current guide/release-note links to the GitHub release body.

Publication was authorized on November 3, 2026. Final remote release, tag, asset, and wiki verification will be recorded after publishing.
