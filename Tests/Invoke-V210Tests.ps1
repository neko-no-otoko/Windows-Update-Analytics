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
    $readmeSource = Get-Content -LiteralPath (Join-Path $toolRoot 'README.md') -Raw

    Assert-WudV210 ($entrySource -match "ValidateSet\('Auto', 'Preflight', 'Resume', 'Finalize', 'Forensic', 'Disarm'\)") 'Finalize is a public command mode'
    Assert-WudV210 ($entrySource -match '\$toolVersion\s*=\s*''2\.1\.0''' -and (Get-Content -LiteralPath (Join-Path $toolRoot 'VERSION') -Raw).Trim() -eq '2.1.0') 'Tool and package versions identify v2.1.0'
    Assert-WudV210 ($entrySource -match 'if \(\$Mode -eq ''Resume''\)[\s\S]+?Test-WudSetupInProgress[\s\S]+?Get-WudResumeSignal') 'Automatic Resume retains its Setup-active and terminal-signal gates'
    Assert-WudV210 ($entrySource -match 'operator-finalize\.json' -and $entrySource -match 'SetupActiveAtRequest' -and $entrySource -match 'AutomaticTerminalSignalPresent') 'Operator finalization records its explicit override and gate observations'
    Assert-WudV210 ($entrySource -match '''OperatorFinalizationBoundary''' -and $entrySource -match '\$Mode -in @\(''Resume'', ''Finalize''\)') 'Finalize shares the stop, final-collection, and cleanup lifecycle with Resume'
    Assert-WudV210 ($entrySource -match 'recorderLockReleased' -and $entrySource -match 'did not release its per-run lock') 'Final collection refuses to race an unreleased recorder lock'
    Assert-WudV210 ($entrySource -match 'elseif \(\$Mode -in @\(''Resume'', ''Finalize''\) -and \$state\)[\s\S]+?Start-WudRecorderTask') 'A failed Finalize pass can restart the recorder for retry'
    Assert-WudV210 ($collectorSource -match '@\(''Resume'', ''Finalize'', ''Forensic''\)' -and $collectorSource -match '\$Context.Mode -eq ''Finalize''[\s\S]+?operatorFinalizationPath') 'Finalize receives post-attempt evidence checks and captures its audit record'
    Assert-WudV210 ($readmeSource -match '\-Mode Finalize' -and $readmeSource -match 'operator override') 'Operator-facing Finalize behavior and caution are documented'

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
