# Windows Update Analytics

Windows Update Analytics ships `Win11UpgradeDiag`, a read-only Windows 11 feature-upgrade evidence recorder and collector. Version 2.2.0 adds the self-contained `WindowsUpdateAnalytics-2.2.0-win-x64.exe` and `WindowsUpdateAnalytics-2.2.0-win-arm64.exe` operator applications. The GUI starts before the upgrade, samples native progress and Delivery Optimization every 60 seconds, checkpoints evidence at observed state boundaries, survives reboot, and finishes with a full forensic capture automatically or on an explicit operator request.

The target map is optimized for Windows 11 23H2 to 25H2. The tool treats that path as a full feature upgrade; it never starts Windows Setup, installs updates, bypasses safeguards, applies repairs, uploads evidence, or asserts a root cause.

## Quick start

1. Copy the executable matching the device architecture to a local folder. Most devices use `WindowsUpdateAnalytics-2.2.0-win-x64.exe`; native Windows on ARM devices can use the ARM64 build.
2. Double-click the executable and approve the UAC prompt.
3. Review the visible settings, then select **Start monitoring**.
4. Allow the baseline collection to finish. Active health checks can take from several minutes to more than an hour on a slow or unhealthy machine.
5. Confirm the GUI says **Monitoring is armed**. Preflight deliberately does not create a report because the monitored process is not finished.
6. Leave the run armed while the normal management platform offers, downloads, and installs the update. The recorder continues as SYSTEM and survives reboot; the GUI does not need to remain open.
7. The final report is created automatically after a qualifying terminal outcome. To end at a technician-chosen point, reopen the executable and select **Finalize and build report**.
8. Open `Report.html` from the GUI. For deeper review, drag `ReviewBundle.zip` into the approved analysis utility.

The GUI exposes each lifecycle action directly and does not require parameters. The PowerShell and CMD interfaces remain in the embedded payload for scheduled SYSTEM resume and advanced automation, but technicians do not need to invoke them.

## Requirements

- Windows 11 on x64 or ARM64
- Local administrator rights
- 64-bit Windows PowerShell 5.1 or later
- At least 1 GB of temporary staging space; substantially more is recommended when logs or dumps are large
- A local path for the executable and NTFS ProgramData staging
- Optional internet access only for Microsoft SetupDiag retrieval and diagnostic endpoint tests

The GUI embeds the hash-manifested PowerShell engine and extracts it into a versioned `%ProgramData%\WindowsUpdateAnalytics\Runtime` folder. Files created from embedded resources do not inherit a ZIP's `Zone.Identifier`, eliminating the need for technicians to unblock individual modules. The GUI verifies every extracted payload file before execution.

The executable is not a bypass for Group Policy `AllSigned` or `Restricted`, AppLocker, Windows Defender Application Control, Smart App Control, or another application-control product. Signing only the EXE also does not satisfy `AllSigned` for the embedded PowerShell engine. Those environments require an organization-trusted code-signing certificate and an allowlisted release whose executable and PowerShell payload are signed as required by policy.

## GUI actions

| Action | Behavior |
|---|---|
| **Start monitoring** | Collects the baseline, commits it under ProgramData, arms SYSTEM monitoring, and verifies recorder startup. It deliberately creates no final report. |
| **Finalize and build report** | Stops the recorder, takes a final boundary checkpoint, runs final collection, creates the report package, and removes owned persistence. |
| **One-time forensic report** | Creates an after-the-fact report from evidence currently available without arming monitoring. |
| **Stop monitoring** | Removes owned tasks and hooks while retaining evidence. It does not create a report. |
| **Open latest report** | Opens the newest completed `Report.html`; it never treats a Preflight receipt as a report. |
| **Open case folder** | Opens the protected ProgramData case for the currently armed run. |

## Advanced command interface

The launcher accepts the same arguments as the PowerShell entry point:

```text
Start-Win11UpgradeDiag.cmd [-Mode Auto|Preflight|Resume|Finalize|Forensic|Disarm]
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

# Stop an armed recorder now, take a final boundary snapshot, build the final
# report, and remove this run's tasks/hooks
.\Start-Win11UpgradeDiag.cmd -Mode Finalize

# Remove this tool's scheduled task and hooks while preserving evidence
.\Start-Win11UpgradeDiag.cmd -Mode Disarm
```

