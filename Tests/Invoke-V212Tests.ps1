[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Assert-WudV212 {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$entrySource = Get-Content -LiteralPath (Join-Path $toolRoot 'Invoke-Win11UpgradeDiag.ps1') -Raw
$launcherSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Start-Win11UpgradeDiag.cmd') -Raw
$prepareSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Prepare-Win11UpgradeDiag.cmd') -Raw
$persistenceSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Persistence.psm1') -Raw
$securitySource = Get-Content -LiteralPath (Join-Path $toolRoot 'docs/SECURITY.md') -Raw
$version = (Get-Content -LiteralPath (Join-Path $toolRoot 'VERSION') -Raw).Trim()

Assert-WudV212 ([version]$version -ge [version]'2.1.2' -and $entrySource -match ('\$toolVersion\s*=\s*''' + [regex]::Escape($version) + '''')) 'Current tool and package versions retain the v2.1.2 launcher contracts'
Assert-WudV212 ($launcherSource.IndexOf('Prepare-Win11UpgradeDiag.cmd" -Check') -lt $launcherSource.IndexOf('-File "%WUD_ROOT%Invoke-Win11UpgradeDiag.ps1"')) 'Download-marker preparation occurs before the PowerShell entry point loads'
Assert-WudV212 ($launcherSource -match 'WUD_PREP_EXIT' -and $launcherSource -match 'AllSigned, WDAC, or AppLocker') 'Launcher distinguishes preparation failure from collector failure'
Assert-WudV212 ($prepareSource.IndexOf('BundleManifest.sha256') -lt $prepareSource.IndexOf('Unblock-File')) 'Every bundle is manifest-verified before any marker is removed'
Assert-WudV212 ($prepareSource -match 'Security\.Cryptography\.SHA256' -and $prepareSource -notmatch 'Get-FileHash') 'Preparation hashes through .NET without depending on PowerShell module auto-loading'
Assert-WudV212 ($prepareSource -match "Zone\.Identifier" -and $prepareSource -match "-ieq '-Check'" -and $prepareSource -match "-ine '-Apply'") 'Preparation exposes check, confirmed, and managed-apply paths'
Assert-WudV212 ($prepareSource -match 'Get-ExecutionPolicy -List' -and $prepareSource -match "MachinePolicy" -and $prepareSource -match "UserPolicy" -and $prepareSource -match "AllSigned" -and $prepareSource -match "Restricted") 'Enforced signing-policy boundaries are diagnosed explicitly'
Assert-WudV212 ($prepareSource -notmatch 'Set-ExecutionPolicy' -and $securitySource -match 'does not change.*execution policy') 'Preparation does not change PowerShell policy'
Assert-WudV212 ($persistenceSource -match "'Prepare-Win11UpgradeDiag\.cmd'") 'Cross-reboot runtime copy includes the preparation helper covered by the bundle manifest'

$manifestPath = Join-Path $toolRoot 'BundleManifest.sha256'
$manifestText = Get-Content -LiteralPath $manifestPath -Raw
Assert-WudV212 ($manifestText -match '(?m)\s+Prepare-Win11UpgradeDiag\.cmd$' -and $manifestText -match '(?m)\s+Tests/Invoke-V212Tests\.ps1$') 'Bundle manifest covers the preparation helper and its regression test'

if ($env:OS -eq 'Windows_NT') {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Win11UpgradeDiag-v212-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
    try {
        $bundleRoot = Join-Path $testRoot 'Win11UpgradeDiag'
        $null = New-Item -ItemType Directory -Path $bundleRoot -Force
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $bundleRoot 'BundleManifest.sha256') -Force
        foreach ($line in Get-Content -LiteralPath $manifestPath) {
            if ($line -match '^\s*$|^\s*#') { continue }
            if ($line -notmatch '^([A-Fa-f0-9]{64})\s+\*?(.+)$') { throw "Malformed fixture manifest line: $line" }
            $relative = $matches[2].Trim()
            $source = Join-Path $toolRoot $relative
            $destination = Join-Path $bundleRoot $relative
            $destinationParent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $destinationParent)) { $null = New-Item -ItemType Directory -Path $destinationParent -Force }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }

        $markedFiles = @(
            (Join-Path $bundleRoot 'Invoke-Win11UpgradeDiag.ps1')
            @(Get-ChildItem -LiteralPath (Join-Path $bundleRoot 'Modules') -Filter '*.psm1' -File | ForEach-Object FullName)
        )
        foreach ($path in $markedFiles) {
            Set-Content -LiteralPath $path -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding Ascii
        }
        Assert-WudV212 (@(Get-Item -LiteralPath $markedFiles[0] -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue).Count -eq 1) 'Windows fixture carries a real Internet-zone alternate data stream'

        $preparePath = Join-Path $bundleRoot 'Prepare-Win11UpgradeDiag.cmd'
        $checkOutput = @(& $preparePath '-Check' 2>&1)
        $checkExit = $LASTEXITCODE
        Assert-WudV212 ($checkExit -eq 10 -and ($checkOutput -join ' ') -match 'download markers detected') ("Check mode detects recursively marked scripts without loading them. Exit={0}; Output={1}" -f $checkExit, ($checkOutput -join ' | '))

        $applyOutput = @(& $preparePath '-Apply' 2>&1)
        $applyExit = $LASTEXITCODE
        $remaining = @($markedFiles | Where-Object { @(Get-Item -LiteralPath $_ -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue).Count -gt 0 })
        Assert-WudV212 ($applyExit -eq 0 -and $remaining.Count -eq 0 -and ($applyOutput -join ' ') -match 'Prepared bundle') 'One managed preparation removes every marked script and module'

        $cleanOutput = @(& $preparePath '-Check' 2>&1)
        $cleanExit = $LASTEXITCODE
        Assert-WudV212 ($cleanExit -eq 0 -and ($cleanOutput -join ' ') -match 'No Internet-zone') 'Prepared bundle is idempotent'

        $markerTarget = Join-Path $bundleRoot 'Modules/Common.psm1'
        Set-Content -LiteralPath $markerTarget -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding Ascii
        [IO.File]::AppendAllText((Join-Path $bundleRoot 'NOTICE.md'), [Environment]::NewLine + 'tampered-fixture')
        $tamperOutput = @(& $preparePath '-Apply' 2>&1)
        $tamperExit = $LASTEXITCODE
        $markerRemains = @(Get-Item -LiteralPath $markerTarget -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue).Count -eq 1
        Assert-WudV212 ($tamperExit -eq 40 -and $markerRemains -and ($tamperOutput -join ' ') -match 'integrity check failed') 'Manifest tampering stops preparation before any marker is removed'
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    }
}

Write-Host 'All v2.1.2 compatibility fixture tests passed.' -ForegroundColor Cyan
