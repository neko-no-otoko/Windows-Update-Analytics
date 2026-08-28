[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $toolRoot 'Modules/Common.psm1') -Force

function Assert-WudV220 {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$version = (Get-Content -LiteralPath (Join-Path $toolRoot 'VERSION') -Raw).Trim()
$entrySource = Get-Content -LiteralPath (Join-Path $toolRoot 'Invoke-Win11UpgradeDiag.ps1') -Raw
$commonSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Common.psm1') -Raw
$persistenceSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Persistence.psm1') -Raw
$projectSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Gui/WindowsUpdateAnalytics.Gui.csproj') -Raw
$programSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Gui/Program.cs') -Raw
$manifestSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Gui/app.manifest') -Raw
$workflowSource = Get-Content -LiteralPath (Join-Path $toolRoot '.github/workflows/build-windows-exe.yml') -Raw
$readmeSource = Get-Content -LiteralPath (Join-Path $toolRoot 'README.md') -Raw

Assert-WudV220 ([version]$version -ge [version]'2.2.0' -and $entrySource -match ('\$toolVersion\s*=\s*''' + [regex]::Escape($version) + '''')) 'Current tool and package versions retain the v2.2.0 GUI contracts'
$receiptIndex = $entrySource.IndexOf("FinalReportCreated = `$false")
$preflightExitIndex = $entrySource.IndexOf("exit ([int]`$context.ExitCode)", $receiptIndex)
$reviewExportIndex = $entrySource.IndexOf('Export-WudReviewBundle', $receiptIndex)
$reportExportIndex = $entrySource.IndexOf('Export-WudReportArtifacts', $receiptIndex)
Assert-WudV220 ($receiptIndex -ge 0 -and $preflightExitIndex -gt $receiptIndex -and $reviewExportIndex -gt $preflightExitIndex -and $reportExportIndex -gt $preflightExitIndex) 'Preflight commits its receipt and exits before either finalized archive exporter'
Assert-WudV220 ($entrySource -match 'preflight-status\.json' -and $entrySource -match "Status\s*=\s*'MonitoringArmed'" -and $entrySource -match 'FinalReportCreated\s*=\s*\$false') 'Preflight writes an explicit non-final machine-readable receipt'
Assert-WudV220 ($entrySource -match 'RecorderStartFailed' -and $entrySource -match "Impact 'Material'" -and $entrySource -match "Persistent 60-second progress recorder started") 'Recorder startup is verified and a failed immediate start makes Preflight materially incomplete'
Assert-WudV220 ($persistenceSource -match "Status = 'StartUnverified'" -and $persistenceSource -match '\$taskState -eq ''Running'' -and \$lockHeld' -and $persistenceSource -match 'AddSeconds\(15\)') 'Recorder startup requires both Task Scheduler Running state and exclusive recorder-lock ownership'
Assert-WudV220 ($commonSource -notmatch 'New-WudDirectory -Path \$OutputPath') 'Run-context creation no longer creates an empty final-output folder during Preflight'

Assert-WudV220 ($projectSource -match '<OutputType>WinExe</OutputType>' -and $projectSource -match '<PublishSingleFile>true</PublishSingleFile>' -and $projectSource -match '<SelfContained>true</SelfContained>') 'GUI project publishes a self-contained single-file Windows application'
Assert-WudV220 ($projectSource -match '<ApplicationIcon>Assets\\WindowsUpdateAnalytics\.ico</ApplicationIcon>' -and (Test-Path -LiteralPath (Join-Path $toolRoot 'Gui/Assets/WindowsUpdateAnalytics.ico'))) 'GUI project embeds the Windows Update Analytics application icon'
Assert-WudV220 ($projectSource -match 'LogicalName="Payload/Invoke-Win11UpgradeDiag\.ps1"' -and $projectSource -match 'Payload/Modules/') 'GUI executable embeds the diagnostic entry point and module payload'
Assert-WudV220 ($manifestSource -match 'requestedExecutionLevel level="requireAdministrator"') 'GUI requests elevation before starting the backend'
Assert-WudV220 ($programSource -match 'private static void Main\(\)' -and $programSource -notmatch 'static void Main\([^)]*string\[\]') 'Operator GUI starts without a command-line interface'
Assert-WudV220 ($programSource -match 'StartupFailureLog\.TryWrite' -and $programSource -match 'Shown \+= \(_, _\) => ConfigureSplitter\(middle\)' -and $programSource -notmatch 'new SplitContainer \{[^\r\n]*SplitterDistance') 'GUI defers DPI-sensitive splitter sizing and records otherwise-unhandled startup failures'
Assert-WudV220 ($programSource -match 'VerifyEmbeddedManifestMatches\(destination\)' -and $programSource -match 'CryptographicOperations\.FixedTimeEquals') 'GUI rejects a stale extracted runtime even when it has a self-consistent older manifest for the same version'
Assert-WudV220 ($programSource -match 'Start monitoring' -and $programSource -match 'Finalize and build report' -and $programSource -match 'One-time forensic report' -and $programSource -match 'Stop monitoring') 'GUI exposes the complete operator lifecycle as explicit actions'
Assert-WudV220 ($programSource -match 'No final report has been created' -and $programSource -match 'ActiveRun\.json') 'GUI verifies armed state instead of treating Preflight as a final report'
Assert-WudV220 ($workflowSource -match 'win-x64' -and $workflowSource -match 'win-arm64' -and $workflowSource -match 'upload-artifact') 'GitHub workflow publishes x64 and ARM64 application artifacts'
Assert-WudV220 ($readmeSource -match 'WindowsUpdateAnalytics.*\.exe' -and $readmeSource -match 'Preflight.*does not.*report') 'Operator documentation identifies the GUI executable and non-final Preflight contract'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Win11UpgradeDiag-v220-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    $runPath = Join-Path $testRoot 'run'
    $outputPath = Join-Path $testRoot 'should-not-exist-yet'
    $null = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '2.2.0-test' -RunId 'v220-output-contract' -RunPath $runPath -OutputPath $outputPath -Mode 'Preflight' -PhaseLabel 'Preflight' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    Assert-WudV220 (-not (Test-Path -LiteralPath $outputPath)) 'Creating a Preflight run context does not publish or pre-create its final output directory'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host 'All v2.2.0 regression tests passed.' -ForegroundColor Cyan