When `-OutputPath` is omitted, every new interactive or SYSTEM-capable run uses `%PUBLIC%\Documents` (`C:\Users\Public\Documents` on a standard installation) as its finalized-output parent. The tool creates a unique `Win11UpgradeDiag-<Computer>-<RunId>` child folder containing the report, exports, logs, archives, and manifests. An explicit `-OutputPath` overrides this default. `-CopyTo` never stores credentials and is attempted only in an interactive technician session. A SYSTEM resume always stages locally before finalizing to the saved local destination.

Media scanning is optional. It requires `-AcceptWindowsEula`, checks the media architecture, language, edition, and target build family where metadata is available, and calls Setup only with `/compat scanonly`. Dynamic Update is disabled for this diagnostic scan so Setup cannot retrieve or apply scan-time updates. Exit code `0xC1900210` is treated as a clean compatibility scan. No installation switch is used.

## Modes

| Mode | Behavior |
|---|---|
| `Auto` | Uses saved state, current build, and recent setup/rollback evidence to select preflight, resume, or forensic behavior. |
| `Preflight` | Collects a baseline, verifies recorder startup, and arms temporary SYSTEM follow-up. It creates `State\preflight-status.json`, not a final report. |
| `Resume` | Continues a previously armed run after a reboot, produces pre/post comparison, then removes owned persistence. Normally invoked automatically. |
| `Finalize` | Explicitly stops an armed recorder, records the operator override, takes a final boundary checkpoint, produces the full report, and removes owned persistence. It does not require automatic terminal evidence. |
| `Forensic` | Performs a one-shot investigation of the evidence currently present on the device without arming follow-up. |
| `Disarm` | Removes only this run's task/hooks and restores its exact SetupConfig backup when safe. Diagnostic artifacts remain. |

Arming expires after 30 days by default. `-NoSetupHooks` disables SetupConfig integration but retains the delayed startup task. Repeated calls use saved run identity and guarded cleanup to avoid duplicate ownership.

Two SYSTEM tasks are created for an armed run. `Recorder-<RunId>` samples immediately and every 60 seconds, restarts after reboot or failure, and never finalizes the case. `Resume-<RunId>` performs the delayed, heavy final collection only after a target-build transition, an owned setup outcome marker, or qualifying setup/rollback evidence newer than the baseline. An ordinary reboot is not interpreted as upgrade completion. An operator can instead run `-Mode Finalize`; that explicit mode records whether Setup was active and whether automatic terminal evidence existed, but it does not let those gates block the requested final snapshot.

## Four-layer evidence design

1. **Persistent progress samples:** append-only `ProgressSamples.jsonl` records current build, boot identity, Setup progress/state, pending-reboot signals, active Setup processes, Delivery Optimization job counters, peers, and performance snapshots.
2. **Native evidence first:** Panther, rollback, Windows Update ETL, USO, Delivery Optimization, servicing, event, crash, and management sources are copied before any readable conversion or active diagnostic runs.
3. **Boundary checkpoints:** a state, boot, build, or 10-percent Setup-progress-bucket change creates a timestamped native checkpoint with its own manifest. A recent, run-window Setup log can label a source-reported Downlevel, SafeOS, FirstBoot, or OOBE phase; old imaging logs cannot activate a recorder phase by themselves.
4. **Final forensic capture:** after success, rollback, failure evidence, a stable post-reboot signal, or an explicit `-Mode Finalize` request, the recorder stops and a final passive-first collection, normalization pass, evidence archive, and report are produced.

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

## Preflight receipt and final artifacts

Preflight writes `%ProgramData%\Win11UpgradeDiag\Runs\<RunId>\State\preflight-status.json`. The receipt records the run ID, target, baseline completion, expiry, recorder start result, collector coverage, material gaps, and `FinalReportCreated=false`. Preflight does not create the public output directory, `Report.html`, `Evidence.zip`, `ReviewBundle.zip`, or artifact manifests.

