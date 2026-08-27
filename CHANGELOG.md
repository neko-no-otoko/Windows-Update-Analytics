# Changelog

## 2.1.0 — 2026-08-26

- Added public `-Mode Finalize` for an operator-controlled end to an armed persistent recording run.
- Finalize records the operator identity, arm-expiry state, Setup-active state, and automatic terminal-signal evaluation before stopping collection.
- Added a forced `OperatorFinalizationBoundary` sample/checkpoint followed by the same full passive-first collection, fact analysis, report, archive, and owned-persistence cleanup used by automatic finalization.
- Kept automatic `Resume` safeguards unchanged: it still defers while Setup is active and still requires direct terminal evidence.
- A successful operator finalization without a directly observed terminal result remains factually labeled; the operator action never implies upgrade success or failure.
- Failed finalization attempts restart the recorder so the armed run remains retryable.
- Final collection now refuses to race a recorder that has not released its per-run lock within the bounded shutdown window.

## 2.0.0 — 2026-08-26

- Added a persistent SYSTEM progress recorder with 60-second append-only JSONL sampling, restart-on-failure behavior, cross-reboot continuity, expiry, and owned cleanup.
- Added state/build/boot/Setup-progress boundary detection and timestamped native checkpoints with per-source copy/export status, hashes, and capacity limits.
- Added first-class Delivery Optimization status, peer, current/month performance, configuration, progress percentage, source-byte, cache-share, and throughput records. Provider failures are explicit instead of silently empty.
- Preserved native Panther, rollback, Windows Update ETL, USO, Delivery Optimization, servicing, event, and crash evidence before readable conversion or active diagnostics.
- Split status into current target presence, observed build transition, attempt outcome, and deployment provenance. A current 25H2 device without retained provenance now reports `Target OS Present`, not `Unknown`.
- Added source-reported Setup phase segmentation for recent run-window Downlevel, SafeOS, FirstBoot, and OOBE markers; historical imaging logs cannot activate a phase by themselves.
- Replaced ambiguous process warnings with explicit `Succeeded`, `ExitedNonzero`, `TimedOut`, `StartFailed`, `ExitCodeUnavailable`, and `ArtifactCapturedDespiteProcessUncertainty` results, including PID, deepest error, and artifact change evidence.
- Added `RecorderSummary.json`, `ProgressSamples.jsonl`, `StateTransitions.jsonl`, and `Checkpoints.json` to final output and the external-review data model.
- Advanced `Summary.json` to numeric schema `2` and semantic schema `2.0.0`, while keeping the fact-only and strict Windows Update scope model.
- Added v2 fixture tests for recorder state sequencing, JSONL truncation recovery, Delivery Optimization arithmetic, target/provenance separation, checkpoint creation, and process accounting.

## 1.1.2 — 2026-08-26

- Hardened `Evidence.zip` and `ReviewBundle.zip` source reads for Windows PowerShell 5.1 by retrying local and UNC files with Windows extended-length paths.
- Evidence hashing now uses the same long-path-aware, read/write/delete-sharing stream logic as archive construction.
- Opens each evidence source before creating its ZIP entry, preventing an unavailable source from leaving a misleading empty entry.
- Indexes filesystem reparse points without following their targets outside the staged evidence tree; they are explicitly recorded as optional archive exclusions.
- Adds factual archive-failure classifications for a genuinely missing source, a remaining long-path failure, and another read failure, including path length, existence-at-failure, and reparse status.
- Added a regression that hashes and archives evidence from a path longer than 300 characters.

## 1.1.1 — 2026-08-26

- Standardized the default finalized-output parent for interactive and SYSTEM runs on `%PUBLIC%\Documents` (`C:\Users\Public\Documents` on a standard installation).
- Final reports, normalized exports, `Collector.log`, `ReviewBundle.zip`, `Evidence.zip`, and integrity manifests now remain together in a unique `Win11UpgradeDiag-<Computer>-<RunId>` folder under Public Documents unless the operator explicitly supplies `-OutputPath`.
- Existing armed runs continue using their saved output path so a single pre/post run is never split between destinations.

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
