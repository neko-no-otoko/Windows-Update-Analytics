# Security and privacy

## Data classification

Treat every output as sensitive endpoint-management or incident-response data. Reports and evidence can contain computer names, usernames, domains, IP addresses, serial numbers, installed software, management configuration, file paths, event text, crash metadata, and raw Windows logs.

The HTML report displays a sensitive-data warning. It is self-contained and does not load fonts, scripts, styles, images, analytics, or other content from the network.

## Local-only processing

All collection, parsing, scope classification, inventory, hashing, and report generation occurs on the endpoint. The package contains no AI client and uploads no evidence. An operator may separately drag `ReviewBundle.zip` into an approved external review utility; that is an explicit action outside the tool. Network use by Win11UpgradeDiag is limited to:

- Retrieving SetupDiag through Microsoft's configured official redirect
- Bounded reachability checks against configured WSUS and selected Microsoft update endpoints
- An explicit `-CopyTo` destination supplied by the operator

Use `-NoInternet` to disable SetupDiag download and public endpoint tests. Existing local/cached SetupDiag may still be used if it passes verification.

## SetupDiag trust

Downloaded SetupDiag is accepted only after a successful Authenticode validation whose certificate subject identifies Microsoft. The report records source URI, file version, signer, and SHA-256. It is invoked with `/NoTel` against the newest scoped feature-upgrade-style copied source. Initial `Windows\Panther`, tool-command, current-health, and media-scan paths are never supplied as its input.

SetupDiag is not redistributed in this bundle. If verification fails, it is not executed, and the fact report continues with a visible coverage gap.

## Bundle integrity

`BundleManifest.sha256` covers every distributed bundle file except the manifest itself, including the launcher, entry point, modules, data, report assets, tests, and documentation. The entry point verifies all listed files before importing modules. Missing, changed, or malformed entries terminate with exit code `40`.

The manifest proves file integrity against the distributed manifest; it is not a digital signature and does not identify a publisher. Protect the ZIP and manifest using your normal software-distribution controls. Code signing can be added later without changing the runtime design.

## Privilege and execution policy

Administrative access is required because Windows Setup logs, event export, system inventory, ProgramData persistence, and scheduled-task registration are privileged. The CMD launcher requests UAC elevation and deliberately selects 64-bit Windows PowerShell.

It supplies `-ExecutionPolicy Bypass` only to the child PowerShell process. It does not call `Set-ExecutionPolicy` or persist a policy change.

Before loading any script or module, the CMD launcher invokes `Prepare-Win11UpgradeDiag.cmd -Check`. This inline, script-free PowerShell check verifies every entry in `BundleManifest.sha256`, inspects the extracted folder for `Zone.Identifier` alternate data streams, and reads the effective policy scopes. If markers exist, the operator receives one explicit confirmation prompt. Only after the operator types `UNBLOCK` does the helper call `Unblock-File` on files beneath the verified bundle root and confirm that the markers are gone.

This is equivalent to the File Explorer **Unblock** action, applied to the complete extracted bundle. It does not change file contents, machine or user execution policy, Group Policy, AppLocker, Windows Defender Application Control, Defender settings, or any system-wide trust list. It is intended only for the common `RemoteSigned` plus Internet-zone-marker case. If `MachinePolicy` or `UserPolicy` enforces `AllSigned` or `Restricted`, preparation stops with exit code `50`; use a trusted enterprise code-signing and application-control deployment path instead.

The integrity manifest detects a file that changed relative to the distributed bundle, but because this initial package is unsigned, the manifest does not prove publisher identity. Obtain the ZIP and its published SHA-256 through an approved channel before accepting the preparation prompt.

## Staging ACL

The ProgramData runtime and run folders are restricted to:

- `NT AUTHORITY\SYSTEM`
- Built-in `Administrators`
- The initiating technician SID

The collector does not take ownership of protected sources or loosen their ACLs. An unreadable source is recorded as a gap.

## Cross-reboot changes

Preflight mode can create temporary SYSTEM recorder and resume tasks plus guarded SetupConfig entries. Ownership metadata and original file bytes are saved in run state. Cleanup stops the recorder, removes only objects created by that run, and restores the original SetupConfig when safe.

The v2.2 GUI is a self-contained native Windows host with the diagnostic payload embedded as resources. It extracts into `%ProgramData%\WindowsUpdateAnalytics\Runtime\<version>`, validates every file against the embedded SHA-256 manifest, and then starts the PowerShell engine. Embedded extraction avoids inherited ZIP download markers on individual modules, but it does not override `AllSigned`, AppLocker, WDAC, Smart App Control, or product-specific application control. A signed EXE does not automatically sign its extracted scripts; restricted environments need an organization-trusted signing and allowlisting process for every artifact their policy evaluates.

Hook scripts are intentionally minimal: write an outcome marker, request the scheduled task, and return. They do not perform collection in the Windows Setup/OOBE critical path.

`-NoSetupHooks` suppresses SetupConfig changes. `-Mode Finalize` records an explicit operator override, performs final collection, removes owned persistence, and preserves evidence. `-Mode Disarm` removes owned persistence without performing final collection.

## Share access and credentials

SYSTEM collection never copies directly to UNC storage. Final `-CopyTo` occurs only under an interactive technician token using its existing authenticated session. Win11UpgradeDiag does not prompt for, persist, encrypt, retrieve, or transmit credentials.

## Secret exclusions

Collectors explicitly avoid password/token stores, browser data, Wi-Fi keys, private keys, and BitLocker recovery passwords. Registry and log evidence can nevertheless contain organization-specific identifiers or application-written sensitive values. Apply access controls and retention rules to the whole output rather than relying on field-level redaction.

## HTML hardening

The report:

- Encodes collected values before placing them in HTML
- Embeds all CSS and JavaScript
- Uses a restrictive Content Security Policy with no remote sources
- Has no executable remediation controls

Open reports in a supported browser. Do not weaken browser protections to view them.

## Retention and transfer

- The default finalized-output folder is beneath `%PUBLIC%\Documents`. It is intentionally easy for local technicians to find, but its inherited ACL may permit broader local read access than the protected ProgramData staging folder. Apply organizational ACLs or use `-OutputPath` when evidence requires a more restricted repository.
- Verify `Checksums.sha256` after copying or archiving.
- Store outputs only in access-controlled diagnostic repositories.
- Do not email unencrypted evidence archives.
- Remove completed ProgramData runs according to organizational retention policy.
- Revoke access promptly if a report was copied to an unintended destination.
- Prefer your enterprise signing and software-distribution pipeline before broad deployment.

## Incident response

If runtime tampering is suspected, stop using the extracted folder, retain it for analysis, obtain a known-good bundle through the approved channel, and compare its ZIP and manifest hashes. A runtime integrity failure occurs before diagnostic collection, but an already modified manifest is outside the protection provided by an unsigned package.
