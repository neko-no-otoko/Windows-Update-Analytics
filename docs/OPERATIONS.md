# Operations guide

## Recommended technician workflow

### Before the managed upgrade

1. Copy and extract the bundle to a local folder.
2. Launch `Start-Win11UpgradeDiag.cmd -Mode Preflight` as the intended technician.
3. Confirm that the report was produced and note its outcome and collection coverage.
4. Leave `%ProgramData%\Win11UpgradeDiag` in place while the organization's existing deployment process performs the upgrade.
5. After success or rollback, allow the startup task to run. It waits three minutes by default so services and log writers can settle.
6. Sign in as a technician and review the refreshed final output. If `-CopyTo` was supplied, invoke `Auto` once interactively if a SYSTEM resume could not reach the share.

Win11UpgradeDiag does not launch or schedule the operating-system upgrade.

### After an attempted upgrade

Run `Start-Win11UpgradeDiag.cmd -Mode Forensic`. This captures the remaining Panther, Rollback, NewOS, Windows.old, Windows Update, servicing, event, crash, application, driver, hardware, and policy evidence without adding persistence.

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
- Optional short `PostOOBE`, `PostRollback`, `PostRollbackContext`, and `CopyLogs` SetupConfig entries

The setup hook scripts only write an outcome marker and request the scheduled task. They return immediately and do not wait for collection.

An ordinary reboot is not treated as an upgrade outcome. Resume finalization requires a target-build transition, an owned PostOOBE/PostRollback marker, or qualifying setup/rollback evidence newer than the preflight baseline. If Setup is still running or none of those signals exists, the scheduled task exits cleanly and remains armed for a later trigger.

The staging ACL is restricted to SYSTEM, built-in Administrators, and the initiating technician SID. The tool does not store a password, token, or share credential.

## SetupConfig safety

The tool reads the existing SetupConfig before making a change and saves its exact bytes and SHA-256 hash. It adds only missing entries that do not conflict with existing values.

- A conflicting individual key is skipped and recorded; the existing value wins.
- An invalid or unrecognized file structure is not rewritten.
- On cleanup, the exact original byte stream is restored when the file remains tool-owned.
- If another administrator changed the file after arming, cleanup removes only lines that match the tool's owned values. It does not overwrite the administrator's later changes.

Use `-NoSetupHooks` when another deployment product owns SetupConfig or local change policy forbids modification. The startup/daily task still provides a reboot-follow-up path.

## Output and UNC handling

Collection always stages to ProgramData first. `-OutputPath` must be a local folder and becomes the parent of the unique finalized run folder.

`-CopyTo` is a post-finalization convenience, not the authoritative storage location. It runs only when an interactive technician token is available and relies on that user's existing access. Failures are logged and do not discard the local result. Use the resulting `Checksums.sha256` at the destination to verify transfer integrity.

## Expected duration

Duration depends on storage performance, log volume, and component health:

- Inventory-only collectors: usually minutes
- DISM ScanHealth and SFC verify-only: commonly 10–60+ minutes combined
- Compatibility Appraiser: potentially tens of minutes
- Windows Update conversion and large evidence copies: proportional to ETL/log size
- Media `/compat scanonly`: potentially an hour or longer

Each external process has a configured timeout. A timeout is a recorded coverage gap rather than an unbounded hang.

## Common operational conditions

### Report says materially incomplete

Inspect the Collection Coverage and Raw Evidence Index sections. Typical reasons include:

- Running after logs were cleaned or rolled over
- Locked files or insufficient staging/output capacity
- A diagnostic command timeout
- Missing SetupDiag while `-NoInternet` is active
- Event channels unavailable or disabled
- Running without access to an offline Windows.old source

The report still presents supported findings, but causal certainty should be bounded by the recorded gaps.

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

The tool first looks for an existing or cached SetupDiag. With internet enabled, it follows Microsoft's official redirect, requires a valid Authenticode signature whose signer is Microsoft, records the version/URI/hash, and then invokes `/NoTel` against the copied snapshot. If verification or download fails, local rules continue and the limitation is visible.

### Compatibility scan was skipped

Both `-MediaPath` and `-AcceptWindowsEula` are required. The selected media must expose `setup.exe`, match the running architecture, edition, default UI language, and intended target family where the image metadata permits validation. The tool invokes only `/compat scanonly`, forces Dynamic Update disabled for that scan, and never falls through into installation. A validation failure is reported instead of starting Setup.

## Retention and cleanup

Define an organizational retention period for both ProgramData staging and copied reports. A completed or disarmed run removes persistence, not evidence. Delete retained runs only after the result has been transferred and its hashes verified. Reports and archives contain sensitive device and user context; use the same controls as endpoint-management exports and incident evidence.
