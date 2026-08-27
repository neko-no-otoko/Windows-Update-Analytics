# Operations guide

## Recommended technician workflow

### Before the managed upgrade

1. Copy and extract the bundle to a local folder.
2. Launch `Start-Win11UpgradeDiag.cmd -Mode Preflight` as the intended technician.
3. Open the run folder under `%PUBLIC%\Documents`, confirm that the fact report was produced, and confirm that the console reported `Persistent 60-second progress recorder started`. Exit `0` is not a prediction that the upgrade will succeed.
4. Leave `%ProgramData%\Win11UpgradeDiag` in place while the organization's existing deployment process offers, downloads, and installs the upgrade.
5. After success or rollback, allow the startup task to run. It waits three minutes by default so services and log writers can settle.
6. Sign in as a technician and review the refreshed output. Use `Report.html` for fast verification and `ReviewBundle.zip` for approved external review. If `-CopyTo` was supplied, invoke `Auto` once interactively if a SYSTEM resume could not reach the share.

Win11UpgradeDiag does not launch or schedule the operating-system upgrade.

### After an attempted upgrade

Run `Start-Win11UpgradeDiag.cmd -Mode Forensic`. This captures remaining Panther, Rollback, NewOS, Windows.old, Windows Update, servicing, event, crash, application, driver, hardware, and policy evidence without adding persistence. Initial imaging and ambiguous setup logs remain visible in the evidence index but cannot enter the upgrade timeline without passing every Windows Update gate.

Collect as soon as practical. Windows servicing, Disk Cleanup, Storage Sense, another setup attempt, or log rollover can remove high-value evidence.

### Cancel an armed run

Run `Start-Win11UpgradeDiag.cmd -Mode Disarm` elevated. It removes the run's owned scheduled task and hook scripts and safely restores SetupConfig. It deliberately retains the staged evidence, state, reports, and logs.

## Automatic selection

`Auto` follows this order:

1. Resume a valid armed run.
2. Treat an expired run as expired and clean up owned persistence.
3. Use current OS/build and recent setup or rollback evidence to select forensic collection where an attempt is already visible.
4. Otherwise start a preflight run.

Each new non-resume invocation receives a UTC timestamp plus random suffix as its `RunId`. A resumed invocation uses saved state. Collectors overwrite or append only within the correct phase folders, and persistence has a single owner record.

## Persistence design

An armed run contains:

- A staged runtime beneath `%ProgramData%\Win11UpgradeDiag\Runtime\<version>`
- State beneath `%ProgramData%\Win11UpgradeDiag\Runs\<RunId>`
- A SYSTEM scheduled task named `\Win11UpgradeDiag\Resume-<RunId>` with startup and daily triggers
- A long-running SYSTEM task named `\Win11UpgradeDiag\Recorder-<RunId>` with a startup trigger, immediate start, one-minute restart-on-failure policy, and run expiry
- Optional short `PostOOBE`, `PostRollback`, `PostRollbackContext`, and `CopyLogs` SetupConfig entries

The recorder appends `Evidence\Recorder\ProgressSamples.jsonl` every 60 seconds. A state, build, boot, or Setup-progress-bucket boundary creates `Evidence\Recorder\Checkpoints\<timestamp>-<state>`. The setup hook scripts only write an outcome marker and request the resume task. They return immediately and do not wait for collection.

An ordinary reboot is not treated as an upgrade outcome. The recorder restarts and its boot identity changes, but resume finalization still requires a target-build transition, an owned PostOOBE/PostRollback marker, or qualifying setup/rollback evidence newer than the preflight baseline. If Setup is still running or none of those signals exists, the resume task exits cleanly and remains armed for a later trigger.

The staging ACL is restricted to SYSTEM, built-in Administrators, and the initiating technician SID. The tool does not store a password, token, or share credential.

## SetupConfig safety

The tool reads the existing SetupConfig before making a change and saves its exact bytes and SHA-256 hash. It adds only missing entries that do not conflict with existing values.

- A conflicting individual key is skipped and recorded; the existing value wins.
- An invalid or unrecognized file structure is not rewritten.
- On cleanup, the exact original byte stream is restored when the file remains tool-owned.
- If another administrator changed the file after arming, cleanup removes only lines that match the tool's owned values. It does not overwrite the administrator's later changes.

Use `-NoSetupHooks` when another deployment product owns SetupConfig or local change policy forbids modification. The startup/daily task still provides a reboot-follow-up path.

## Output and UNC handling

