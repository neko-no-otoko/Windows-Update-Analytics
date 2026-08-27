# Windows Update Analytics

Windows Update Analytics ships `Win11UpgradeDiag`, a read-only Windows 11 feature-upgrade evidence recorder and collector. Version 2.0 starts before the upgrade, samples native progress and Delivery Optimization every 60 seconds, checkpoints evidence at observed state boundaries, survives reboot, and finishes with a full forensic capture. It normalizes direct facts, applies transparent evidence-scope gates, and produces an offline HTML report plus a compact `ReviewBundle.zip` designed for drag-and-drop human or external AI review.

The target map is optimized for Windows 11 23H2 to 25H2. The tool treats that path as a full feature upgrade; it never starts Windows Setup, installs updates, bypasses safeguards, applies repairs, uploads evidence, or asserts a root cause.

## Quick start

1. Extract the entire bundle to a local folder. Do not run it from inside the ZIP.
2. Double-click `Start-Win11UpgradeDiag.cmd` and approve the UAC prompt.
3. Allow the initial collection to finish. Active health checks can make this take from several minutes to more than an hour on a slow or unhealthy machine. When the report completes, the persistent recorder is running.
4. Leave the run armed while the normal management platform offers, downloads, and installs the update.
5. Open the new `Win11UpgradeDiag-<Computer>-<RunId>` folder under `%PUBLIC%\Documents` and review `Report.html`. For deeper review, drag `ReviewBundle.zip` into the approved analysis utility. The final collection runs automatically after success or rollback.

By default, one-click `Auto` mode starts a preflight run when there is no armed run and no recent upgrade evidence. When a recent attempt is already visible, it performs an after-the-fact forensic run. An armed run is resumed using its saved state.

## Requirements

- Windows 11 on x64 or ARM64
- Local administrator rights
- 64-bit Windows PowerShell 5.1 or later
- At least 1 GB of temporary staging space; substantially more is recommended when logs or dumps are large
- A local NTFS location for the extracted bundle and ProgramData staging
- Optional internet access only for Microsoft SetupDiag retrieval and diagnostic endpoint tests

The bundle remains intentionally unsigned and hash-manifested. The launcher uses a process-scoped execution-policy bypass; it does not change the machine execution policy. Verify `BundleManifest.sha256` before distribution if the transport channel is not trusted.

## Command interface

The launcher accepts the same arguments as the PowerShell entry point:

```text
Start-Win11UpgradeDiag.cmd [-Mode Auto|Preflight|Resume|Forensic|Disarm]
  [-TargetVersion 25H2]
  [-OutputPath <local-folder>]
  [-CopyTo <UNC-folder>]
  [-MediaPath <25H2-media>] [-AcceptWindowsEula]
  [-IncludeLargeDumps] [-NoInternet] [-NoSetupHooks]
  [-ArmDays <1-365>] [-NoOpen]
```

Examples:

```powershell
# One-touch preflight and automatic post-upgrade capture
.\Start-Win11UpgradeDiag.cmd -Mode Preflight -TargetVersion 25H2

# Offline after-the-fact collection without cross-reboot hooks
.\Start-Win11UpgradeDiag.cmd -Mode Forensic -NoInternet -NoSetupHooks

# Explicit compatibility scan using mounted matching media
.\Start-Win11UpgradeDiag.cmd -Mode Preflight -MediaPath D:\ -AcceptWindowsEula

# Place the local result under D:\UpgradeDiagnostics, then copy finalized artifacts
# to a share when an interactive technician token is available
.\Start-Win11UpgradeDiag.cmd -OutputPath D:\UpgradeDiagnostics -CopyTo \\server\share\UpgradeDiagnostics

# Remove this tool's scheduled task and hooks while preserving evidence
.\Start-Win11UpgradeDiag.cmd -Mode Disarm
```

When `-OutputPath` is omitted, every new interactive or SYSTEM-capable run uses `%PUBLIC%\Documents` (`C:\Users\Public\Documents` on a standard installation) as its finalized-output parent. The tool creates a unique `Win11UpgradeDiag-<Computer>-<RunId>` child folder containing the report, exports, logs, archives, and manifests. An explicit `-OutputPath` overrides this default. `-CopyTo` never stores credentials and is attempted only in an interactive technician session. A SYSTEM resume always stages locally before finalizing to the saved local destination.

