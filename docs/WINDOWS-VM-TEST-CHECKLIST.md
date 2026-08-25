# Windows VM acceptance checklist

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

- [ ] Clean readiness produces `Ready`, complete coverage, and exit `0`.
- [ ] Media compatibility `0xC1900210` produces a clean scan finding and never starts installation.
- [ ] Incompatible application `0xC1900208` identifies the app/file and produces an evidence-linked blocker.
- [ ] Insufficient OS or system/recovery space produces the correct affected volume and recommendation.
- [ ] Safeguard hold captures its identifier/status without attempting bypass.
- [ ] Target-version, deferral, pause, source-selection, or WSUS/cloud conflict identifies update ownership.
- [ ] Unreachable WSUS or Microsoft endpoint distinguishes DNS/proxy/TLS/time/reachability evidence where possible.
- [ ] DISM component corruption and CBS/package failure are differentiated from an ordinary pending reboot.
- [ ] `0xC1900101` rollback maps the last fatal phase/operation and implicated driver/device when supported.
- [ ] Migration failure identifies setup phase/operation and named profile/app/file evidence.
- [ ] Setup bugcheck or dump finding links dump metadata and nearby BugCheck/WER/Kernel-Power evidence.
- [ ] Successful 25H2 upgrade suppresses earlier nonfatal setup noise and produces `Upgrade Succeeded`.
- [ ] Rollback produces `Rolled Back`, exit `20`, and preserves the last fatal operation.
- [ ] Several historical attempts are segmented; old blockers are `Historical` and do not control a clean current outcome.
- [ ] Missing Windows.old or cleaned Panther data becomes an explicit coverage limitation.

## Persistence and idempotency

- [ ] Preflight copies runtime/state to ProgramData and applies the expected restricted ACL.
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

- [ ] DISM uses `/ScanHealth`, never `/RestoreHealth`.
- [ ] SFC uses `/verifyonly`, never repair mode.
- [ ] No CHKDSK repair, cache deletion, update installation, driver removal, or safeguard bypass occurs.
- [ ] Compatibility Appraiser timeout is bounded and recorded.
- [ ] SetupDiag download rejects an invalid or non-Microsoft Authenticode signer.
- [ ] SetupDiag invocation contains `/NoTel` and targets the copied snapshot.
- [ ] Media validation rejects mismatched target family/architecture and missing EULA acceptance.
- [ ] Setup invocation contains `/compat scanonly` and no install continuation path.
- [ ] Setup compatibility scan explicitly disables Dynamic Update.
- [ ] Collector does not use `Win32_Product`.
- [ ] Collector never assigns drive letters, takes ownership, or loosens source ACLs.

## Degraded operation

- [ ] `-NoInternet` performs local analysis without public calls.
- [ ] Missing or stale SetupDiag is reported without preventing local rule analysis.
- [ ] Locked logs, disabled channels, and access denial are recorded as gaps.
- [ ] Insufficient ProgramData or output capacity produces a materially incomplete report where appropriate.
- [ ] Timed-out DISM, SFC, Appraiser, WU conversion, SetupDiag, and media scan terminate cleanly.
- [ ] Failed UNC copy preserves a valid local result and credentials are never stored.
- [ ] An unavailable UNC target times out within the configured share-copy limit and remains safe to retry.
- [ ] Large `MEMORY.DMP` is metadata/hash only by default.
- [ ] `-IncludeLargeDumps` checks capacity and records a failed/oversized copy instead of silently omitting it.

## Output contract and report QA

- [ ] All nine final artifacts exist and are nonempty when applicable.
- [ ] `Evidence.zip` reopens and all archived hashes match the manifest.
- [ ] `Checksums.sha256` validates after local and UNC copies.
- [ ] Every finding has an existing evidence reference or a documented normalized inventory record.
- [ ] `Summary.json` reports numeric schema `1` and semantic schema `1.0.0`, and round-trips through the fleet ingestion parser.
- [ ] CSV opens in Excel without formula execution from collected values.
- [ ] HTML contains no remote asset requests and satisfies its CSP.
- [ ] Collected HTML/script-like text is escaped and cannot execute.
- [ ] Search, sort, severity/category/status filters, collapsible excerpts, anchors, and copy controls work by keyboard.
- [ ] Dark/light modes, high contrast, zoom to 200%, mobile width, and print/PDF layout remain readable.
- [ ] Outcome and severity remain understandable without color.
- [ ] A report with thousands of evidence entries remains usable.
- [ ] Timestamps remain ordered through a DST transition and retain UTC values.

## Pilot exit criteria

- [ ] No unexpected state mutation is observed across the full matrix.
- [ ] No credential or prohibited secret collection is found in sampled outputs.
- [ ] All explicit SetupDiag/compatibility blockers are ranked above generic free-text rules.
- [ ] False positives are documented as regression fixtures before rule adjustment.
- [ ] Known-good devices do not receive an active blocker from historical/nonfatal noise.
- [ ] Known-failed devices identify the expected terminal phase and at least one actionable evidence chain.
- [ ] Help desk and engineering reviewers can reproduce a finding from the report's source reference.
- [ ] A 25–50 device ring completes before general technician deployment.