Collection always stages to ProgramData first. By default, final artifacts are written to `%PUBLIC%\Documents\Win11UpgradeDiag-<Computer>-<RunId>`, regardless of whether the final pass runs under an interactive administrator or SYSTEM. This keeps `Report.html`, `Collector.log`, normalized exports, `ReviewBundle.zip`, `Evidence.zip`, and their integrity manifests together in a predictable machine-wide location.

`-OutputPath` must be a local folder and explicitly overrides the Public Documents parent for a newly created run. A resumed or disarmed run always honors its saved output path, including for runs created by an older tool version, so preflight and follow-up artifacts are not split across folders.

`-CopyTo` is a post-finalization convenience, not the authoritative storage location. It runs only when an interactive technician token is available and relies on that user's existing access. Failures are logged and do not discard the local result. Use the resulting `Checksums.sha256` at the destination to verify transfer integrity.

### External review workflow

Use `ReviewBundle.zip`, not the much larger `Evidence.zip`, for the first pass in an approved human or AI review utility. The package contains a ready-to-use `REVIEW_PROMPT.md`, but the reviewer should always enforce these boundaries:

1. Read `Case.json` and `CollectionCoverage.json` first.
2. Analyze only attempts whose `IncludedForUpgradeReview` value is true.
3. Treat facts as records, not causal conclusions.
4. Cite `EvidenceRef` for every assertion.
5. Request the matching full source from `Evidence.zip` only when the bounded excerpt is insufficient.

Win11UpgradeDiag never performs this upload itself and never stores credentials for an external service.

## Expected duration

Duration depends on storage performance, log volume, and component health:

- Inventory-only collectors: usually minutes
- DISM ScanHealth and SFC verify-only: commonly 10–60+ minutes combined
- Compatibility Appraiser: potentially tens of minutes
- Windows Update conversion and large evidence copies: proportional to ETL/log size
- Media `/compat scanonly`: potentially an hour or longer

Each external process has a configured timeout. A timeout is a recorded coverage gap rather than an unbounded hang.

Archive construction uses Windows extended-length paths when Windows PowerShell 5.1 cannot open a deeply nested staged file normally. Filesystem reparse points are indexed but their targets are not followed into an archive, because a target can leave the bounded evidence tree. If a regular staged file genuinely disappears or remains unreadable, the manifest records its exact path and archive status; the ZIP contains no fabricated empty replacement.

## Common operational conditions

### Report says materially incomplete

Inspect Collection Coverage in `Report.html` and `ReviewBundle.zip/CollectionCoverage.json`. Typical reasons include:

- Running after logs were cleaned or rolled over
- Locked files or insufficient staging/output capacity
- A diagnostic command timeout
- Missing SetupDiag while `-NoInternet` is active
- Event channels unavailable or disabled
- Running without access to an offline Windows.old source

The report still presents direct facts, but missing evidence can prevent attempt validation or external causal review.

### No post-reboot report appeared

Check these in order:

1. `%ProgramData%\Win11UpgradeDiag\active-run.json`
2. The `\Win11UpgradeDiag\Resume-<RunId>` scheduled-task history
3. The run's `Collector.log` and state JSON
4. The arm expiry timestamp
5. Whether Windows Setup is still active; resume intentionally defers in that state
6. SetupConfig conflict notes if hook creation was expected

Run the launcher with `-Mode Auto` interactively to resume the saved run, or use `-Mode Disarm` to cancel it.

### Integrity check failed

Re-extract a known-good bundle. Do not edit a runtime file without regenerating `BundleManifest.sha256`. Integrity failure exits `40` before modules or collectors run.

### SetupDiag was not used

The tool first looks for an existing or cached SetupDiag. With internet enabled, it follows Microsoft's official redirect, requires a valid Authenticode signature whose signer is Microsoft, records the version/URI/hash, and then invokes `/NoTel` against the newest scoped feature-upgrade-style source. If verification/download fails, or no scoped input exists, fact collection continues and the limitation is visible.

### Compatibility scan was skipped

Both `-MediaPath` and `-AcceptWindowsEula` are required. The selected media must expose `setup.exe`, match the running architecture, edition, default UI language, and intended target family where the image metadata permits validation. The tool invokes only `/compat scanonly`, forces Dynamic Update disabled for that scan, and never falls through into installation. A validation failure is reported instead of starting Setup.

## Retention and cleanup

Define an organizational retention period for both ProgramData staging and copied reports. A completed or disarmed run removes persistence, not evidence. Delete retained runs only after the result has been transferred and its hashes verified. Reports and archives contain sensitive device and user context; use the same controls as endpoint-management exports and incident evidence.
