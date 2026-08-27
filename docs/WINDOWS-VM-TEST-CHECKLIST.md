# Windows VM acceptance checklist

Version 2.0 acceptance must validate the persistent recorder, fact-only engine, contamination boundary, and explicit outcome/provenance model; v1.0 causal-rule expectations are retained only as regression fixtures and are not the default runtime behavior.

Fixture and parser tests are necessary but not sufficient. Complete this checklist on isolated Windows VMs before expanding beyond a controlled pilot. Record the bundle SHA-256, tool version, VM snapshot, Windows edition/language/build/UBR, architecture, update source, security agents, and observed runtime for every case.

## Platform matrix

| Source | Architecture | Minimum validation |
|---|---|---|
| Windows 11 23H2 | x64 | Preflight, clean feature upgrade to 25H2, rollback/failure fixture, forensic run |
| Windows 11 24H2 | x64 | Preflight, 25H2 enablement path, success/resume, forensic run |
| Windows 11 25H2 | x64 | Current-target detection, forensic rerun, no false blocker from historical logs |
| Windows 11 23H2/24H2 | ARM64 | All inventory/command fallbacks, matching ARM64 media scan, persistence |
| Windows 11 non-English | x64 | Structured parsing, localized free-text degradation, HTML encoding |

Test Pro and Enterprise where deployment policy differs. Include Microsoft Update/WUfB, WSUS, Intune, ConfigMgr/co-management, and an unmanaged baseline as applicable to the organization.

## Package and launcher

- [ ] Extracted ZIP contains all documented runtime, data, assets, tests, and docs.
- [ ] `BundleManifest.sha256` verifies on a pristine extraction.
- [ ] Editing a covered module causes exit `40` before collection.
- [ ] Double-click launcher selects 64-bit Windows PowerShell 5.1 and prompts for UAC.
- [ ] Process execution-policy bypass does not alter LocalMachine or CurrentUser policy.
- [ ] Non-admin direct invocation exits `50` with a useful message.
- [ ] Unsupported Windows version or non-Windows execution exits `50`.
- [ ] Paths containing spaces and non-ASCII characters work.

## Core scenarios

- [ ] A WUA-owned feature update with matching Setup/BlueBox evidence passes every attempt gate and is the only setup source in the included timeline.
- [ ] Fresh-imaging `Windows\Panther` logs are classified `InitialDeploymentOrImaging`, even when they mention Windows Update or the target build.
- [ ] Media `/Compat ScanOnly` records are classified `DiagnosticCompatibilityScan` and never appear as a real upgrade attempt.
- [ ] ConfigMgr/media feature upgrades with an explicit non-Windows-Update owner remain `NonWindowsUpdateFeatureUpgrade`.
- [ ] Ambiguous Setup logs remain `UnclassifiedSetupEvidence` rather than being promoted by timestamp proximity.

- [ ] Clean preflight produces complete factual coverage, outcome `Monitoring Armed`, and exit `0` without claiming readiness.
- [ ] Media compatibility `0xC1900210` is retained as a source-reported scan-only fact and never starts installation.
- [ ] Application, disk-space, safeguard, policy, connectivity, servicing, driver, migration, and crash records preserve exact values/codes/evidence without asserting cause.
- [ ] `0xC1900101 - 0x20017` produces an observed failure line plus a decoded SafeOS/Boot fact, but no inferred driver name.
- [ ] A transition observed from the preflight build to 25H2 produces `Upgrade Succeeded`; a freshly inspected 25H2 device with no observed transition produces `Target OS Present`, never `Unknown`.
- [ ] An owned rollback marker plus a validated Windows Update attempt produces `Rolled Back` and exit `20`.
- [ ] Several setup candidates remain independently hashed/classified; none is merged or promoted by proximity alone.
- [ ] Missing Windows.old or cleaned Panther data becomes an explicit coverage limitation.

## Persistence and idempotency

- [ ] A new interactive run without `-OutputPath` finalizes every report, export, log, archive, and manifest beneath `%PUBLIC%\Documents\Win11UpgradeDiag-<Computer>-<RunId>`.
- [ ] A SYSTEM resume uses the exact same saved Public Documents run folder as its preflight pass.
- [ ] An explicit local `-OutputPath` overrides the Public Documents default, while an older armed run retains its previously saved path.
- [ ] Preflight copies runtime/state to ProgramData and applies the expected restricted ACL.
- [ ] `Recorder-<RunId>` starts immediately, samples at the configured 60-second interval, and restarts after task/process failure.
- [ ] Each JSONL sample is independently parseable; a deliberately truncated final line is reported without losing prior records.
- [ ] State/build/boot/10-percent-progress changes create bounded native checkpoints and unchanged samples do not create duplicate checkpoints.
- [ ] DO status, peers, current/month performance, configuration, HTTP/peer/Connected Cache counters, progress, caller, and source URL are present or carry an explicit provider failure/unavailable state.
- [ ] Unrelated Delivery Optimization traffic is not promoted to a 25H2 download; Windows Update transport ownership remains distinct from feature-update attempt validation.
- [ ] SYSTEM startup task runs after success and after rollback.
- [ ] Three-minute delayed resume does not collect while Setup is still active.
- [ ] An ordinary reboot without a target-build transition, hook marker, or newer Setup evidence does not finalize the run.
- [ ] Daily fallback resumes when the first startup trigger is missed.
- [ ] Hook scripts return immediately and never delay OOBE or rollback.
- [ ] Existing nonconflicting SetupConfig bytes are restored exactly after cleanup.
- [ ] Each conflicting SetupConfig key is skipped while nonconflicting keys remain eligible.
- [ ] An administrator edit made after arming is preserved; cleanup removes only owned values.
- [ ] `-NoSetupHooks` creates no SetupConfig entries but retains task-based follow-up.
- [ ] Repeated `Auto` invocation does not create duplicate tasks, hooks, or run ownership.
- [ ] Repeated reboot does not repeatedly finalize an already completed run.
- [ ] Expiry removes persistence and retains diagnostic artifacts.
- [ ] `Disarm` removes only owned persistence and retains evidence.

