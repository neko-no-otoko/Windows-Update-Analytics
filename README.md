# Windows Update Analytics

Windows Update Analytics ships `Win11UpgradeDiag`, a read-only Windows 11 feature-upgrade diagnostic companion. It collects preflight or post-failure evidence, correlates Windows Setup and Windows Update signals, and produces a self-contained HTML investigation report plus machine-readable artifacts.

The initial rules and target map are optimized for Windows 11 23H2 to 25H2. The tool treats that path as a full feature upgrade; it never starts Windows Setup, installs updates, bypasses safeguards, or applies repairs.

## Quick start

1. Extract the entire bundle to a local folder. Do not run it from inside the ZIP.
2. Double-click `Start-Win11UpgradeDiag.cmd` and approve the UAC prompt.
3. Allow the initial collection to finish. Active health checks can make this take from several minutes to more than an hour on a slow or unhealthy machine.
4. Review `Report.html` in the output folder. If the run was armed before the upgrade, the follow-up collection runs automatically after success or rollback.

By default, one-click `Auto` mode starts a preflight run when there is no armed run and no recent upgrade evidence. When a recent attempt is already visible, it performs an after-the-fact forensic run. An armed run is resumed using its saved state.

## Requirements

- Windows 11 on x64 or ARM64
- Local administrator rights
- 64-bit Windows PowerShell 5.1 or later
- At least 1 GB of temporary staging space; substantially more is recommended when logs or dumps are large
- A local NTFS location for the extracted bundle and ProgramData staging
- Optional internet access only for Microsoft SetupDiag retrieval and diagnostic endpoint tests

The bundle is intentionally unsigned for the initial release. The launcher uses a process-scoped execution-policy bypass; it does not change the machine execution policy. Verify `BundleManifest.sha256` before distribution if the transport channel is not trusted.

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

`-OutputPath` identifies the parent output folder. The tool creates a unique `Win11UpgradeDiag-<Computer>-<RunId>` child folder. `-CopyTo` never stores credentials and is attempted only in an interactive technician session. A SYSTEM resume always stages locally.

Media scanning is optional. It requires `-AcceptWindowsEula`, checks the media architecture, language, edition, and target build family where metadata is available, and calls Setup only with `/compat scanonly`. Dynamic Update is disabled for this diagnostic scan so Setup cannot retrieve or apply scan-time updates. Exit code `0xC1900210` is treated as a clean compatibility scan. No installation switch is used.

## Modes

| Mode | Behavior |
|---|---|
| `Auto` | Uses saved state, current build, and recent setup/rollback evidence to select preflight, resume, or forensic behavior. |
| `Preflight` | Collects a baseline, reports readiness, and arms a temporary SYSTEM follow-up task and guarded SetupConfig hooks. |
| `Resume` | Continues a previously armed run after a reboot, produces pre/post comparison, then removes owned persistence. Normally invoked automatically. |
| `Forensic` | Performs a one-shot investigation of the evidence currently present on the device without arming follow-up. |
| `Disarm` | Removes only this run's task/hooks and restores its exact SetupConfig backup when safe. Diagnostic artifacts remain. |

Arming expires after 30 days by default. `-NoSetupHooks` disables SetupConfig integration but retains the delayed startup task. Repeated calls use saved run identity and guarded cleanup to avoid duplicate ownership.

The scheduled task does not interpret an ordinary reboot as upgrade completion. It finalizes only after a target-build transition, an owned setup outcome marker, or qualifying setup/rollback evidence newer than the baseline; otherwise it remains armed until a later trigger or expiry.

## What it does and does not do

The tool can run these read-only diagnostics with bounded timeouts:

- DISM `/Online /Cleanup-Image /ScanHealth`
- SFC `/verifyonly`
- Compatibility Appraiser refresh
- Microsoft SetupDiag against the copied evidence snapshot, with `/NoTel`
- Windows Update and Delivery Optimization log conversion
- Setup `/compat scanonly` only when matching media and explicit EULA acceptance are supplied

It does **not** run RestoreHealth, SFC repair, CHKDSK repair, update-cache deletion, update installation, driver removal, safeguard bypass, disk/partition changes, ownership changes, or ACL changes to force access.

## Final artifacts

Every finalized run is designed to contain:

| Artifact | Purpose |
|---|---|
| `Report.html` | Offline, searchable investigation report with findings, timeline, coverage, and evidence index. |
| `Summary.json` | Stable fleet-ingestion contract. |
| `Findings.csv` | Flat finding rollup for triage. |
| `Timeline.csv` | Normalized setup/update/event sequence. |
| `Inventory.json` | Collected normalized snapshots and collector records. |
| `Evidence.zip` | Full-fidelity copied logs and command output. |
| `Manifest.json` | File provenance, paths, sizes, and SHA-256 hashes. |
| `Checksums.sha256` | Integrity hashes for finalized artifacts. |
| `Collector.log` | Execution and collector audit trail. |

Locked, cleaned, timed-out, skipped, or oversized sources are recorded as gaps. A default run includes Setup-specific dumps and ordinary minidumps. `MEMORY.DMP` is metadata-and-hash only unless `-IncludeLargeDumps` is specified and capacity checks pass.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Complete report; ready or upgrade successful. |
| `10` | Complete report with active warnings requiring attention. |
| `20` | Active blocker, failure, or rollback detected. |
| `30` | Report produced but materially incomplete. |
| `40` | Fatal tool failure; no valid report. |
| `50` | Unsupported OS, PowerShell, or privilege state. |

Older evidence is retained but marked `Historical`; it does not by itself set the current exit code or outcome.

## Files and state

- Persistent runtime and runs: `%ProgramData%\Win11UpgradeDiag`
- Per-run evidence: `%ProgramData%\Win11UpgradeDiag\Runs\<RunId>`
- Default final result: the initiating technician's Desktop
- Windows Update SetupConfig: `%SystemDrive%\Users\Default\AppData\Local\Microsoft\Windows\WSUS\SetupConfig.ini`

See [Operations](docs/OPERATIONS.md), [Collected data](docs/COLLECTED-DATA.md), [Security](docs/SECURITY.md), [output schema](docs/SCHEMA.md), and the [Windows VM test checklist](docs/WINDOWS-VM-TEST-CHECKLIST.md).

Fleet-ingestion tooling can use the bundled machine-readable contract at `Data\Summary.schema.json`.

## Validation

The cross-platform fixture runner checks parsers, rule correlation, report escaping/CSP, all output contracts, archive reopening, and evidence references:

```powershell
pwsh -NoProfile -File .\Tests\Invoke-FixtureTests.ps1
```

If Pester 5 is installed, run:

```powershell
Invoke-Pester .\Tests\Win11UpgradeDiag.Tests.ps1
```

Fixture tests do not replace the Windows VM acceptance matrix. Validate this unsigned release on representative 23H2, 24H2, and 25H2 systems before broad deployment.
