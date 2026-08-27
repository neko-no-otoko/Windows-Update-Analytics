[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $toolRoot 'Modules/Common.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Recorder.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Review.psm1') -Force

function Assert-WudV210 {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Win11UpgradeDiag-v210-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    $entrySource = Get-Content -LiteralPath (Join-Path $toolRoot 'Invoke-Win11UpgradeDiag.ps1') -Raw
    $collectorSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Collectors.psm1') -Raw
    $commonSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Common.psm1') -Raw
    $persistenceSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Persistence.psm1') -Raw
    $launcherSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Start-Win11UpgradeDiag.cmd') -Raw
    $readmeSource = Get-Content -LiteralPath (Join-Path $toolRoot 'README.md') -Raw

    Assert-WudV210 ($entrySource -match "ValidateSet\('Auto', 'Preflight', 'Resume', 'Finalize', 'Forensic', 'Disarm'\)") 'Finalize is a public command mode'
    $packageVersion = (Get-Content -LiteralPath (Join-Path $toolRoot 'VERSION') -Raw).Trim()
    Assert-WudV210 ([version]$packageVersion -ge [version]'2.1.0' -and $entrySource -match ('\$toolVersion\s*=\s*''' + [regex]::Escape($packageVersion) + '''')) 'Current tool and package versions retain the v2.1 maintenance contracts'
    Assert-WudV210 ($entrySource -match 'if \(\$Mode -eq ''Resume''\)[\s\S]+?Test-WudSetupInProgress[\s\S]+?Get-WudResumeSignal') 'Automatic Resume retains its Setup-active and terminal-signal gates'
    Assert-WudV210 ($entrySource -match 'operator-finalize\.json' -and $entrySource -match 'SetupActiveAtRequest' -and $entrySource -match 'AutomaticTerminalSignalPresent') 'Operator finalization records its explicit override and gate observations'
    Assert-WudV210 ($entrySource -match '''OperatorFinalizationBoundary''' -and $entrySource -match '\$Mode -in @\(''Resume'', ''Finalize''\)') 'Finalize shares the stop, final-collection, and cleanup lifecycle with Resume'
    Assert-WudV210 ($entrySource -match 'recorderLockReleased' -and $entrySource -match 'did not release its per-run lock') 'Final collection refuses to race an unreleased recorder lock'
    Assert-WudV210 ($entrySource -match 'elseif \(\$Mode -in @\(''Resume'', ''Finalize''\) -and \$state\)[\s\S]+?Start-WudRecorderTask') 'A failed Finalize pass can restart the recorder for retry'
    Assert-WudV210 ($collectorSource -match '@\(''Resume'', ''Finalize'', ''Forensic''\)' -and $collectorSource -match '\$Context.Mode -eq ''Finalize''[\s\S]+?operatorFinalizationPath') 'Finalize receives post-attempt evidence checks and captures its audit record'
    Assert-WudV210 ($readmeSource -match '\-Mode Finalize' -and $readmeSource -match 'operator override') 'Operator-facing Finalize behavior and caution are documented'
    Assert-WudV210 ($commonSource.IndexOf('$processHandle = $process.Handle') -lt $commonSource.IndexOf('$deadline = [DateTime]::UtcNow.AddSeconds')) 'PowerShell 5.1 process handle is retained before timeout polling'
    Assert-WudV210 ($entrySource -match 'BootstrapLogPath' -and $entrySource -match 'Write-WudBootstrapLog' -and $launcherSource -match 'Win11UpgradeDiag-Launcher\.log') 'Launcher and entry point retain early-startup diagnostics'
    Assert-WudV210 ($persistenceSource -match '\$comPath = ''\\Win11UpgradeDiag''' -and $persistenceSource -match 'ERROR_ALREADY_EXISTS is idempotent' -and $persistenceSource -notmatch 'GetFolder\(\$taskPath\)') 'Task-folder creation is canonical and idempotent across resume and recorder registration'

    if (Test-WudIsWindows) {
        $liveSample = Get-WudProgressSample -RunPath $testRoot -TargetVersion '25H2' -TargetBuild 26200
        $pendingRenameErrors = @($liveSample.PendingReboot.ProviderErrors | Where-Object Source -match 'Session Manager')
        Assert-WudV210 ($pendingRenameErrors.Count -eq 0) 'Absent PendingFileRenameOperations is a normal not-pending observation under strict mode'
    }

    $runPath = New-WudDirectory -Path (Join-Path $testRoot 'run')
    $recorderPath = New-WudDirectory -Path (Join-Path $runPath 'Evidence/Recorder')
    $sample = [pscustomobject][ordered]@{
        SchemaVersion = 1
        TimestampUtc = '2026-08-26T15:00:00Z'
        BootId = 'boot-finalize-fixture'
        Os = [pscustomobject]@{ DisplayVersion = '23H2'; Build = 22631; UBR = 1; TargetVersion = '25H2'; TargetBuild = 26200; TargetPresent = $false }
        Setup = [pscustomobject]@{ SystemSetupInProgress = 1; UpgradeInProgress = 1; OOBEInProgress = 0; SetupProgress = 55 }
        SetupProcesses = @([pscustomobject]@{ Name = 'setuphost.exe'; ProcessId = 42 })
        PendingReboot = [pscustomobject]@{ IsPending = $false; Signals = @() }
        Markers = [pscustomobject]@{ PostOOBE = $false; PostRollback = $false }
        DeliveryOptimization = [pscustomobject]@{}
        RecorderState = 'SetupActive'
        Signature = 'SetupActive|boot-finalize-fixture|22631|50'
    }
    Write-WudJsonLine -Path (Join-Path $recorderPath 'ProgressSamples.jsonl') -InputObject $sample -Depth 20
    $context = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '2.1.0-test' -RunId 'v210-finalize-status' -RunPath $runPath -OutputPath (Join-Path $testRoot 'out') -Mode 'Finalize' -PhaseLabel 'Finalize' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    $identity = [pscustomobject]@{ DisplayVersion = '23H2'; CurrentBuild = '22631'; UBR = 1 }
    $status = Get-WudUpgradeStatusModel -Context $context -Identity $identity -FeatureHistory @() -EligibleAttempts @()
    Assert-WudV210 ($status.AttemptOutcome -eq 'InProgress' -and $status.OutcomeBanner -eq 'Upgrade In Progress') 'Operator finalization preserves an observed mid-flight state instead of inventing a terminal outcome'
    Assert-WudV210 (-not $status.WindowsUpdateEvidenceConfirmed -and $status.DeploymentSource -eq 'Unattributed') 'Operator finalization does not invent Windows Update provenance'

    Write-Host 'All v2.1 fixture tests passed.' -ForegroundColor Cyan
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
