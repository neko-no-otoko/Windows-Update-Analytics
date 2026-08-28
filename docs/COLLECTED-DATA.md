# WUPA focused evidence profile

WUPA collects direct Windows Update performance and feature-update evidence. It does not attempt open-ended machine inventory.

## Always collected

- OS/build, source-OS history, boot identity, model, BIOS, locale, and image/setup state
- OS volume free space, disks/partitions/volumes, WinRE, BitLocker, and Secure Boot state
- problem devices and signed-driver facts limited to display, storage, network, system, and unsigned drivers
- Windows Update and Delivery Optimization policies, core service state, BITS jobs, configured update endpoints, proxy, and time status
- Windows Update history and pending-reboot markers
- `$WINDOWS.~BT\Sources\Panther`, `$WINDOWS.~BT\Sources\Rollback`, `Windows\Logs\MoSetup`, existing SetupDiag, Windows Update ETLs, USO logs, Delivery Optimization logs, setup-hook copies, and `Windows.old` Panther evidence when present
- native System, Setup, Setup Operational, MoSetup, Windows Update Client, Update Orchestrator, and Delivery Optimization event channels
- readable Windows Update conversion and bounded Delivery Optimization status, peer, performance, configuration, and log records
- Microsoft-signed SetupDiag analysis against the newest scoped feature-update source

## Persistent record

Every 60 seconds WUPA appends an observation containing current build, boot identity, setup process/state, pending-reboot signals, update progress, Delivery Optimization file/byte/source counters, and owned outcome markers. State changes create at most eight checkpoints. Each checkpoint is capped at 64 MiB and retains only the newest bounded Panther, Rollback, and MoSetup files. Event logs and transport logs are not duplicated into each checkpoint.

## Excluded by design

- installed applications, AppX packages, services, security-product inventory, and filesystem filters
- complete drivers/devices, hardware, memory, battery, graphics, network, VPN, route, MDM, ConfigMgr, group-policy, and enrollment inventories
- package, feature, capability, language, hotfix, and component-store sweeps
- active DISM ScanHealth, SFC, Compatibility Appraiser refresh, and setup media scan
- CBS/DISM logs, broad WER/reliability history, SetupAPI logs, minidump sweeps, and full `MEMORY.DMP`
- general `Windows\Panther`, which may describe initial imaging rather than a Windows Update feature upgrade

Missing optional sources are recorded. Core setup evidence missing after an attempted final collection is a material coverage gap.

## External review

`ReviewBundle.zip` contains normalized case, recorder, attempts, facts, timeline, update history, coverage, excluded-evidence decisions, hashes, and bounded excerpts. It is designed to be ingestible without executing code. WUPA itself never uploads it.
