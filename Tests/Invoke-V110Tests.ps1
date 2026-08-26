[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $toolRoot 'Modules/Common.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Analysis.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Review.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Report.psm1') -Force

function Assert-WudV110 {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Win11UpgradeDiag-v110-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    $context = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '1.1.0-test' -RunId 'v110-fixture' -RunPath (Join-Path $testRoot 'run') -OutputPath (Join-Path $testRoot 'output') -Mode 'Forensic' -PhaseLabel 'Forensic' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    $identity = [pscustomobject][ordered]@{
        ComputerName = 'V110-PC'; Manufacturer = 'Contoso'; Model = 'Fixture'; SerialNumber = 'V110'
        EditionId = 'Enterprise'; ProductName = 'Windows 11 Enterprise'; DisplayVersion = '23H2'
        CurrentBuild = '22631'; UBR = 9000; CapturedUtc = '2026-08-26T12:00:00Z'
        WindowsImageState = 'IMAGE_STATE_COMPLETE'
        SystemSetupState = [pscustomobject]@{ SystemSetupInProgress = 0; OOBEInProgress = 0 }
        SourceOsHistory = @()
    }
    $history = @([pscustomobject][ordered]@{
        Date = '2026-08-20T14:20:00Z'; Title = 'Feature update to Windows 11, version 25H2'
        Operation = 'Installation'; ResultCode = '4'; HResult = -1047526904; HResultHex = '0xC1900208'
        ClientApplicationID = 'UpdateOrchestrator'; ServerSelection = 'ssWindowsUpdate'; ServiceID = 'fixture-service'
        UpdateID = '11111111-2222-3333-4444-555555555555'; RevisionNumber = 1
    })
    $context.Inventory['Identity'] = $identity
    $context.Inventory['Hardware'] = [pscustomobject]@{}
    $context.Inventory['Software'] = [pscustomobject]@{ Applications = @(); Services = @() }
    $context.Inventory['Drivers'] = [pscustomobject]@{ Devices = @(); SignedDrivers = @() }
    $context.Inventory['Management'] = [pscustomobject]@{ Connectivity = @(); InternetTestsSuppressed = $true }
    $context.Inventory['Servicing'] = [pscustomobject]@{ UpdateHistory = $history; PendingReboot = [pscustomobject]@{ IsPending = $false }; Packages = @(); HotFixes = @() }
    $null = $context.CollectorRecords.Add([pscustomobject]@{ Id = 'fixture'; Version = '1.1.0-test'; Description = 'v1.1 fixture'; Required = $true; Status = 'Succeeded'; Detail = $null; StartedUtc = $context.StartedUtc; EndedUtc = $context.StartedUtc; DurationMs = 1 })

    $wuPath = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'Raw/WindowsBT-Rollback')
    $wuDuplicatePath = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'Raw/WindowsBT-Panther')
    $imagingPath = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'Raw/Windows-Panther')
    $scanPath = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'Compatibility/MediaScan')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'Tests/Fixtures/setupact-wu-upgrade.log') -Destination (Join-Path $wuPath 'setupact.log')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'Tests/Fixtures/setupact-wu-upgrade.log') -Destination (Join-Path $wuDuplicatePath 'setupact.log')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'Tests/Fixtures/setupact-imaging.log') -Destination (Join-Path $imagingPath 'setupact.log')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'Tests/Fixtures/setupact-scanonly.log') -Destination (Join-Path $scanPath 'setupact.log')
    Write-WudJsonAtomic -Path (Join-Path $context.SnapshotPath 'inventory.json') -InputObject $context.Inventory -Depth 30
    Write-WudJsonAtomic -Path (Join-Path $context.SnapshotPath 'collector-records.json') -InputObject @($context.CollectorRecords)
    Write-WudLog -Context $context -Level INFO -Message 'Starting v1.1 fact-only fixture.'

    $analysis = Invoke-WudFactAnalysis -Context $context
    Assert-WudV110 ($analysis.AnalysisMode -eq 'FactOnly') 'Fact-only analysis mode'
    Assert-WudV110 (@($analysis.Attempts).Count -eq 4) 'All setup candidates remain inventoried'
    Assert-WudV110 (@($analysis.Attempts | Where-Object Classification -eq 'WindowsUpdateFeatureUpgrade').Count -eq 1) 'Windows Update feature-upgrade gate inclusion'
    Assert-WudV110 (@($analysis.Attempts | Where-Object { $_.DuplicateOf }).Count -eq 1) 'Byte-identical setup evidence is retained but deduplicated'
    Assert-WudV110 (@($analysis.Attempts | Where-Object Classification -eq 'InitialDeploymentOrImaging').Count -eq 1) 'Initial imaging setup evidence exclusion'
    Assert-WudV110 (@($analysis.Attempts | Where-Object Classification -eq 'DiagnosticCompatibilityScan').Count -eq 1) 'Scan-only setup evidence exclusion'
    Assert-WudV110 (@($analysis.Timeline | Where-Object { $_.EvidenceReference -match 'Windows-Panther|MediaScan' }).Count -eq 0) 'Excluded sources cannot enter the upgrade timeline'
    Assert-WudV110 (@($analysis.Facts | Where-Object FactType -eq 'SourceReported').Count -ge 1) 'Source-reported facts emitted'
    Assert-WudV110 (@($analysis.Facts | Where-Object { $_.FactType -eq 'Decoded' -and $_.Phase -eq 'SafeOS' -and $_.Operation -eq 'Boot' }).Count -eq 1) 'Deterministic extend-code fact emitted'
    Assert-WudV110 (@($analysis.Facts | Where-Object { $_.Category -eq 'WindowsSetup' -and $_.Code -match '0xC1900101' }).Count -eq 1) 'Validated setup error retained as direct fact'
    Assert-WudV110 (@($analysis.Findings).Count -eq 0) 'No causal findings emitted by fact-only engine'

    $bundle = Export-WudReviewBundle -Context $context
    Assert-WudV110 (Test-Path -LiteralPath $bundle.Path) 'ReviewBundle.zip created'
    Assert-WudV110 ($bundle.Verified) 'Review bundle internal hash manifest verified'
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive = [IO.Compression.ZipFile]::OpenRead($bundle.Path)
    try {
        $names = @($archive.Entries | ForEach-Object FullName)
        foreach ($required in @('READ_ME_FIRST.md', 'REVIEW_PROMPT.md', 'Case.json', 'Attempts.json', 'Facts.jsonl', 'Facts.csv', 'Timeline.jsonl', 'EvidenceIndex.jsonl', 'ExcludedEvidence.json', 'Manifest.sha256')) {
            Assert-WudV110 ($names -contains $required) "Review bundle entry $required"
        }
    }
    finally { $archive.Dispose() }

    $report = Export-WudReportArtifacts -Context $context
    $html = Get-Content -LiteralPath $report -Raw
    Assert-WudV110 ($html -match 'Interpretation boundary') 'Fact-only interpretation boundary in report'
    Assert-WudV110 ($html -match 'Setup evidence scope') 'Attempt gate table in report'
    Assert-WudV110 ($html -match 'ReviewBundle\.zip') 'External review bundle called out in report'
    Assert-WudV110 ($html -notmatch 'Primary finding|Recommended next action|confidence precedence') 'No causal ranking language in fact-only report'
    Assert-WudV110 ($html -match 'Content-Security-Policy' -and $html -notmatch '<script\s+src=') 'Fact report has an offline restrictive content contract'
    Assert-WudV110 ($html -notmatch "<script>alert\('v110'\)</script>" -and $html -match '&lt;script&gt;alert') 'Fact report escapes collected script-like text'
    Assert-WudV110 ($html -match 'id="fact-type-filter"' -and $html -match 'id="fact-scope-filter"') 'Fact report type and scope filters are present'
    foreach ($artifact in @('Report.html', 'Summary.json', 'Facts.csv', 'Findings.csv', 'Timeline.csv', 'Attempts.json', 'ExcludedEvidence.json', 'Inventory.json', 'ReviewBundle.zip', 'Evidence.zip', 'Manifest.json', 'Checksums.sha256', 'Collector.log')) {
        Assert-WudV110 (Test-Path -LiteralPath (Join-Path $context.OutputPath $artifact)) "v1.1 artifact $artifact"
    }
    $summary = Read-WudJson -Path (Join-Path $context.OutputPath 'Summary.json')
    $schema = Read-WudJson -Path (Join-Path $toolRoot 'Data/Summary.schema.json')
    foreach ($requiredProperty in @($schema.required)) {
        Assert-WudV110 ($null -ne $summary.PSObject.Properties[[string]$requiredProperty]) ("v1.1 summary required property {0}" -f $requiredProperty)
    }
    Assert-WudV110 ($summary.SchemaSemanticVersion -eq '1.1.0') 'v1.1 summary semantic version'
    Assert-WudV110 ($summary.AnalysisMode -eq 'FactOnly') 'Summary declares fact-only mode'
    Assert-WudV110 ($summary.AttemptScope.ValidatedWindowsUpdate -eq 1) 'Summary reports validated attempt count'

    $collectorContext = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '1.1.0-test' -RunId 'safe-property-fixture' -RunPath (Join-Path $testRoot 'safe-run') -OutputPath (Join-Path $testRoot 'safe-output') -Mode 'Forensic' -PhaseLabel 'Forensic' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    $record = Invoke-WudCollector $collectorContext 'missing-name' 'Sparse process record fixture' {
        $null = $collectorContext.ProcessRecords.Add([pscustomobject]@{ Succeeded = $false; TimedOut = $false; ExitCodeHex = '0x00000001' })
    }
    Assert-WudV110 ($record.Status -eq 'CompletedWithWarnings') 'Sparse process records do not abort collector accounting'
    Assert-WudV110 ($record.Detail -match '<unnamed-process>') 'Missing process Name receives an explicit placeholder'

    $commonSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Common.psm1') -Raw
    $collectorSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Collectors.psm1') -Raw
    Assert-WudV110 ($commonSource -match 'if \(@\(\$ArgumentList\)\.Count -gt 0\) \{ \$parameters\.ArgumentList') 'Empty Start-Process ArgumentList is not bound'
    Assert-WudV110 ($collectorSource -notmatch '\$app\.DisplayName') 'Sparse uninstall entries use safe property access'
    Assert-WudV110 ($collectorSource.IndexOf("'raw-evidence'") -lt $collectorSource.IndexOf("'active-health'")) 'Passive raw capture precedes active diagnostics'
    Assert-WudV110 ($collectorSource -match '/LogPath:\{0\}') 'DISM ScanHealth uses an isolated diagnostic log path'

    Write-Host 'All v1.1 fixture tests passed.' -ForegroundColor Cyan
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
