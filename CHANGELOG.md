# Changelog

## 1.1.0 — 2026-08-26

- Replaced default causal rule correlation with a fact-only evidence engine. The tool now emits `Observed`, `SourceReported`, `Decoded`, and transparent `Computed` records without naming a root cause.
- Added a provider-neutral `ReviewBundle.zip` with case metadata, attempts, JSONL/CSV facts and timeline, complete Windows Update history, inventory/diff, coverage, excluded-evidence records, hashed evidence index, bounded excerpts, and a ready-to-use external-review prompt.
- Added strict setup-attempt gates for Windows Update ownership, feature-upgrade semantics, time overlap, target version/build, completed Windows image state, and contamination exclusions.
- Explicitly classifies and excludes initial deployment/imaging, diagnostic compatibility scans, general servicing, non-Windows-Update upgrades, unclassified setup evidence, and tool-generated evidence from the included upgrade timeline.
- Reordered collection so passive raw evidence is snapshotted before DISM, SFC, Appraiser refresh, media scan, or SetupDiag execution. DISM now writes to a run-owned log path and SetupDiag receives only a scoped feature-upgrade source.
- Added Windows image-state capture and richer Windows Update history provenance (`UpdateID`, revision, client application, service, and server selection where exposed).
- Fixed Windows PowerShell 5.1 launch failures for no-argument commands by omitting an empty `Start-Process -ArgumentList` binding.
- Fixed strict-mode failures on sparse uninstall and process records, including missing `DisplayName` and `Name` properties, and added script-location detail to collector/fatal errors.
- Added v1.1 regression fixtures for real upgrade, imaging, scan-only, sparse-object, contamination-order, review-bundle, and fact-only report contracts.

## 1.0.0 — 2026-08-25

- Initial 23H2 → 25H2 diagnostic companion.
- Added one-click elevated launcher and PowerShell 5.1 engine.
- Added preflight, automatic resume, forensic, and disarm modes.
- Added guarded SetupConfig hooks and SYSTEM scheduled-task persistence.
- Added Windows Setup, compatibility, servicing, update, driver, policy, management, event, crash, and inventory collectors.
- Added Microsoft-signed SetupDiag refresh and offline `/NoTel` execution.
- Added deterministic rules, phase/operation decoding, attempt inventory, timelines, confidence, and evidence references.
- Added self-contained HTML, JSON, CSV, ZIP, manifest, and checksum outputs.
- Added exact-byte SetupConfig preservation/restoration, evidence-source mappings, bounded UNC transfer, and ordinary-reboot resume gating.
- Added fixture runner, Pester tests, and Windows VM acceptance checklist.