Media scanning is optional. It requires `-AcceptWindowsEula`, checks the media architecture, language, edition, and target build family where metadata is available, and calls Setup only with `/compat scanonly`. Dynamic Update is disabled for this diagnostic scan so Setup cannot retrieve or apply scan-time updates. Exit code `0xC1900210` is treated as a clean compatibility scan. No installation switch is used.

## Modes

| Mode | Behavior |
|---|---|
| `Auto` | Uses saved state, current build, and recent setup/rollback evidence to select preflight, resume, or forensic behavior. |
| `Preflight` | Collects a baseline and arms a temporary SYSTEM follow-up task and guarded SetupConfig hooks. It does not predict upgrade success. |
| `Resume` | Continues a previously armed run after a reboot, produces pre/post comparison, then removes owned persistence. Normally invoked automatically. |
| `Forensic` | Performs a one-shot investigation of the evidence currently present on the device without arming follow-up. |
| `Disarm` | Removes only this run's task/hooks and restores its exact SetupConfig backup when safe. Diagnostic artifacts remain. |

Arming expires after 30 days by default. `-NoSetupHooks` disables SetupConfig integration but retains the delayed startup task. Repeated calls use saved run identity and guarded cleanup to avoid duplicate ownership.

Two SYSTEM tasks are created for an armed run. `Recorder-<RunId>` samples immediately and every 60 seconds, restarts after reboot or failure, and never finalizes the case. `Resume-<RunId>` performs the delayed, heavy final collection only after a target-build transition, an owned setup outcome marker, or qualifying setup/rollback evidence newer than the baseline. An ordinary reboot is not interpreted as upgrade completion.

## Four-layer evidence design

1. **Persistent progress samples:** append-only `ProgressSamples.jsonl` records current build, boot identity, Setup progress/state, pending-reboot signals, active Setup processes, Delivery Optimization job counters, peers, and performance snapshots.
2. **Native evidence first:** Panther, rollback, Windows Update ETL, USO, Delivery Optimization, servicing, event, crash, and management sources are copied before any readable conversion or active diagnostic runs.
3. **Boundary checkpoints:** a state, boot, build, or 10-percent Setup-progress-bucket change creates a timestamped native checkpoint with its own manifest. A recent, run-window Setup log can label a source-reported Downlevel, SafeOS, FirstBoot, or OOBE phase; old imaging logs cannot activate a recorder phase by themselves.
4. **Final forensic capture:** after success, rollback, failure evidence, or a stable post-reboot signal, the recorder stops and a final passive-first collection, normalization pass, evidence archive, and report are produced.

Delivery Optimization traffic without a direct Windows Update caller or Microsoft update URL is labeled `DeliveryOptimizationTransferObserved`, not an upgrade download. Even Windows Update-owned transport remains context until the setup-attempt gates confirm a feature update.

## What it does and does not do

The tool can run these read-only diagnostics with bounded timeouts:

- DISM `/Online /Cleanup-Image /ScanHealth`
- SFC `/verifyonly`
- Compatibility Appraiser refresh
- Microsoft SetupDiag against the newest scoped feature-upgrade-style source, with `/NoTel`
- Windows Update and Delivery Optimization log conversion
- Setup `/compat scanonly` only when matching media and explicit EULA acceptance are supplied

It does **not** run RestoreHealth, SFC repair, CHKDSK repair, update-cache deletion, update installation, driver removal, safeguard bypass, disk/partition changes, ownership changes, or ACL changes to force access.

## Final artifacts

Every finalized run is designed to contain:

| Artifact | Purpose |
|---|---|
| `Report.html` | Offline, searchable fact report with attempt scope, direct records, included timeline, and collection coverage. |
| `ReviewBundle.zip` | Compact drag-and-drop external-review package with JSONL/CSV facts, attempts, inventory, exclusions, evidence hashes, and bounded excerpts. |
| `Summary.json` | Stable fleet-ingestion contract, including fact and attempt-scope summaries. |
| `Facts.csv` | Flat direct-fact export for triage and ingestion. |
| `Findings.csv` | Retained compatibility artifact; header-only in fact-only mode because v2 emits no causal findings. |
| `Timeline.csv` | Only validated Windows Update setup records and source-reported update history; no proximity-only correlations. |
| `RecorderSummary.json` | Sampling window, observed states, Delivery Optimization byte/source/throughput rollups, and timestamps. |
| `ProgressSamples.jsonl` | Append-only, timestamped native progress observations suitable for streaming or external review. |
| `StateTransitions.jsonl` | Recorder boundaries with prior/current state, boot identity, and evidence locator. |
| `Checkpoints.json` | Rollup of timestamped native checkpoint manifests. |
| `Attempts.json` | Every setup candidate, its classification, exact scope gates, corroborating evidence, and inclusion decision. |
| `ExcludedEvidence.json` | Imaging, scan-only, tool-generated, non-Windows-Update, and unclassified setup evidence exclusions. |
| `Inventory.json` | Collected normalized snapshots and collector records. |
| `Evidence.zip` | Full-fidelity copied logs and command output. |
| `Manifest.json` | File provenance, paths, sizes, and SHA-256 hashes. |
| `Checksums.sha256` | Integrity hashes for finalized artifacts. |
| `Collector.log` | Execution and collector audit trail. |

