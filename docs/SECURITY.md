# WUPA security model

WUPA is read-only with respect to Windows servicing. It does not install updates, run repairs, delete update caches, remove drivers, change safeguards, assign drive letters, or take ownership of protected paths.

The self-contained GUI requests elevation and extracts a SHA-256-manifested PowerShell 5.1 payload to `%ProgramData%\WUPA\Runtime\<version>`. The manifest is verified before module loading and again when reusing a cached runtime. The current public executable is not organization-signed; WDAC, AppLocker, Smart App Control, or `AllSigned` environments require trusted signing and allowlisting appropriate to their policy.

Cross-reboot tasks run as SYSTEM. Setup hooks write only an outcome marker and trigger the delayed resume task. Hook and task cleanup is scoped to the current run. SetupConfig is backed up byte-for-byte and restored when unchanged; later administrator changes are preserved.

Network use is limited to direct tests of configured/official update endpoints and downloading SetupDiag from Microsoft's official redirect. Downloads must end at an approved Microsoft host and have a valid Microsoft Authenticode signature and SetupDiag identity. SetupDiag runs with `/NoTel`. Evidence is never uploaded.

Outputs can contain device identifiers, users, domain/network data, paths, policies, and native logs. Passwords, tokens, browser data, Wi-Fi keys, private keys, and BitLocker recovery passwords are not collected. Treat all output as sensitive and transfer it only through approved channels.

WUPA is independent open-source software, is not a Microsoft product, and is not affiliated with Microsoft.
