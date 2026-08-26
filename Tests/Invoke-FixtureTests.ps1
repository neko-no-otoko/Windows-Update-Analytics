[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $toolRoot 'Modules/Common.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Analysis.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Report.psm1') -Force
Import-Module (Join-Path $toolRoot 'Modules/Persistence.psm1') -Force

function Assert-Wud {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("Win11UpgradeDiag-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    $runPath = Join-Path $testRoot 'run'
    $outputPath = Join-Path $testRoot 'output'
    $context = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '1.0.0-test' -RunId 'fixture-run' -RunPath $runPath -OutputPath $outputPath -Mode 'Preflight' -PhaseLabel 'Preflight' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    $identity = [pscustomobject][ordered]@{
        ComputerName = 'LAB-PC-01'; Domain = 'CONTOSO'; Manufacturer = 'Contoso'; Model = 'Model X';
        SerialNumber = 'ABC123'; UUID = '00000000-0000-0000-0000-000000000001'; ProductName = 'Windows 11 Enterprise';
        EditionId = 'Enterprise'; DisplayVersion = '23H2'; CurrentBuild = '22631'; UBR = 7517; SystemLocale = 'en-US'
    }
    $hardware = [pscustomobject][ordered]@{
        LogicalDisks = @([pscustomobject]@{ DeviceID = 'C:'; FreeSpace = 50GB; Size = 200GB })
        Tpm = [pscustomobject]@{ TpmPresent = $true; TpmReady = $true }
        SecureBoot = $true
        PhysicalDisks = @([pscustomobject]@{ FriendlyName = 'Disk 0'; HealthStatus = 'Healthy' })
    }
    $software = [pscustomobject]@{ Applications = @([pscustomobject]@{ DisplayName = 'Contoso Legacy Filter'; DisplayVersion = '1.0' }) }
    $drivers = [pscustomobject]@{
        Devices = @(
            [pscustomobject]@{ Name = 'Contoso Filter'; DeviceID = 'ROOT\CONTOSO'; ConfigManagerErrorCode = 0 },
            [pscustomobject]@{ DeviceID = 'ROOT\SPARSE'; ConfigManagerErrorCode = 28 }
        )
        SignedDrivers = @([pscustomobject]@{ DeviceID = 'ROOT\CONTOSO'; DriverVersion = '1.0.0.0' })
    }
    $servicing = [pscustomobject]@{ PendingReboot = [pscustomobject]@{ IsPending = $true }; UpdateHistory = @(); HotFixes = @() }
    $management = [pscustomobject]@{ InternetTestsSuppressed = $true; Connectivity = @() }
    $context.Inventory['Identity'] = $identity
    $context.Inventory['Hardware'] = $hardware
    $context.Inventory['Software'] = $software
    $context.Inventory['Drivers'] = $drivers
    $context.Inventory['Servicing'] = $servicing
    $context.Inventory['Management'] = $management
    $null = $context.CollectorRecords.Add([pscustomobject]@{ Id = 'fixture'; Description = 'Fixture collector'; Required = $true; Status = 'Succeeded'; Detail = $null; StartedUtc = [DateTime]::UtcNow.ToString('o'); EndedUtc = [DateTime]::UtcNow.ToString('o'); DurationMs = 5 })

    $raw = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'Raw/WindowsBT-Rollback')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'Tests/Fixtures/setupact-driver-rollback.log') -Destination (Join-Path $raw 'setupact.log')
    $setupDiag = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'SetupDiag')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'Tests/Fixtures/SetupDiagResults.json') -Destination (Join-Path $setupDiag 'SetupDiagResults.json')
    $servicingPath = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'Servicing')
    Write-WudJsonAtomic -Path (Join-Path $servicingPath 'servicing.json') -InputObject $servicing
    $inventoryPath = New-WudDirectory -Path (Join-Path $context.SnapshotPath 'Inventory')
    Write-WudJsonAtomic -Path (Join-Path $inventoryPath 'drivers.json') -InputObject $drivers
    Write-WudJsonAtomic -Path (Join-Path $context.SnapshotPath 'raw-copy-results.json') -InputObject ([pscustomobject]@{
        Sources = @([pscustomobject]@{ Source = 'C:\$WINDOWS.~BT\Sources\Rollback'; Destination = 'WindowsBT-Rollback'; Present = $true; Copied = $true })
        MemoryDump = $null
    })
    Write-WudJsonAtomic -Path (Join-Path $context.SnapshotPath 'collector-records.json') -InputObject @($context.CollectorRecords)
    Write-WudJsonAtomic -Path (Join-Path $context.SnapshotPath 'inventory.json') -InputObject $context.Inventory -Depth 30

    $decoded = Get-WudPhaseOperation '0x20017'
    Assert-Wud ($decoded.Phase -eq 'SafeOS') 'Extend-code phase decoding'
    Assert-Wud ($decoded.Operation -eq 'Boot') 'Extend-code operation decoding'
    $dstEarlier = ConvertTo-WudLogTimestamp '2025-11-02T01:30:00-05:00'
    $dstLater = ConvertTo-WudLogTimestamp '2025-11-02T01:30:00-06:00'
    Assert-Wud ($dstEarlier.ExplicitOffset -and $dstLater.ExplicitOffset) 'Explicit timestamp offsets preserved'
    Assert-Wud (([DateTimeOffset]::Parse($dstEarlier.TimestampUtc)) -lt ([DateTimeOffset]::Parse($dstLater.TimestampUtc))) 'DST repeated-hour ordering uses explicit offsets'

    $analysis = Invoke-WudAnalysis -Context $context
    Assert-Wud ($analysis.Outcome -eq 'Blocked') 'Preflight blocker outcome'
    Assert-Wud (@($analysis.Findings | Where-Object RuleId -eq 'WUD-COMPAT-APP-BLOCK').Count -eq 1) 'Compatibility application blocker rule'
    $appFinding = @($analysis.Findings | Where-Object RuleId -eq 'WUD-COMPAT-APP-BLOCK')[0]
    Assert-Wud ($appFinding.Confidence -eq 'High') 'Structured SetupDiag confidence precedence'
    Assert-Wud ($appFinding.AffectedEntity -match 'Contoso Legacy Filter') 'Structured SetupDiag affected entity extraction'
    Assert-Wud (@($appFinding.Codes) -contains '0xC1900208') 'Normalized finding code collection'
    Assert-Wud (@($analysis.Findings | Where-Object RuleId -eq 'WUD-DRIVER-ROLLBACK').Count -eq 1) 'Driver rollback rule'
    Assert-Wud (@($analysis.Findings | Where-Object RuleId -eq 'WUD-PENDING-REBOOT').Count -eq 1) 'Inventory finding evidence chain'
    Assert-Wud (@($analysis.Findings | Where-Object RuleId -eq 'WUD-PROBLEM-DEVICES').Count -eq 1) 'Sparse PnP record does not fail missing Name access'
    $pendingFinding = @($analysis.Findings | Where-Object RuleId -eq 'WUD-PENDING-REBOOT')[0]
    Assert-Wud ($pendingFinding.InstanceKey -eq 'pending-reboot') 'Custom finding positional contract'
    Assert-Wud ($pendingFinding.Recommendation -match 'servicing|restart') 'Custom finding recommendation contract'
    Assert-Wud (@($analysis.Timeline).Count -gt 0) 'Setup timeline extraction'
    Assert-Wud (@($analysis.Attempts).Count -eq 1) 'Attempt inventory segmentation'

    $report = Export-WudReportArtifacts -Context $context
    foreach ($artifact in @('Report.html', 'Summary.json', 'Findings.csv', 'Timeline.csv', 'Inventory.json', 'Evidence.zip', 'Manifest.json', 'Checksums.sha256', 'Collector.log')) {
        Assert-Wud (Test-Path -LiteralPath (Join-Path $outputPath $artifact)) "Artifact $artifact"
    }
    $reportText = Get-Content -LiteralPath $report -Raw
    Assert-Wud ($reportText -match 'Content-Security-Policy') 'Offline report content security policy'
    Assert-Wud ($reportText -match 'Contoso Legacy Filter') 'Evidence rendered into report'
    Assert-Wud ($reportText -notmatch '<script\s+src=') 'No external JavaScript dependency'
    Assert-Wud ($reportText -notmatch "<script>alert\('fixture'\)</script>") 'Collected HTML is escaped'
    Assert-Wud ($reportText -match '&lt;script&gt;alert') 'Escaped collected markup remains reviewable'
    Assert-Wud ($reportText -notmatch "script-src &#39;unsafe-inline&#39;") 'Nonce-based script content security policy'
    Assert-Wud ($reportText -match 'id="status-filter"') 'Finding status filter'
    Assert-Wud ($reportText -match 'Copy recommendation') 'Copyable finding recommendations'
    Assert-Wud ($reportText -match 'id="finding-WUD-') 'Finding anchor targets'
    Assert-Wud ($reportText -match 'Phase / operation') 'Timeline phase and operation columns'

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $outputPath 'Evidence.zip'))
    try { Assert-Wud ($archive.Entries.Count -gt 0) 'Evidence ZIP can be reopened' }
    finally { $archive.Dispose() }

    $summary = Read-WudJson -Path (Join-Path $outputPath 'Summary.json')
    $summarySchema = Read-WudJson -Path (Join-Path $toolRoot 'Data/Summary.schema.json')
    foreach ($requiredProperty in @($summarySchema.required)) {
        Assert-Wud ($null -ne $summary.PSObject.Properties[[string]$requiredProperty]) ("Fleet schema required property: {0}" -f $requiredProperty)
    }
    Assert-Wud ($summary.SchemaVersion -eq 1) 'Fleet summary schema version'
    Assert-Wud ($summary.Device.ComputerName -eq 'LAB-PC-01') 'Fleet summary device identity'
    Assert-Wud ($summary.Outcome -eq 'Blocked') 'Fleet summary outcome'
    Assert-Wud ($summary.RuleCatalogVersion -eq '1.1.0') 'Fleet summary rule catalog version'
    Assert-Wud (@($summary.CollectionCoverage).Count -gt 0) 'Fleet summary collection coverage'
    Assert-Wud (@($summary.ArtifactHashes).Count -ge 5) 'Fleet summary artifact hashes'
    $manifest = Read-WudJson -Path (Join-Path $outputPath 'Manifest.json')
    Assert-Wud ($manifest.ArchiveVerification.Verified) 'Evidence archive hash verification'
    Assert-Wud (@($manifest.SourceMappings).Count -eq 1) 'Evidence source-to-archive mapping'
    Assert-Wud ($manifest.SourceMappings[0].ArchivePrefix -eq 'Preflight/Raw/WindowsBT-Rollback') 'Evidence mapping archive prefix'
    foreach ($finding in @($analysis.Findings)) {
        foreach ($evidence in @($finding.Evidence)) {
            $relative = ([string]$evidence.SourcePath).Replace('\', [IO.Path]::DirectorySeparatorChar)
            Assert-Wud (Test-Path -LiteralPath (Join-Path $context.EvidencePath $relative)) ("Evidence reference resolves: {0}" -f $evidence.Reference)
        }
    }
    Assert-Wud ((ConvertTo-WudCsvCell '=HYPERLINK("bad")') -match "^'") 'CSV formula neutralization'

    $emptyRun = Join-Path $testRoot 'empty-run'
    $emptyOutput = Join-Path $testRoot 'empty-output'
    $emptyContext = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '1.0.0-test' -RunId 'empty-fixture' -RunPath $emptyRun -OutputPath $emptyOutput -Mode 'Preflight' -PhaseLabel 'Preflight' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    $emptyContext.Inventory = [ordered]@{ Baseline = $null; Current = $context.Inventory.Current; Diff = $null }
    $emptyContext.Outcome = 'Ready'; $emptyContext.ExitCode = 0; $emptyContext.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $null = $emptyContext.CollectorRecords.Add([pscustomobject]@{ Id = 'empty-fixture'; Version = '1.0.0-test'; Description = 'Empty contract fixture'; Required = $false; Status = 'Succeeded'; Detail = $null; StartedUtc = $emptyContext.StartedUtc; EndedUtc = $emptyContext.CompletedUtc; DurationMs = 1 })
    Write-WudLog -Context $emptyContext -Level INFO -Message 'Creating an empty findings/timeline contract fixture.'
    $null = Export-WudReportArtifacts -Context $emptyContext
    Assert-Wud ((Get-Item -LiteralPath (Join-Path $emptyOutput 'Findings.csv')).Length -gt 0) 'Empty findings CSV retains its header contract'
    Assert-Wud ((Get-Item -LiteralPath (Join-Path $emptyOutput 'Timeline.csv')).Length -gt 0) 'Empty timeline CSV retains its header contract'

    $collectorSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Collectors.psm1') -Raw
    Assert-Wud ($collectorSource -notmatch '(?i)/RestoreHealth|/ScanNow|chkdsk(?:\.exe)?\s+[^\r\n]*(?:/f|/r)') 'No repair-mode servicing commands'
    Assert-Wud ($collectorSource -notmatch '(?i)Win32_Product') 'No Win32_Product inventory side effects'
    Assert-Wud ($collectorSource -match "'/compat', 'scanonly'") 'Media execution is scan-only'
    Assert-Wud ($collectorSource -match '\$dynamicUpdate\s*=\s*''Disable''') 'Media scan disables Dynamic Update'

    $successRun = Join-Path $testRoot 'success-run'
    $successOutput = Join-Path $testRoot 'success-output'
    $successContext = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '1.0.0-test' -RunId 'success-fixture' -RunPath $successRun -OutputPath $successOutput -Mode 'Resume' -PhaseLabel 'Resume' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    $successIdentity = ($identity | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
    $successIdentity.DisplayVersion = '25H2'
    $successIdentity.CurrentBuild = '26200'
    $baselineSoftware = [pscustomobject]@{ Applications = @([pscustomobject]@{ DisplayName = 'Contoso Legacy Filter'; DisplayVersion = '1.0' }); Services = @([pscustomobject]@{ Name = 'ContosoSvc'; State = 'Running'; StartMode = 'Auto'; PathName = 'contoso.exe'; StartName = 'LocalSystem' }); AntivirusProducts = @() }
    $currentSoftware = [pscustomobject]@{ Applications = @([pscustomobject]@{ DisplayName = 'Contoso Legacy Filter'; DisplayVersion = '2.0' }); Services = @([pscustomobject]@{ Name = 'ContosoSvc'; State = 'Stopped'; StartMode = 'Manual'; PathName = 'contoso.exe'; StartName = 'LocalSystem' }); AntivirusProducts = @() }
    $baselineServicing = [pscustomobject]@{ PendingReboot = [pscustomobject]@{ IsPending = $false }; UpdateHistory = @(); HotFixes = @(); Packages = @([pscustomobject]@{ PackageName = 'Package-A'; PackageState = 'Installed'; ReleaseType = 'Update'; InstallTime = '2026-01-01' }) }
    $currentServicing = [pscustomobject]@{ PendingReboot = [pscustomobject]@{ IsPending = $false }; UpdateHistory = @(); HotFixes = @(); Packages = @([pscustomobject]@{ PackageName = 'Package-B'; PackageState = 'Installed'; ReleaseType = 'Update'; InstallTime = '2026-08-20' }) }
    $baselineManagement = [pscustomobject]@{ InternetTestsSuppressed = $true; Connectivity = @(); NetworkAdapters = @([pscustomobject]@{ InterfaceDescription = 'Ethernet'; Name = 'Ethernet'; Status = 'Up'; MacAddress = '00-00-00-00-00-01'; LinkSpeed = '1 Gbps'; DriverVersion = '1.0' }) }
    $currentManagement = [pscustomobject]@{ InternetTestsSuppressed = $true; Connectivity = @(); NetworkAdapters = @([pscustomobject]@{ InterfaceDescription = 'Ethernet'; Name = 'Ethernet'; Status = 'Up'; MacAddress = '00-00-00-00-00-01'; LinkSpeed = '1 Gbps'; DriverVersion = '2.0' }) }
    $successDrivers = [pscustomobject]@{ Devices = @([pscustomobject]@{ Name = 'Contoso Filter'; DeviceID = 'ROOT\CONTOSO'; ConfigManagerErrorCode = 0 }); SignedDrivers = $drivers.SignedDrivers }
    $baselineInventory = [pscustomobject][ordered]@{ Identity = $identity; Hardware = $hardware; Software = $baselineSoftware; Drivers = $successDrivers; Servicing = $baselineServicing; Management = $baselineManagement }
    $currentInventory = [pscustomobject][ordered]@{ Identity = $successIdentity; Hardware = $hardware; Software = $currentSoftware; Drivers = $successDrivers; Servicing = $currentServicing; Management = $currentManagement }
    $baselineSnapshot = New-WudDirectory -Path (Join-Path $successContext.EvidencePath 'Preflight')
    Write-WudJsonAtomic -Path (Join-Path $baselineSnapshot 'inventory.json') -InputObject $baselineInventory -Depth 30
    Write-WudJsonAtomic -Path (Join-Path $successContext.SnapshotPath 'inventory.json') -InputObject $currentInventory -Depth 30
    foreach ($property in $currentInventory.PSObject.Properties) { $successContext.Inventory[$property.Name] = $property.Value }
    $successRaw = New-WudDirectory -Path (Join-Path $successContext.SnapshotPath 'Raw/WindowsBT-Rollback')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'Tests/Fixtures/setupact-driver-rollback.log') -Destination (Join-Path $successRaw 'setupact.log')
    $successAnalysis = Invoke-WudAnalysis -Context $successContext
    Assert-Wud ($successAnalysis.Outcome -eq 'Upgrade Succeeded') 'Later target milestone outcome precedence'
    Assert-Wud ($successAnalysis.ExitCode -eq 0) 'Historical setup failure does not fail a successful target build'
    Assert-Wud (@($successAnalysis.Findings | Where-Object { $_.RuleId -eq 'WUD-DRIVER-ROLLBACK' -and $_.Status -eq 'Historical' }).Count -eq 1) 'Later success suppresses earlier setup failure noise'
    Assert-Wud ($successAnalysis.Inventory.Diff.Available) 'Pre/post comparison availability'
    Assert-Wud (@($successAnalysis.Inventory.Diff.Packages.Added).Count -eq 1) 'Package pre/post comparison'
    Assert-Wud (@($successAnalysis.Inventory.Diff.Services.Changed).Count -eq 1) 'Service pre/post comparison'
    Assert-Wud (@($successAnalysis.Inventory.Diff.Networks.Changed).Count -eq 1) 'Network pre/post comparison'

    $multiRun = Join-Path $testRoot 'multi-attempt-run'
    $multiOutput = Join-Path $testRoot 'multi-attempt-output'
    $multiContext = New-WudRunContext -ToolRoot $toolRoot -ToolVersion '1.0.0-test' -RunId 'multi-attempt-fixture' -RunPath $multiRun -OutputPath $multiOutput -Mode 'Forensic' -PhaseLabel 'Forensic' -TargetVersion '25H2' -CopyTo $null -MediaPath $null -AcceptWindowsEula $false -IncludeLargeDumps $false -NoInternet $true -NoSetupHooks $true -ArmDays 30
    $multiServicing = [pscustomobject]@{ PendingReboot = [pscustomobject]@{ IsPending = $false }; UpdateHistory = @(); HotFixes = @(); Packages = @() }
    $multiManagement = [pscustomobject]@{ InternetTestsSuppressed = $true; Connectivity = @(); NetworkAdapters = @(); RegistryExports = [pscustomobject]@{} }
    $multiInventory = [pscustomobject][ordered]@{ Identity = $identity; Hardware = $hardware; Software = $software; Drivers = $drivers; Servicing = $multiServicing; Management = $multiManagement }
    foreach ($property in $multiInventory.PSObject.Properties) { $multiContext.Inventory[$property.Name] = $property.Value }
    Write-WudJsonAtomic -Path (Join-Path $multiContext.SnapshotPath 'inventory.json') -InputObject $multiInventory -Depth 30
    $firstAttempt = New-WudDirectory -Path (Join-Path $multiContext.SnapshotPath 'Raw/Attempt-One')
    $secondAttempt = New-WudDirectory -Path (Join-Path $multiContext.SnapshotPath 'Raw/Attempt-Two')
    Write-WudText -Path (Join-Path $firstAttempt 'setupact.log') -Text "2025-11-02T01:30:00-05:00 Error 0xC1900101 - 0x20017 first attempt"
    Write-WudText -Path (Join-Path $secondAttempt 'setupact.log') -Text "2025-11-02T01:30:00-06:00 Fatal Error 0xC1900208 second truncated attempt"
    $multiAnalysis = Invoke-WudAnalysis -Context $multiContext
    Assert-Wud (@($multiAnalysis.Attempts).Count -eq 2) 'Multiple setup attempts remain segmented'
    Assert-Wud (@($multiAnalysis.Timeline).Count -ge 2) 'Truncated logs remain parseable'
    Assert-Wud (([DateTimeOffset]::Parse($multiAnalysis.Timeline[0].TimestampUtc)) -lt ([DateTimeOffset]::Parse($multiAnalysis.Timeline[1].TimestampUtc))) 'Timeline remains UTC ordered across repeated DST hour'

    $originalSystemDrive = $env:SystemDrive
    $fakeSystemDrive = New-WudDirectory -Path (Join-Path $testRoot 'system-drive')
    $env:SystemDrive = $fakeSystemDrive
    try {
        $setupRunPath = New-WudDirectory -Path (Join-Path $testRoot 'setupconfig-run')
        $configPath = Join-Path $fakeSystemDrive 'Users\Default\AppData\Local\Microsoft\Windows\WSUS\SetupConfig.ini'
        $null = New-WudDirectory -Path (Split-Path -Parent $configPath)
        $originalText = "[SetupConfig]`r`n; UTF-8 fixture: caf$([char]0x00E9)`r`nPriority=Normal"
        [byte[]]$preamble = [Text.Encoding]::UTF8.GetPreamble()
        [byte[]]$body = [Text.Encoding]::UTF8.GetBytes($originalText)
        [byte[]]$originalBytes = New-Object byte[] ($preamble.Length + $body.Length)
        [Array]::Copy($preamble, 0, $originalBytes, 0, $preamble.Length)
        [Array]::Copy($body, 0, $originalBytes, $preamble.Length, $body.Length)
        [IO.File]::WriteAllBytes($configPath, $originalBytes)
        $setupContext = [pscustomobject]@{ RunId = 'setupconfig-fixture'; RunPath = $setupRunPath }
        $hooks = [pscustomobject]@{ HookPath = (Join-Path $setupRunPath 'hooks') }
        $persistenceModule = Get-Module Persistence
        $setupMetadata = & $persistenceModule { param($ctx, $hookData) Install-WudSetupConfigHooks -Context $ctx -Hooks $hookData } $setupContext $hooks
        [byte[]]$modifiedBytes = [IO.File]::ReadAllBytes($configPath)
        $prefixPreserved = $modifiedBytes.Length -gt $originalBytes.Length
        for ($index = 0; $prefixPreserved -and $index -lt $originalBytes.Length; $index++) {
            if ($modifiedBytes[$index] -ne $originalBytes[$index]) { $prefixPreserved = $false }
        }
        Assert-Wud $prefixPreserved 'SetupConfig appends without changing original bytes'
        $setupState = [pscustomobject]@{ RunPath = $setupRunPath }
        $restoreResult = & $persistenceModule { param($ctx, $savedState) Restore-WudSetupConfig -Context $ctx -State $savedState } $setupContext $setupState
        [byte[]]$restoredBytes = [IO.File]::ReadAllBytes($configPath)
        $exactRestore = $restoredBytes.Length -eq $originalBytes.Length
        for ($index = 0; $exactRestore -and $index -lt $originalBytes.Length; $index++) {
            if ($restoredBytes[$index] -ne $originalBytes[$index]) { $exactRestore = $false }
        }
        Assert-Wud ($restoreResult -eq 'RestoredExactOriginal') 'SetupConfig exact restore path'
        Assert-Wud $exactRestore 'SetupConfig original bytes restored exactly'

        $divergedRunPath = New-WudDirectory -Path (Join-Path $testRoot 'setupconfig-diverged-run')
        Write-WudText -Path $configPath -Text "[SetupConfig]`r`nPostOOBE=C:\ExistingOwner`r`nPriority=Normal"
        $divergedContext = [pscustomobject]@{ RunId = 'setupconfig-diverged-fixture'; RunPath = $divergedRunPath }
        $divergedHooks = [pscustomobject]@{ HookPath = (Join-Path $divergedRunPath 'hooks') }
        $divergedMetadata = & $persistenceModule { param($ctx, $hookData) Install-WudSetupConfigHooks -Context $ctx -Hooks $hookData } $divergedContext $divergedHooks
        Assert-Wud (@($divergedMetadata.Conflicts | Where-Object Key -eq 'PostOOBE').Count -eq 1) 'SetupConfig conflicting key is retained'
        [IO.File]::AppendAllText($configPath, "AdminValue=Keep`r`n", (New-Object Text.UTF8Encoding($false)))
        $divergedState = [pscustomobject]@{ RunPath = $divergedRunPath }
        $divergedRestore = & $persistenceModule { param($ctx, $savedState) Restore-WudSetupConfig -Context $ctx -State $savedState } $divergedContext $divergedState
        $divergedText = [IO.File]::ReadAllText($configPath)
        Assert-Wud ($divergedRestore -eq 'RemovedOwnedEntriesFromDivergedFile') 'SetupConfig divergent cleanup path'
        Assert-Wud ($divergedText -match 'PostOOBE=C:\\ExistingOwner') 'SetupConfig preserves pre-existing conflicting value'
        Assert-Wud ($divergedText -match 'AdminValue=Keep') 'SetupConfig preserves later administrator edit'
        Assert-Wud ($divergedText -notmatch [Regex]::Escape([string]$divergedHooks.HookPath)) 'SetupConfig removes only owned hook values'

        $noHookState = [pscustomobject]@{ RunPath = (Join-Path $testRoot 'no-hooks-run') }
        $noHookResult = & $persistenceModule { param($ctx, $savedState) Restore-WudSetupConfig -Context $ctx -State $savedState } $setupContext $noHookState
        Assert-Wud ($noHookResult -eq 'NotConfigured') 'NoSetupHooks cleanup does not report a false failure'
    }
    finally {
        if ($null -eq $originalSystemDrive) { Remove-Item Env:SystemDrive -ErrorAction SilentlyContinue }
        else { $env:SystemDrive = $originalSystemDrive }
    }
    Write-Host 'All fixture tests passed.' -ForegroundColor Cyan
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