Every automatically resumed, explicitly finalized, or forensic run is designed to contain:

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
| `0` | Preflight monitoring armed successfully, or a complete fact report without a failed/rollback outcome. This is not a readiness guarantee. |
| `10` | Reserved for a complete report with a direct attention status. |
| `20` | Source-reported failed Windows Update attempt or validated rollback outcome. |
| `30` | Preflight was armed with a material baseline/recorder limitation, or a report was produced but materially incomplete. |
| `40` | Fatal tool failure; no valid report. |
| `50` | Unsupported OS, PowerShell, or privilege state. |

Excluded and older evidence remains indexed, but it cannot enter the included upgrade timeline unless it independently passes every v2 Windows Update scope gate.

## Fact-only and external review model

Version 2 uses four record types:

- `Observed`: a value or log record read directly by the collector.
- `SourceReported`: a result emitted by Windows Update, Windows Setup, or scoped SetupDiag.
- `Decoded`: a deterministic code-to-name or extend-code-to-phase/operation mapping.
- `Computed`: a transparent diff or scope-gate result, never a causal claim.

A setup candidate is included as `WindowsUpdateFeatureUpgrade` only when it passes Windows Update ownership, feature-upgrade semantics, temporal overlap, target version/build, completed Windows image state, and contamination-exclusion gates. `Windows\Panther` imaging, `/Compat ScanOnly`, general CBS/DISM servicing, this tool's own output, explicit non-Windows-Update deployments, and ambiguous setup records are kept for provenance but excluded from upgrade conclusions.

Outcome is no longer a single ambiguous inference. `Summary.json` separately reports `CurrentOsState`, `BuildTransition`, `AttemptOutcome`, and `DeploymentSource`. A device already on 25H2 is therefore `Target OS Present` even when no retained evidence proves how it arrived there.

## Files and state

- Persistent runtime and runs: `%ProgramData%\Win11UpgradeDiag`
- Embedded GUI payload runtime: `%ProgramData%\WindowsUpdateAnalytics\Runtime\2.2.0`
- Per-run evidence: `%ProgramData%\Win11UpgradeDiag\Runs\<RunId>`
- Default finalized result: `%PUBLIC%\Documents\Win11UpgradeDiag-<Computer>-<RunId>`
- Early launcher/UAC diagnostic: `%PUBLIC%\Documents\Win11UpgradeDiag-Launcher.log`
- Windows Update SetupConfig: `%SystemDrive%\Users\Default\AppData\Local\Microsoft\Windows\WSUS\SetupConfig.ini`

See [Operations](docs/OPERATIONS.md), [Collected data](docs/COLLECTED-DATA.md), [Security](docs/SECURITY.md), [output schema](docs/SCHEMA.md), and the [Windows VM test checklist](docs/WINDOWS-VM-TEST-CHECKLIST.md).

Fleet-ingestion tooling can use the bundled machine-readable contract at `Data\Summary.schema.json`.

## Validation

The cross-platform runners check legacy parsers, attempt gates, contamination exclusions, sparse PowerShell objects, JSONL recovery, recorder state transitions, Delivery Optimization rollups, process-status contracts, report escaping/CSP, review-bundle contracts, archive reopening, and evidence references:

```powershell
pwsh -NoProfile -File .\Tests\Invoke-FixtureTests.ps1
pwsh -NoProfile -File .\Tests\Invoke-V110Tests.ps1
pwsh -NoProfile -File .\Tests\Invoke-V200Tests.ps1
pwsh -NoProfile -File .\Tests\Invoke-V210Tests.ps1
pwsh -NoProfile -File .\Tests\Invoke-V212Tests.ps1
pwsh -NoProfile -File .\Tests\Invoke-V220Tests.ps1
```

If Pester 5 is installed, run:

```powershell
Invoke-Pester .\Tests\Win11UpgradeDiag.Tests.ps1
```

Fixture tests do not replace the Windows VM acceptance matrix. Validate this unsigned release on representative 23H2, 24H2, and 25H2 systems before broad deployment.
