# Manual release housekeeping

Keep the source, downloadable app, and wiki in sync for each release. This is a manual checklist, not build automation. Aura uses ad-hoc signing; Developer ID signing and notarization are outside this workflow.

1. Confirm the intended changes are complete and the app version in `build_app.sh` is correct. If the bundled ClamAV runtime changes, update `README.md`, `THIRD_PARTY_NOTICES.md`, `Vendor/ClamAV/NOTICE.txt`, certificates, and applicable upstream license notices together.
2. Build the intended Mac architectures and record which were actually exercised. Package the app, verify its version and ad-hoc signature, extract the final ZIP, verify it again, and record the ZIP's SHA-256. Document functional validation and its limits without calling an untested path verified.
3. Merge the reviewed source change into `main`. Confirm the final source tree matches the build and that obsolete PRs are closed without dropping unique work.
4. Tag the exact release commit and publish the matching versioned Mac ZIP on GitHub Releases. Check the release is published, the expected asset is uploaded, its checksum matches, and the correct release is marked latest.
5. Update the separate GitHub wiki repository at `https://github.com/TonyPHX/aura-protect.wiki.git`:
   - Add the new entry to **Release Notes**, preserving historical entries.
   - Refresh **Home**, **Getting Started**, scan/settings instructions, results/recovery, troubleshooting, updates, background behavior, and privacy details as affected.
   - Update `_Sidebar.md` if pages are added. Check all internal page links.
   - Commit and push the wiki; source-repository commits do not update it automatically.
6. Link the current user guide and wiki release notes from the GitHub release. Confirm README download/wiki links still work and descriptions reflect the shipped behavior.
7. Verify remote `main`, release tag, published asset, wiki commit, and open PR status. Report any remaining manual setup or validation limits. Documentation-only follow-ups need not rebuild or retag an unchanged app.
