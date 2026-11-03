# Aura Protect 1.2.2 release verification

Published November 3, 2026. **Release housekeeping completed.**

- Release: https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.2
- Latest stable release verified as `v1.2.2`, not draft or prerelease.
- Source merged through PR #8; release tag targets `0450589e34a0c197ef0351b053638df16851deee`.
- Published universal ZIP: `Aura-Protect-1.2.2-macOS.zip`, 35,173,083 bytes.
- Uploaded digest matches the extracted and verified local package: `472e596a24e8e82cbc51750c6ae97856992a94d3051767528301d54e6316dbeb`.
- Companion checksum file is published. Release body links the dashboard guide, user guide, and Release Notes.
- Wiki release commit: `902ce73` — Status Dashboard guide/native preview, Home, Getting Started, Release Notes, scan/console/troubleshooting guidance, sidebar, and housekeeping updated together. Internal page/image links checked.
- Native preview figures are explicitly illustrative and confined to the separate renderer. The application uses actual scan observations; no preview image or synthetic readings are embedded in the app.
- Main/tag executable source matches the verified build; final closeout changes only documentation. Release and documentation closeout PRs are merged; no release-related PR is intentionally left open.

## Validation and measurement behavior

Fifteen tests pass: four dashboard measurement/range/peak/reset checks plus the eleven existing real-engine, cancellation, coverage, cache, history, and scheduler regressions. Native wide/compact/idle/partial-access previews were rendered and inspected. Button contrast, status-card balance, and database labels were checked in the native renders.

Optimized arm64 and x86_64 builds pass. The ZIP was extracted and its version, both executable architectures, Finder registrations, and deep/strict ad-hoc signature verified. Runtime checks ran on Apple silicon; Intel was cross-compiled. Signing/notarization policy is unchanged.

Live files/second and average use observed file completions and monotonic elapsed intervals. Speed dials share a visible adaptive range. Session peak is retained after chart eviction, and measurements reset for each new scan. The existing bounded sample stream is reused with no new animation timer. Reduce Motion disables needle transitions.

ClamAV remains 1.5.4. The Scan Console, 1.2.1 scheduler, coverage, quarantine/recovery, updates, and background behavior are preserved. This is a visibility/graphics update, not an additional throughput or CPU-utilization claim. Existing Windows and unrelated untracked work was not included. No publication step remains outstanding.
