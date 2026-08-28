# WUPA Windows VM acceptance checklist

Run this matrix before general deployment. Record the WUPA executable SHA-256, architecture, Windows edition/language/build/UBR, update source, and runtime for each case.

## Platforms

- [ ] Windows 11 23H2 x64 → 25H2 success
- [ ] Windows 11 23H2 x64 → 25H2 failure/rollback
- [ ] Windows 11 24H2 x64 → 25H2
- [ ] Windows 11 25H2 x64 after-the-fact analysis
- [ ] Windows 11 ARM64 source and target where available
- [ ] One non-English Windows 11 device
- [ ] WUfB/Intune, WSUS, ConfigMgr/co-managed, and unmanaged sources as applicable

## Application and package

- [ ] x64 and ARM64 EXEs start, request UAC, display the WUPA icon/name, and require no parameters.
- [ ] The main window exposes one state-appropriate primary action and no settings panel.
- [ ] The EXE verifies the embedded manifest before loading PowerShell.
- [ ] Tampering with an extracted runtime file prevents execution.
- [ ] AppLocker/WDAC/Smart App Control/AllSigned denial remains visible and WUPA attempts no bypass.
- [ ] A legacy v2 active pointer blocks a new v3 case with clear guidance.

## Start tracking

- [ ] **Start tracking the 25H2 update** creates `%ProgramData%\WUPA\ActiveRun.json` and a run folder.
- [ ] The GUI does not say ready until the recorder task is Running and owns its lock.
- [ ] Start creates no final `Report.html` or evidence archive.
- [ ] Recorder samples every 60 seconds and restarts on boot/process failure.
- [ ] The GUI can close without stopping recording.
- [ ] Update progress and Delivery Optimization byte/source counters appear in JSONL or carry explicit provider errors.
- [ ] At most eight state checkpoints are produced; each is bounded and contains no duplicate EVTX/WU/USO/DO trees.

## Scope safeguards

- [ ] Fresh imaging evidence under `Windows\Panther` is not copied or promoted into the update attempt.
- [ ] `$WINDOWS.~BT`, rollback, hook copies, and `Windows.old` candidates retain exact source/time/build gates.
- [ ] Scan-only, imaging, general servicing, and non-Windows-Update candidates remain excluded/context-only.
- [ ] Unrelated Delivery Optimization traffic is never identified as the 25H2 payload without Windows Update ownership evidence.

## Cross-reboot completion

- [ ] Recorder and resume tasks run as SYSTEM after reboot.
- [ ] Resume defers while Setup is active.
- [ ] An ordinary reboot without a terminal signal does not finalize.
- [ ] Success, rollback, and terminal failure trigger one delayed final collection.
- [ ] Existing SetupConfig is restored byte-for-byte when unchanged.
- [ ] Later administrator SetupConfig edits are preserved while WUPA-owned entries are removed.
- [ ] Automatic completion removes the run's recorder/resume tasks and WUPA-owned hooks.

## Manual finish and cancel

- [ ] **Finish and create report** stops the recorder, writes an operator boundary, builds artifacts, and cleans owned persistence.
- [ ] Finishing mid-flight reports the observed state without inventing success/failure.
- [ ] A finalization failure restarts the recorder and leaves the case retryable.
- [ ] A held run disables duplicate finalization and displays the newest `Collector.log` status.
- [ ] **Cancel tracking** removes owned persistence, creates no report, and retains staged evidence.
- [ ] Expiry performs the same owned cleanup and retains evidence.

## Focused collector

- [ ] No installed-software/AppX/service/security-product sweep runs.
- [ ] No DISM ScanHealth, SFC, Appraiser refresh, media scan, package/feature enumeration, MDM report, gpresult, dxdiag, msinfo, WER sweep, or full MEMORY.DMP hash/copy runs.
- [ ] Required focused native logs and event channels are present or explicitly marked missing/locked.
- [ ] Delivery Optimization status, peers, current/month performance, configuration, HTTP/peer/Connected Cache counters, and bounded readable records are present or explicitly unavailable.
- [ ] SetupDiag download rejects non-Microsoft hosts/signers and invocation includes `/NoTel` with scoped input.

## Outputs

- [ ] Final output is `%PUBLIC%\Documents\WUPA-<Computer>-<RunId>`.
- [ ] `Report.html`, `ReviewBundle.zip`, `Evidence.zip`, normalized JSON/CSV, `Collector.log`, manifests, and checksums exist.
- [ ] `ReviewBundle.zip` and `Evidence.zip` reopen and hashes validate.
- [ ] Every included fact resolves to evidence; excluded candidates show their exact gate failure.
- [ ] HTML has no remote requests, passes CSP, escapes collected text, supports keyboard operation, print/PDF, dark/light mode, and 200% zoom.
- [ ] A freshly inspected 25H2 device reports target presence rather than `Unknown` while keeping deployment source unattributed when evidence is absent.

## Pilot gate

- [ ] No unexpected state mutation or prohibited secret collection is found.
- [ ] Known-good and known-failed cases preserve expected timestamps/codes without causal invention.
- [ ] Reviewers can reproduce every displayed fact from its evidence reference.
- [ ] Complete a 25–50 device ring before broad technician deployment.
