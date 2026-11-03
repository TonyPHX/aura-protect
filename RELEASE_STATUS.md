# Aura Protect 1.2.2 publication status

Prepared November 3, 2026, from the published 1.2.1 source and documentation closeout (`dac62d82011306cec1f58a97940e1a39e05517a2`). Publication and final remote verification are in progress.

## Validation

- New native Status dashboard: live speed, session average/peak, progress instruments, bounded throughput trace, readiness controls, and result counts.
- Fifteen tests pass: four dashboard telemetry/range checks plus the eleven existing coverage, cancellation, cache, history and real-engine regressions.
- Native wide, compact, and idle/partial-access previews rendered and inspected; illustrative preview data is confined to the separate renderer, not the app.
- Reduce Motion disables needle transitions. The dashboard consumes the existing telemetry samples without an animation timer or fabricated throughput.
- ClamAV remains 1.5.4; scanner/coverage/quarantine behavior and the 1.2.1 scheduler are preserved.

Final universal package checksum, release tag, published asset, and wiki commit will be recorded after publication. Runtime validation is on Apple silicon; Intel is cross-compiled. Signing remains ad-hoc.

Verified universal ZIP: `Aura-Protect-1.2.2-macOS.zip`. SHA-256: `472e596a24e8e82cbc51750c6ae97856992a94d3051767528301d54e6316dbeb`. Extracted package version, architectures, Finder registrations, and deep/strict signature checked.