## Active diagnostic safety

- [ ] Raw evidence copy finishes before DISM, SFC, Appraiser, media scan, and SetupDiag start.
- [ ] DISM ScanHealth writes to the run-owned `CurrentDiagnostics` log path.
- [ ] SetupDiag receives only the selected WindowsBT/Rollback/Windows.old/SetupCopyLogs source and never the whole evidence root.
- [ ] A later capture of earlier tool-generated CBS/Appraiser records remains servicing/tool context and cannot enter the upgrade timeline.

- [ ] DISM uses `/ScanHealth`, never `/RestoreHealth`.
- [ ] SFC uses `/verifyonly`, never repair mode.
- [ ] No CHKDSK repair, cache deletion, update installation, driver removal, or safeguard bypass occurs.
- [ ] Compatibility Appraiser timeout is bounded and recorded.
- [ ] SetupDiag download rejects an invalid or non-Microsoft Authenticode signer.
- [ ] SetupDiag invocation contains `/NoTel` and targets only the selected copied upgrade-style source.
- [ ] Media validation rejects mismatched target family/architecture and missing EULA acceptance.
- [ ] Setup invocation contains `/compat scanonly` and no install continuation path.
- [ ] Setup compatibility scan explicitly disables Dynamic Update.
- [ ] Collector does not use `Win32_Product`.
- [ ] Collector never assigns drive letters, takes ownership, or loosens source ACLs.

## Degraded operation

- [ ] `-NoInternet` performs local fact processing without public calls.
- [ ] Missing or stale SetupDiag is reported without preventing fact/report generation.
- [ ] Locked logs, disabled channels, and access denial are recorded as gaps.
- [ ] Insufficient ProgramData or output capacity produces a materially incomplete report where appropriate.
- [ ] Timed-out DISM, SFC, Appraiser, WU conversion, SetupDiag, and media scan terminate cleanly.
- [ ] Failed UNC copy preserves a valid local result and credentials are never stored.
- [ ] An unavailable UNC target times out within the configured share-copy limit and remains safe to retry.
- [ ] Large `MEMORY.DMP` is metadata/hash only by default.
- [ ] `-IncludeLargeDumps` checks capacity and records a failed/oversized copy instead of silently omitting it.

## Output contract and report QA

- [ ] `ReviewBundle.zip` reopens and contains all required JSONL/CSV, scope, coverage, excerpt, prompt, and hash-manifest files.
- [ ] The fact-only HTML contains no primary-cause ranking, confidence label, or executable recommendation.
- [ ] `Findings.csv` is header-only and `Facts.csv` contains the v2 records.
- [ ] Every fact evidence locator resolves to an indexed source or an explicitly recorded external/original source path.

- [ ] All v2 final artifacts exist and are nonempty when applicable, including recorder summary, progress JSONL, state transitions, and checkpoints.
- [ ] `Evidence.zip` reopens and all archived hashes match the manifest.
- [ ] A staged evidence file with an absolute path longer than 260 characters is hashed and included in `Evidence.zip` under Windows PowerShell 5.1.
- [ ] A broken or external reparse point is indexed as `ArchiveReparsePointSkipped`, is not followed, and creates no empty ZIP entry.
- [ ] A regular file removed between evidence inventory and archive creation is recorded as `ArchiveSourceMissing` and creates no empty ZIP entry.
- [ ] `Checksums.sha256` validates after local and UNC copies.
- [ ] Every fact has an indexed evidence reference or an explicitly documented original-source locator.
- [ ] `Summary.json` reports numeric schema `2` and semantic schema `2.0.0`, and round-trips through the fleet ingestion parser.
- [ ] CSV opens in Excel without formula execution from collected values.
- [ ] HTML contains no remote asset requests and satisfies its CSP.
- [ ] Collected HTML/script-like text is escaped and cannot execute.
- [ ] Search, sort, fact-type/category/scope filters, collapsible excerpts, and controls work by keyboard.
- [ ] Dark/light modes, high contrast, zoom to 200%, mobile width, and print/PDF layout remain readable.
- [ ] Outcome, fact type, inclusion, and exclusion remain understandable without color.
- [ ] A report with thousands of evidence entries remains usable.
- [ ] Timestamps remain ordered through a DST transition and retain UTC values.

## Pilot exit criteria

- [ ] No unexpected state mutation is observed across the full matrix.
- [ ] No credential or prohibited secret collection is found in sampled outputs.
- [ ] Explicit source-reported records remain distinct from observed free text and computed scope gates.
- [ ] False inclusions/exclusions are documented as regression fixtures before gate adjustment.
- [ ] Known-good and freshly imaged devices receive no causal or readiness claims.
- [ ] Known-failed devices preserve the expected source-reported terminal code/phase and exact evidence chain.
- [ ] Help desk and engineering reviewers can reproduce every fact from its source reference.
- [ ] A 25–50 device ring completes before general technician deployment.
