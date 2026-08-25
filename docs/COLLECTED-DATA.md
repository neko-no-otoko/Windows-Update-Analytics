# Collected data and resulting insight

Win11UpgradeDiag captures full-fidelity diagnostic evidence locally and derives normalized, evidence-linked findings. Availability varies by OS edition, enabled roles, management product, setup stage, retention, localization, and permissions. Missing and skipped sources are reported rather than treated as clean.

## Collection matrix

| Family | Representative sources | Supported conclusions |
|---|---|---|
| Device and attempt identity | Computer/model/serial, OS edition/display version/build/UBR, architecture, boot/install time, source OS history, setup timestamps | Source/target path, attempt boundaries, elapsed time, current versus historical evidence, and upgrade outcome |
| Hardware and firmware | CPU, memory, BIOS/UEFI, TPM, Secure Boot, display/WDDM, battery, disks, storage reliability, partitions/volumes, WinRE, BCD, VHD/safe-mode state, BitLocker metadata | Readiness gaps, firmware/security configuration, capacity risks, unsupported boot state, storage-health concerns, and encryption-related setup risk |
| Compatibility | AppCompat and target-version experience registry, safeguard state, CompatData/Appraiser XML, Appraiser task result, optional media scan | Explicit application/hardware blocks, system-requirement blocks, safeguard holds, stale intelligence, and clean or failed media scan |
| Applications and OS composition | Machine and loaded-user uninstall registry, AppX/provisioned packages, capabilities, optional features, packages, languages, profiles, services, security products, filter drivers | Application blockers, FOD/language mismatch, profile-migration surface, and third-party security/filter software to investigate |
| Devices and drivers | PnP devices/problem codes, signed drivers, driver store, `pnputil`, boot/storage/display/network drivers, SetupAPI logs | `0xC1900101` correlation, problem or unsigned device state, boot-critical driver exposure, and device-install failures |
| Update ownership and policy | Windows Update/WUfB/WSUS policies, target release/deferral/pause/source/safeguard configuration, GPResult, MDM enrollment, `dsregcmd`, ConfigMgr and Intune logs when present | Update authority, policy conflicts, target pinning, pause/deferral, WSUS/cloud ownership, and likely offer suppression |
| Transport and orchestration | Windows Update ETL and converted log, Update Orchestrator, Delivery Optimization data/logs, BITS, WinHTTP proxy, DNS/IP/routes, time sync, bounded endpoint checks | Scan, offer, download, staging, install, TLS/proxy/DNS/clock, and source-reachability symptoms |
| Servicing health | Update history, hotfixes, DISM packages/features, CBS/DISM logs, pending markers, DISM ScanHealth, SFC verify-only | Component corruption, package failures, pending actions, reboot prerequisites, and servicing contribution |
| Setup, migration, and rollback | Panther, NewOS, Rollback, UnattendGC, MoSetup/BlueBox, migration XML, setup ETL/text, Windows.old traces, SetupDiag output | Setup phase/operation, result/extend-code decoding, final milestone, fatal abort, migration failure, rollback origin, and named app/driver/file |
| Events, crashes, reliability | Relevant event-channel EVTX exports, normalized events, reliability records, WER metadata, setup dumps/minidumps, WHEA/disk/NTFS/volmgr/BugCheck/Kernel-Power signals | Unexpected reboot/bugcheck, hardware/storage problems, crashing setup participants, and time-nearby supporting evidence |
| Pre/post comparison | Normalized application, driver, device, service, package, policy, disk, security, and network snapshots | Additions/removals, migration loss, regression, pending state, and before/after configuration changes |
| Provenance and completeness | Collector version, start/end time, timeout/error/skip status, source/destination, file size, SHA-256 | Reproducibility, chain integrity, missing evidence, and confidence limitations |

## Specific active commands

The collector may invoke the following diagnostics:

```text
dism.exe /Online /Cleanup-Image /ScanHealth
sfc.exe /verifyonly
Get-WindowsUpdateLog
Get-DeliveryOptimizationLog and available DO status/configuration commands
SetupDiag.exe /NoTel /LogsPath <local-evidence-snapshot> ...
setup.exe /auto upgrade /compat scanonly ...
```

The media command is gated by matching-media validation and `-AcceptWindowsEula`. Dynamic Update is explicitly disabled. Its intent is compatibility evaluation only, and the engine treats `0xC1900210` as the documented successful scan result.

## Event channels and raw logs

The implementation exports relevant channels where present, including core System, Application, and Setup records and targeted Windows Setup, Windows Update Client, Update Orchestrator, Delivery Optimization, AppCompat, DeviceSetupManager, Kernel-Boot, BitLocker, storage, and reliability sources. Unsupported or absent channels become collector notes, not errors by definition.

For text analysis, rules prefer structured SetupDiag, XML, JSON, CSV, registry, and event representations. Free-text lines are a secondary source and receive evidence paths, line numbers when available, timestamps, matched codes, and bounded excerpts.

## Attempt segmentation and confidence

The analyzer groups evidence using setup instance hints, timestamp clusters, source/target build transitions, and reboot boundaries. Evidence that clearly predates the latest attempt is marked `Historical` and does not control the current outcome or exit code.

Findings have four severities and three confidence levels:

- `Blocker`: an explicit condition prevents or terminated the upgrade
- `Error`: a failed operation or serious contributing condition
- `Warning`: a material risk or condition requiring review
- `Information`: explanatory state or a clean/expected result
- `High`: explicit SetupDiag/compatibility result or tightly matched causal evidence
- `Medium`: corroborated rule result with a plausible direct relationship
- `Low`: temporal association, weak entity matching, or locale/free-text limitation

The report suppresses nonfatal noise when a later setup milestone proves success. It still retains the underlying evidence and earlier contributing events.

## Deliberate exclusions

The tool does not collect:

- Passwords or reusable authentication tokens
- Browser history, cookies, saved passwords, or profile databases
- Wi-Fi pre-shared keys
- Certificate private keys
- BitLocker recovery passwords
- Arbitrary document or email contents
- Cloud-uploaded AI analysis

BitLocker collection is limited to operational status and protector metadata exposed by standard administrative commands; recovery secrets are not requested.

## Dump handling

Setup-specific dumps and ordinary minidumps are included when readable. The system `MEMORY.DMP` is normally represented by path, size, timestamps, and SHA-256 only. `-IncludeLargeDumps` permits a copy only after capacity checks; locked, oversized, or failed copies are explicitly indexed.

## Interpretive limitations

- A clean current snapshot does not prove a transient failure was absent earlier.
- A nearby event is not automatically causal; time-only correlation is capped at low confidence.
- Localized free text may reduce confidence, although structured codes and XML remain locale-neutral.
- Removed Windows.old/Panther/Rollback content can make exact phase attribution impossible.
- A safeguard identifier may require current Microsoft or OEM release-health context outside the offline report.
- SetupDiag and local rules are evidence aids, not a replacement for vendor debugging of a faulty driver, firmware, or application.
