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

## Staging ACL

The ProgramData runtime and run folders are restricted to:

- `NT AUTHORITY\SYSTEM`
- Built-in `Administrators`
- The initiating technician SID

The collector does not take ownership of protected sources or loosen their ACLs. An unreadable source is recorded as a gap.

## Cross-reboot changes

Preflight mode can create a temporary SYSTEM scheduled task and guarded SetupConfig entries. Ownership metadata and original file bytes are saved in run state. Cleanup removes only objects created by that run and restores the original SetupConfig when safe.

Hook scripts are intentionally minimal: write an outcome marker, request the scheduled task, and return. They do not perform collection in the Windows Setup/OOBE critical path.

`-NoSetupHooks` suppresses SetupConfig changes. `-Mode Disarm` removes owned persistence and preserves evidence.

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
