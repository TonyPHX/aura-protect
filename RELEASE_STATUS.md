# Aura Protect 1.2.12 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.12) · [Wiki release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes).

- Tag v1.2.12 points to source commit `1fb06d5e49901413ad738fc7bb544e532122977f` from PR #13.
- The extracted app reports 1.2.12, includes arm64 and x86_64, passed deep strict signature verification, and bundles ClamAV 1.5.5.
- GitHub reports the matching ZIP SHA-256 `221193229e8baa7f8a8bab655e9b1ea97bcab3ac9dc18a5d5389e295bf091507`. The companion checksum file is published.
- Twenty-one tests passed. The parallel ClamAV integration test could not start its daemon in the test environment. Intel was cross-compiled.

# Aura Protect 1.2.11 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.11) · [Wiki release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes).

- Tag v1.2.11 points to source commit `70fc706098e90ab913d952ebef1c0f77f0c3d93f` from PR #12.
- The extracted app reports 1.2.11, contains arm64 and x86_64, passed strict deep signature verification, and bundles ClamAV 1.5.5.
- GitHub reports the matching ZIP SHA-256 `7bc1a586000209234abcde019d547ca382f7c33210d418ea6290587aae1fa252`. The companion checksum is published.
- Twenty-one tests passed, including the parallel input regression. The real ClamAV parallel test could not start its daemon in the test environment. Intel was cross-compiled.

# Aura Protect 1.2.10 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.10) · [Wiki release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes).

- Tag v1.2.10 points to source commit `acd7f298c82cadaf6cfa2c4e29362638bce13c1a` from PR #11.
- The extracted app reports 1.2.10, includes arm64 and x86_64, passed deep and strict signature verification, and bundles ClamAV 1.5.5.
- GitHub reports ZIP SHA-256 `7af9e354425ef6c7387c7c0dad0352e229dd39ac79df7701a7e11b4532980094`, matching the verified local ZIP. The companion checksum file is published.
- Twenty tests passed. The pause regression verified queued input order after resume. The real parallel ClamAV integration test could not start its daemon in the test environment. Intel was cross-compiled.
- The wiki documents pause and resume, updates current guides and navigation, and keeps older version details in historical pages.

# Aura Protect 1.2.9 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.9) · [Wiki release notes](https://github.com/TonyPHX/aura-protect/wiki/Release-Notes).

- Tag v1.2.9 points to source commit `f533a8d4d3afe303fcba9975527a86db68dfccc1` from PR #10.
- The extracted app reports 1.2.9, includes arm64 and x86_64, passed deep and strict signature verification, and bundles ClamAV 1.5.5.
- GitHub reports ZIP SHA-256 `f9fcce139fdc97681f7419fe47e18bf41be6632a071cf05cb00dd5d379aec71d`, matching the verified local ZIP. The companion checksum file is published.
- Nineteen tests passed, including the history regressions. One parallel ClamAV test failed at daemon startup in the test environment. Intel was cross-compiled.

# Aura Protect 1.2.8 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.8).

- Tag v1.2.8 points to source commit `ca077df`.
- The extracted universal app reports version 1.2.8, contains both Mac architectures, and passed deep, strict signature verification. The bundled engine reports ClamAV 1.5.5.
- The uploaded ZIP SHA-256 matches `14c21ba938cf7904fb6fb957c9e259fa20751d610f1883700a400bc99e9487a0`.
- Eighteen tests passed. The parallel daemon test was skipped because the environment blocks its Unix socket. Full-disk performance was not benchmarked.
- Wiki commit `3a5d8e9` documents discovery, timing, and the reuse default.

# Aura Protect 1.2.7 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.7).

- Tag v1.2.7 points to source commit `fe1a85d`.
- The universal macOS ZIP passed extraction, version, and deep signature checks. GitHub reports the matching SHA-256 `db2655a9a69e288841a72f325462a105c78c69aa08ca5321e69edb785aac7fd3`. The bundled ClamAV reports 1.5.5.
- Sixteen tests passed. The daemon integration test was excluded because the environment blocks its Unix socket.
- Wiki commit `0748e80` documents the unified Scan page, Entire Disk preset, and About & Licenses version display.

# Aura Protect 1.2.6 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.6).

- Tag v1.2.6 points to source commit `6f1362b`.
- The uploaded universal macOS ZIP matches the locally verified SHA-256 `cb37939b4f21982a55e4c2a4fa13881ec0f87f0273c6b21e9e7b2893a9b257bc`. The extracted app passed deep, strict signature verification and reported ClamAV 1.5.5.
- Sixteen tests passed. The daemon integration test was excluded because the environment blocks its Unix socket.
- Wiki commit `ac3ebc3` documents the live file counter and flag fade-in.

# Aura Protect 1.2.5 release verification

[GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.5).

- Tag v1.2.5 points to source commit `e1a84b0`.
- The uploaded universal macOS ZIP matches the locally verified SHA-256 `882f92e1eeb0aabef9c029b3837fb448753327501dc00befaa46c59224682878`. The extracted app passed deep, strict signature verification and reported ClamAV 1.5.5.
- Sixteen tests passed. The daemon integration test was excluded because the environment blocks its Unix socket.
- Wiki commit `cd02486` documents the release and flag animation.

# Aura Protect 1.2.4 release verification

Published November 22, 2026. [GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.4).

- Tag v1.2.4 points to source commit `92d26a1`.
- The uploaded universal macOS ZIP matches the locally verified SHA-256 `536c88df68d3b60c67fc1def2e0567c0a608e7e4c12ceb76234bc48abaa9edc7`. The extracted app passed deep, strict signature verification for both architectures and reported ClamAV 1.5.5.
- Sixteen tests passed, including a real-engine check that a file result arrives before the scan input closes. The daemon integration test could not start because the environment blocked its Unix socket.
- Wiki commit `fa12d21` documents the release, streaming discovery, and the updated console behavior.

# Aura Protect 1.2.3 release verification

The macOS candidate bundles ClamAV 1.5.5. The installer SHA-256 matched the
checksum in Cisco-Talos's GitHub release metadata. macOS reported an invalid
installer signature during verification. The installer was extracted without
being run. The bundled binaries were then signed and verified using Aura
Protect's ad-hoc signing workflow.

The local 1.2.3 app built for arm64 and x86_64 and passed deep, strict code
signature verification. The scanner reported 1.5.5 on Apple silicon and
under Intel translation.
Serial checks covered clean files, a harmless positive detection, archive
inspection, and archive opt-out. Fifteen Swift tests passed. The parallel
daemon integration test is pending because this session could not bind the
daemon's Unix socket.

Published November 22, 2026. [GitHub release](https://github.com/TonyPHX/aura-protect/releases/tag/v1.2.3).
The release tag targets source commit `5771c6e`. The uploaded universal ZIP
matched the verified local ZIP SHA-256
`2c93ba735b0906939017d03b0ff55fbc4d49176e518f6e0d26ea004b2a5cb845`.
The companion checksum file is published. Wiki commit `353cb4f` updates
Home, Getting Started, Release Notes, Results and Quarantine, and Engine and
Definition Updates.

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