Locked, cleaned, timed-out, skipped, or oversized sources are recorded as gaps. A default run includes Setup-specific dumps and ordinary minidumps. `MEMORY.DMP` is metadata-and-hash only unless `-IncludeLargeDumps` is specified and capacity checks pass.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Complete fact report; no source-reported failed/rollback outcome selected. This is not a readiness guarantee. |
| `10` | Reserved for a complete report with a direct attention status. |
| `20` | Source-reported failed Windows Update attempt or validated rollback outcome. |
| `30` | Report produced but materially incomplete. |
| `40` | Fatal tool failure; no valid report. |
| `50` | Unsupported OS, PowerShell, or privilege state. |

Excluded and older evidence remains indexed, but it cannot enter the included upgrade timeline unless it independently passes every v2 Windows Update scope gate.

## Fact-only and external review model

Version 2.0 uses four record types:

- `Observed`: a value or log record read directly by the collector.
- `SourceReported`: a result emitted by Windows Update, Windows Setup, or scoped SetupDiag.
- `Decoded`: a deterministic code-to-name or extend-code-to-phase/operation mapping.
- `Computed`: a transparent diff or scope-gate result, never a causal claim.

A setup candidate is included as `WindowsUpdateFeatureUpgrade` only when it passes Windows Update ownership, feature-upgrade semantics, temporal overlap, target version/build, completed Windows image state, and contamination-exclusion gates. `Windows\Panther` imaging, `/Compat ScanOnly`, general CBS/DISM servicing, this tool's own output, explicit non-Windows-Update deployments, and ambiguous setup records are kept for provenance but excluded from upgrade conclusions.

Outcome is no longer a single ambiguous inference. `Summary.json` separately reports `CurrentOsState`, `BuildTransition`, `AttemptOutcome`, and `DeploymentSource`. A device already on 25H2 is therefore `Target OS Present` even when no retained evidence proves how it arrived there.

## Files and state

- Persistent runtime and runs: `%ProgramData%\Win11UpgradeDiag`
- Per-run evidence: `%ProgramData%\Win11UpgradeDiag\Runs\<RunId>`
- Default finalized result: `%PUBLIC%\Documents\Win11UpgradeDiag-<Computer>-<RunId>`
- Windows Update SetupConfig: `%SystemDrive%\Users\Default\AppData\Local\Microsoft\Windows\WSUS\SetupConfig.ini`

See [Operations](docs/OPERATIONS.md), [Collected data](docs/COLLECTED-DATA.md), [Security](docs/SECURITY.md), [output schema](docs/SCHEMA.md), and the [Windows VM test checklist](docs/WINDOWS-VM-TEST-CHECKLIST.md).

Fleet-ingestion tooling can use the bundled machine-readable contract at `Data\Summary.schema.json`.

## Validation

The cross-platform runners check legacy parsers, attempt gates, contamination exclusions, sparse PowerShell objects, JSONL recovery, recorder state transitions, Delivery Optimization rollups, process-status contracts, report escaping/CSP, review-bundle contracts, archive reopening, and evidence references:

```powershell
pwsh -NoProfile -File .\Tests\Invoke-FixtureTests.ps1
pwsh -NoProfile -File .\Tests\Invoke-V110Tests.ps1
pwsh -NoProfile -File .\Tests\Invoke-V200Tests.ps1
```

If Pester 5 is installed, run:

```powershell
Invoke-Pester .\Tests\Win11UpgradeDiag.Tests.ps1
```

Fixture tests do not replace the Windows VM acceptance matrix. Validate this unsigned release on representative 23H2, 24H2, and 25H2 systems before broad deployment.
