Set-StrictMode -Version 2.0

function ConvertTo-WudHtmlText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-WudProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Get-WudAllCollectorRecords {
    param($Context)
    $records = New-Object Collections.ArrayList
    foreach ($file in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter 'collector-records.json' -ErrorAction SilentlyContinue)) {
        $snapshot = Split-Path -Leaf (Split-Path -Parent $file.FullName)
        foreach ($record in @(Read-WudJson -Path $file.FullName)) {
            $null = $records.Add([pscustomobject][ordered]@{
                Snapshot    = $snapshot
                Id          = $record.Id
                Version     = Get-WudProperty $record 'Version' $Context.ToolVersion
                Description = $record.Description
                Required    = $record.Required
                Status      = $record.Status
                Detail      = $record.Detail
                StartedUtc  = $record.StartedUtc
                EndedUtc    = $record.EndedUtc
                DurationMs  = $record.DurationMs
            })
        }
    }
    if (@($records).Count -eq 0) {
        foreach ($record in @($Context.CollectorRecords)) {
            $null = $records.Add([pscustomobject][ordered]@{
                Snapshot = $Context.PhaseLabel; Id = $record.Id; Version = Get-WudProperty $record 'Version' $Context.ToolVersion
                Description = $record.Description; Required = $record.Required; Status = $record.Status; Detail = $record.Detail
                StartedUtc = $record.StartedUtc; EndedUtc = $record.EndedUtc; DurationMs = $record.DurationMs
            })
        }
    }
    return @($records)
}

function New-WudEvidenceArchive {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        $Context
    )
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $DestinationPath) { Remove-Item -LiteralPath $DestinationPath -Force }
    $destinationParent = Split-Path -Parent $DestinationPath
    if ($destinationParent) { $null = New-WudDirectory -Path $destinationParent }
    $zipStream = [IO.File]::Open($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = $null
    try {
        $archive = New-Object IO.Compression.ZipArchive($zipStream, [IO.Compression.ZipArchiveMode]::Create, $false)
        foreach ($file in Get-ChildItem -LiteralPath $SourcePath -File -Recurse -Force -ErrorAction Stop) {
            $relative = (Get-WudRelativePath -BasePath $SourcePath -Path $file.FullName).Replace('\', '/')
            $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $file.LastWriteTime
            $sourceStream = $null
            $entryStream = $null
            try {
                $sourceStream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                $entryStream = $entry.Open()
                $sourceStream.CopyTo($entryStream)
            }
            catch {
                if ($Context) {
                    $null = Add-WudCollectionGap -Context $Context -Collector 'report-archive' -Source $file.FullName -Status 'ArchiveReadFailed' -Detail $_.Exception.Message
                    Write-WudLog -Context $Context -Level WARN -Message ("Evidence could not be added to the archive: {0}: {1}" -f $file.FullName, $_.Exception.Message)
                }
            }
            finally {
                if ($entryStream) { $entryStream.Dispose() }
                if ($sourceStream) { $sourceStream.Dispose() }
            }
        }
    }
    finally {
        if ($archive) { $archive.Dispose() }
        else { $zipStream.Dispose() }
    }
}

function Test-WudEvidenceArchiveIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$EvidenceManifest
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $missing = New-Object Collections.ArrayList
    $mismatched = New-Object Collections.ArrayList
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries = @{}
        foreach ($entry in $archive.Entries) { $entries[$entry.FullName.ToLowerInvariant()] = $entry }
        foreach ($item in @($EvidenceManifest)) {
            $name = ([string]$item.RelativePath).Replace('\', '/').ToLowerInvariant()
            if (-not $entries.ContainsKey($name)) { $null = $missing.Add($item.RelativePath); continue }
            if (-not $item.Sha256) { continue }
            $stream = $null
            $sha = $null
            try {
                $stream = $entries[$name].Open()
                $sha = [Security.Cryptography.SHA256]::Create()
                $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
                if ($actual -ne [string]$item.Sha256) { $null = $mismatched.Add($item.RelativePath) }
            }
            finally {
                if ($sha) { $sha.Dispose() }
                if ($stream) { $stream.Dispose() }
            }
        }
        return [pscustomobject][ordered]@{
            Verified       = (@($missing).Count -eq 0 -and @($mismatched).Count -eq 0)
            ExpectedFiles  = @($EvidenceManifest).Count
            ArchiveEntries = $archive.Entries.Count
            Missing        = @($missing)
            HashMismatches = @($mismatched)
            VerifiedUtc    = [DateTime]::UtcNow.ToString('o')
        }
    }
    finally { $archive.Dispose() }
}

function Get-WudArtifactRecord {
    param([string]$Path, [string]$BasePath)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $file = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        Name         = Get-WudRelativePath -BasePath $BasePath -Path $file.FullName
        Length       = $file.Length
        LastWriteUtc = $file.LastWriteTimeUtc.ToString('o')
        Sha256       = Get-WudFileHashSafe -Path $file.FullName
    }
}

function Export-WudCsvContract {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Headers,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $rowArray = @($Rows)
    if ($rowArray.Count -gt 0) {
        @($rowArray | Select-Object -Property $Headers) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return
    }
    $headerLine = (@($Headers | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }) -join ',') + [Environment]::NewLine
    Write-WudText -Path $Path -Text $headerLine
}

function Get-WudEvidenceSourceMappings {
    param($Context)
    $mappings = New-Object Collections.ArrayList
    foreach ($file in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter 'raw-copy-results.json' -ErrorAction SilentlyContinue)) {
        $relativeRecord = (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName).Replace('\', '/')
        $snapshot = @($relativeRecord -split '/')[0]
        $record = Read-WudJson -Path $file.FullName
        foreach ($source in @($record.Sources)) {
            $null = $mappings.Add([pscustomobject][ordered]@{
                Snapshot      = $snapshot
                SourcePath    = $source.Source
                ArchivePrefix = ('{0}/Raw/{1}' -f $snapshot, $source.Destination)
                Present       = [bool]$source.Present
                Copied        = [bool]$source.Copied
                State         = if (-not $source.Present) { 'Missing' } elseif ($source.Copied) { 'Copied' } else { 'CopyFailedOrEmpty' }
            })
        }
        if ($record.MemoryDump) {
            $null = $mappings.Add([pscustomobject][ordered]@{
                Snapshot      = $snapshot
                SourcePath    = $record.MemoryDump.Path
                ArchivePrefix = if ($record.MemoryDump.Copied) { "$snapshot/Raw/Windows-MEMORY.DMP" } else { $null }
                Present       = $true
                Copied        = [bool]$record.MemoryDump.Copied
                State         = if ($record.MemoryDump.Copied) { 'Copied' } else { 'MetadataOnly' }
                Length        = $record.MemoryDump.Length
                LastWriteUtc  = $record.MemoryDump.LastWriteUtc
                Sha256        = $record.MemoryDump.Sha256
                Detail        = $record.MemoryDump.CopyReason
            })
        }
    }
    return @($mappings)
}

function New-WudSummaryObject {
    param($Context, $CollectorRecords, $ArtifactRecords)
    $current = Get-WudProperty -Object $Context.Inventory -Name 'Current'
    $baseline = Get-WudProperty -Object $Context.Inventory -Name 'Baseline'
    $currentIdentity = Get-WudProperty -Object $current -Name 'Identity'
    if (-not $currentIdentity) { $currentIdentity = Get-WudProperty -Object $baseline -Name 'Identity' }
    $baselineIdentity = Get-WudProperty -Object $baseline -Name 'Identity'
    if (-not $baselineIdentity) { $baselineIdentity = $currentIdentity }
    if ($baselineIdentity -eq $currentIdentity) {
        $history = @(Get-WudProperty -Object $currentIdentity -Name 'SourceOsHistory' -Default @())
        $historicalSource = @($history | Where-Object { $_.DisplayVersion -and $_.DisplayVersion -ne $currentIdentity.DisplayVersion } | Select-Object -First 1)
        if (@($historicalSource).Count -gt 0) {
            $baselineIdentity = [pscustomobject][ordered]@{
                ProductName    = $historicalSource[0].ProductName
                EditionId      = $currentIdentity.EditionId
                DisplayVersion = $historicalSource[0].DisplayVersion
                CurrentBuild   = $historicalSource[0].CurrentBuild
                UBR            = $historicalSource[0].UBR
            }
        }
    }
    $primary = $Context.PrimaryFinding
    $ruleCatalog = Read-WudJson -Path (Join-Path $Context.ToolRoot 'Data/rules.json')
    $targetCatalog = Read-WudJson -Path (Join-Path $Context.ToolRoot 'Data/targets.json')
    return [pscustomobject][ordered]@{
        SchemaVersion      = 1
        SchemaSemanticVersion = '1.0.0'
        ToolVersion        = $Context.ToolVersion
        RuleCatalogVersion = Get-WudProperty $ruleCatalog 'catalogVersion' '1'
        TargetMapVersion   = Get-WudProperty $targetCatalog 'mapVersion' '1'
        RunId              = $Context.RunId
        Mode               = $Context.Mode
        PhaseLabel         = $Context.PhaseLabel
        StartedUtc         = $Context.StartedUtc
        CompletedUtc       = $Context.CompletedUtc
        Run                = [pscustomobject][ordered]@{
            RunId = $Context.RunId; Mode = $Context.Mode; PhaseLabel = $Context.PhaseLabel
            ComputerName = Get-WudProperty $currentIdentity 'ComputerName'
            StartedUtc = $Context.StartedUtc; CompletedUtc = $Context.CompletedUtc
        }
        Timestamps         = [pscustomobject][ordered]@{ StartedUtc = $Context.StartedUtc; CompletedUtc = $Context.CompletedUtc }
        Sensitive          = $true
        Outcome            = $Context.Outcome
        ExitCode           = $Context.ExitCode
        Device             = [pscustomobject][ordered]@{
            ComputerName = Get-WudProperty $currentIdentity 'ComputerName'
            Domain       = Get-WudProperty $currentIdentity 'Domain'
            Manufacturer = Get-WudProperty $currentIdentity 'Manufacturer'
            Model        = Get-WudProperty $currentIdentity 'Model'
            SerialNumber = Get-WudProperty $currentIdentity 'SerialNumber'
            UUID         = Get-WudProperty $currentIdentity 'UUID'
        }
        SourceOs           = [pscustomobject][ordered]@{
            Product        = Get-WudProperty $baselineIdentity 'ProductName'
            Edition        = Get-WudProperty $baselineIdentity 'EditionId'
            DisplayVersion = Get-WudProperty $baselineIdentity 'DisplayVersion'
            Build          = Get-WudProperty $baselineIdentity 'CurrentBuild'
            UBR            = Get-WudProperty $baselineIdentity 'UBR'
        }
        CurrentOs          = [pscustomobject][ordered]@{
            Product        = Get-WudProperty $currentIdentity 'ProductName'
            Edition        = Get-WudProperty $currentIdentity 'EditionId'
            DisplayVersion = Get-WudProperty $currentIdentity 'DisplayVersion'
            Build          = Get-WudProperty $currentIdentity 'CurrentBuild'
            UBR            = Get-WudProperty $currentIdentity 'UBR'
        }
        TargetOs           = [pscustomobject][ordered]@{
            Product        = $Context.Target.product
            DisplayVersion = $Context.Target.displayVersion
            BuildFamily    = $Context.Target.buildFamily
        }
        PrimaryFinding     = $primary
        Findings           = @($Context.Findings)
        FindingCounts      = [pscustomobject][ordered]@{
            Blocker     = @($Context.Findings | Where-Object { $_.Status -ne 'Historical' -and $_.Severity -eq 'Blocker' }).Count
            Error       = @($Context.Findings | Where-Object { $_.Status -ne 'Historical' -and $_.Severity -eq 'Error' }).Count
            Warning     = @($Context.Findings | Where-Object { $_.Status -ne 'Historical' -and $_.Severity -eq 'Warning' }).Count
            Information = @($Context.Findings | Where-Object { $_.Status -ne 'Historical' -and $_.Severity -eq 'Information' }).Count
            Historical  = @($Context.Findings | Where-Object Status -eq 'Historical').Count
            Total       = @($Context.Findings).Count
        }
        Attempts            = @($Context.Attempts)
        CollectionCoverage  = @($CollectorRecords)
        CollectionGaps      = @($Context.CollectionGaps)
        CollectionComplete  = $Context.CollectionComplete
        ArtifactHashes       = @($ArtifactRecords)
        Persistence          = Get-WudProperty $Context.Inventory 'Persistence'
    }
}

function Add-WudHtmlLine {
    param([Text.StringBuilder]$Builder, [string]$Text)
    $null = $Builder.AppendLine($Text)
}

function Get-WudOutcomeCssClass {
    param([string]$Outcome)
    return 'outcome-' + (($Outcome.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
}

function Build-WudReportHtml {
    param($Context, $Summary, $EvidenceManifest, $CollectorRecords)
    $css = Get-Content -LiteralPath (Join-Path $Context.ToolRoot 'Assets/report.css') -Raw
    $javascript = Get-Content -LiteralPath (Join-Path $Context.ToolRoot 'Assets/report.js') -Raw
    $builder = New-Object Text.StringBuilder
    $outcomeClass = Get-WudOutcomeCssClass -Outcome $Summary.Outcome
    $sourceDisplay = '{0} ({1}.{2})' -f $Summary.SourceOs.DisplayVersion, $Summary.SourceOs.Build, $Summary.SourceOs.UBR
    $currentDisplay = '{0} ({1}.{2})' -f $Summary.CurrentOs.DisplayVersion, $Summary.CurrentOs.Build, $Summary.CurrentOs.UBR
    $targetDisplay = '{0} (build family {1})' -f $Summary.TargetOs.DisplayVersion, $Summary.TargetOs.BuildFamily
    $coverageTotal = @($CollectorRecords).Count
    $coverageGood = @($CollectorRecords | Where-Object Status -eq 'Succeeded').Count
    $coverageText = if (-not $Summary.CollectionComplete) { 'Materially incomplete - review collection gaps' } elseif ($coverageTotal -gt 0) { '{0}/{1} collectors succeeded' -f $coverageGood, $coverageTotal } else { 'No collector records' }
    $nonceBytes = New-Object byte[] 18
    $random = New-Object Security.Cryptography.RNGCryptoServiceProvider
    try { $random.GetBytes($nonceBytes) } finally { $random.Dispose() }
    $nonce = [Convert]::ToBase64String($nonceBytes)

    Add-WudHtmlLine $builder '<!doctype html>'
    Add-WudHtmlLine $builder '<html lang="en"><head><meta charset="utf-8">'
    Add-WudHtmlLine $builder '<meta name="viewport" content="width=device-width,initial-scale=1">'
    Add-WudHtmlLine $builder ('<meta http-equiv="Content-Security-Policy" content="default-src &#39;none&#39;; base-uri &#39;none&#39;; object-src &#39;none&#39;; form-action &#39;none&#39;; style-src &#39;nonce-{0}&#39;; script-src &#39;nonce-{0}&#39;; img-src data:; font-src data:">' -f $nonce)
    Add-WudHtmlLine $builder ('<title>Win11UpgradeDiag - {0} - {1}</title>' -f (ConvertTo-WudHtmlText $Summary.Device.ComputerName), (ConvertTo-WudHtmlText $Summary.Outcome))
    Add-WudHtmlLine $builder ('<style nonce="{0}">{1}</style></head><body>' -f $nonce, $css)
    Add-WudHtmlLine $builder '<div class="sensitive-banner">FULL-FIDELITY DIAGNOSTIC DATA - Contains device, user, domain, network, software, and log identifiers. Handle as sensitive.</div>'
    Add-WudHtmlLine $builder '<nav class="topbar" aria-label="Report controls"><div class="brand"><span class="brand-mark">W</span><span>Win11UpgradeDiag</span></div><div class="top-actions"><button id="theme-toggle" type="button" aria-label="Toggle theme">Theme</button><button id="print-report" type="button">Print / PDF</button></div></nav>'
    Add-WudHtmlLine $builder '<main>'
    Add-WudHtmlLine $builder ('<header class="hero {0}"><div class="eyebrow">Windows feature-update diagnostic companion</div><h1>{1}</h1><span class="outcome-pill {0}">{2}</span><div class="hero-meta"><span><strong>Device:</strong> {3}</span><span><strong>Run:</strong> <code>{4}</code></span><span><strong>Completed:</strong> {5}</span></div></header>' -f $outcomeClass, (ConvertTo-WudHtmlText $Summary.Outcome), (ConvertTo-WudHtmlText $coverageText), (ConvertTo-WudHtmlText $Summary.Device.ComputerName), (ConvertTo-WudHtmlText $Summary.RunId), (ConvertTo-WudHtmlText $Summary.CompletedUtc))
    Add-WudHtmlLine $builder '<section class="summary-grid" aria-label="Upgrade summary">'
    Add-WudHtmlLine $builder ('<div class="metric"><div class="metric-label">Source OS</div><div class="metric-value">{0}</div><div class="metric-detail">{1}</div></div>' -f (ConvertTo-WudHtmlText $sourceDisplay), (ConvertTo-WudHtmlText $Summary.SourceOs.Edition))
    Add-WudHtmlLine $builder ('<div class="metric"><div class="metric-label">Current OS</div><div class="metric-value">{0}</div><div class="metric-detail">{1}</div></div>' -f (ConvertTo-WudHtmlText $currentDisplay), (ConvertTo-WudHtmlText $Summary.CurrentOs.Edition))
    Add-WudHtmlLine $builder ('<div class="metric"><div class="metric-label">Diagnostic target</div><div class="metric-value">{0}</div><div class="metric-detail">{1}</div></div>' -f (ConvertTo-WudHtmlText $targetDisplay), (ConvertTo-WudHtmlText $Summary.TargetOs.Product))
    Add-WudHtmlLine $builder ('<div class="metric"><div class="metric-label">Findings</div><div class="metric-value">{0} blocker &middot; {1} error</div><div class="metric-detail">{2} warning &middot; {3} informational &middot; {4} historical</div></div>' -f $Summary.FindingCounts.Blocker, $Summary.FindingCounts.Error, $Summary.FindingCounts.Warning, $Summary.FindingCounts.Information, $Summary.FindingCounts.Historical)
    Add-WudHtmlLine $builder '</section>'

    if ($Summary.Persistence) {
        $persistence = $Summary.Persistence
        $setupConfigState = if ($persistence.NoSetupHooks) { 'Setup hooks disabled by operator' } elseif ($persistence.SetupConfig.InvalidFormat) { 'SetupConfig invalid; hooks skipped' } elseif (@($persistence.SetupConfig.Conflicts).Count -gt 0) { '{0} SetupConfig conflicts retained' -f @($persistence.SetupConfig.Conflicts).Count } else { 'Guarded SetupConfig hooks installed' }
        Add-WudHtmlLine $builder ('<section class="panel"><h2>Cross-reboot capture</h2><div class="summary-grid"><div class="metric"><div class="metric-label">State</div><div class="metric-value">{0}</div></div><div class="metric"><div class="metric-label">Expires UTC</div><div class="metric-value">{1}</div></div><div class="metric"><div class="metric-label">Scheduled task</div><div class="metric-value">{2}</div></div><div class="metric"><div class="metric-label">Setup integration</div><div class="metric-value">{3}</div></div></div></section>' -f (ConvertTo-WudHtmlText $persistence.Status), (ConvertTo-WudHtmlText $persistence.ExpiresUtc), (ConvertTo-WudHtmlText $persistence.Task.FullName), (ConvertTo-WudHtmlText $setupConfigState))
    }

    if ($Summary.PrimaryFinding) {
        $primary = $Summary.PrimaryFinding
        Add-WudHtmlLine $builder '<section class="panel primary-finding"><div class="eyebrow">Primary finding</div>'
        Add-WudHtmlLine $builder ('<div class="finding-title-row"><h2>{0}</h2><div class="badges"><span class="badge {1}">{2}</span><span class="badge {3}">{4} confidence</span></div></div>' -f (ConvertTo-WudHtmlText $primary.Title), $primary.Severity.ToLowerInvariant(), (ConvertTo-WudHtmlText $primary.Severity), $primary.Confidence.ToLowerInvariant(), (ConvertTo-WudHtmlText $primary.Confidence))
        Add-WudHtmlLine $builder ('<p>{0}</p><h3>Recommended next action</h3><p><span id="primary-recommendation">{1}</span> <button class="copy-inline" type="button" data-copy-target="primary-recommendation">Copy recommendation</button></p>' -f (ConvertTo-WudHtmlText $primary.Explanation), (ConvertTo-WudHtmlText $primary.Recommendation))
        Add-WudHtmlLine $builder '</section>'
    }
    else {
        Add-WudHtmlLine $builder '<section class="panel primary-finding empty"><div class="eyebrow">Primary finding</div><h2>No blocker or error was identified</h2><p>Review warnings, collection coverage, and any evidence not available before treating this as a guarantee of upgrade success.</p></section>'
    }

    $detectedPhases = @($Context.Findings | Where-Object { $_.Phase } | ForEach-Object Phase) + @($Context.Attempts | ForEach-Object PhaseHint)
    Add-WudHtmlLine $builder '<section class="panel"><h2>Upgrade phase map</h2><p class="section-note">Detected phases are highlighted; an unhighlighted phase means no direct phase evidence was parsed, not necessarily that Setup never entered it.</p><div class="phase-track">'
    foreach ($phase in @('Downlevel', 'SafeOS', 'First Boot', 'OOBE Boot', 'Rollback')) {
        $detected = @($detectedPhases | Where-Object { $_ -match [Regex]::Escape($phase) }).Count -gt 0
        Add-WudHtmlLine $builder ('<div class="phase{0}">{1}</div>' -f $(if ($detected) { ' detected' } else { '' }), (ConvertTo-WudHtmlText $phase))
    }
    Add-WudHtmlLine $builder '</div></section>'

    $domains = @(
        [pscustomobject]@{ Id = 'domain-compatibility'; Title = 'Compatibility'; Categories = @('Compatibility'); Pattern = '(?i)Compatibility|AppCompat|CompatData|Appraiser|MediaScan'; Description = 'Appraiser, safeguard, system-requirement, application, and optional target-media scan evidence.' },
        [pscustomobject]@{ Id = 'domain-update'; Title = 'Update delivery and orchestration'; Categories = @('Update Delivery'); Pattern = '(?i)WindowsUpdate|USO|DeliveryOptimization|BITS'; Description = 'Offer, scan, download, proxy, source reachability, Delivery Optimization, and orchestrator evidence.' },
        [pscustomobject]@{ Id = 'domain-setup'; Title = 'Setup, migration, and rollback'; Categories = @('Setup', 'Migration'); Pattern = '(?i)Panther|Rollback|SetupDiag|MoSetup|Unattend|SetupCopyLogs'; Description = 'Setup phases, operations, result/extend codes, migration, fatal termination, and rollback evidence.' },
        [pscustomobject]@{ Id = 'domain-servicing'; Title = 'Servicing health'; Categories = @('Servicing'); Pattern = '(?i)Servicing|CBS|DISM|sfc|dism'; Description = 'Packages, update history, component store, pending state, DISM ScanHealth, and SFC verify-only.' },
        [pscustomobject]@{ Id = 'domain-drivers'; Title = 'Drivers and devices'; Categories = @('Drivers'); Pattern = '(?i)drivers|PnP|setupapi|pnputil|DeviceSetup'; Description = 'Signed drivers, driver store, problem devices, SetupAPI, and device installation evidence.' },
        [pscustomobject]@{ Id = 'domain-storage'; Title = 'Disks, WinRE, boot, and encryption'; Categories = @('Storage', 'Security', 'Hardware'); Pattern = '(?i)hardware|reagentc|bcdedit|manage-bde|mountvol|BitLocker|Storage'; Description = 'Capacity, partitions, storage health, BCD/boot state, WinRE, TPM, Secure Boot, and BitLocker status.' },
        [pscustomobject]@{ Id = 'domain-apps'; Title = 'Applications, features, and languages'; Categories = @('Applications'); Pattern = '(?i)software|Appx|feature|capabilit|language|profile|filter'; Description = 'Installed applications, AppX, provisioned packages, features, capabilities, languages, profiles, services, and filters.' },
        [pscustomobject]@{ Id = 'domain-policy'; Title = 'Management and policy'; Categories = @('Policy'); Pattern = '(?i)Management|policy|gpresult|dsregcmd|MDM|ConfigMgr|Intune'; Description = 'WUfB, WSUS, Group Policy, MDM, enrollment, co-management, source selection, and target policy.' },
        [pscustomobject]@{ Id = 'domain-crash'; Title = 'Crashes and hardware symptoms'; Categories = @('Crash'); Pattern = '(?i)Events|WER|Minidump|MEMORY|setupmem|reliability|dxdiag|msinfo'; Description = 'Bug checks, WER, setup/minidumps, reliability, WHEA, storage, and unexpected-reboot symptoms.' }
    )
    Add-WudHtmlLine $builder '<section class="panel"><h2>Diagnostic domains</h2><p class="section-note">Each domain links the normalized findings to the relevant files in the evidence archive.</p><div class="domain-grid">'
    foreach ($domain in $domains) {
        $domainFindings = @($Context.Findings | Where-Object { $domain.Categories -contains $_.Category })
        $domainEvidence = @($EvidenceManifest | Where-Object { $_.RelativePath -match $domain.Pattern })
        Add-WudHtmlLine $builder ('<a class="domain-card" href="#{0}"><strong>{1}</strong><span>{2} findings &middot; {3} evidence files</span></a>' -f $domain.Id, (ConvertTo-WudHtmlText $domain.Title), @($domainFindings).Count, @($domainEvidence).Count)
    }
    Add-WudHtmlLine $builder '</div></section>'
    foreach ($domain in $domains) {
        $domainFindings = @($Context.Findings | Where-Object { $domain.Categories -contains $_.Category })
        $domainEvidence = @($EvidenceManifest | Where-Object { $_.RelativePath -match $domain.Pattern })
        Add-WudHtmlLine $builder ('<section class="panel domain-section" id="{0}"><h2>{1}</h2><p>{2}</p>' -f $domain.Id, (ConvertTo-WudHtmlText $domain.Title), (ConvertTo-WudHtmlText $domain.Description))
        if (@($domainFindings).Count -gt 0) {
            Add-WudHtmlLine $builder '<ul class="compact-list">'
            foreach ($finding in @($domainFindings | Select-Object -First 8)) { Add-WudHtmlLine $builder ('<li><span class="badge {0}">{1}</span> {2} <span class="muted">({3}, {4})</span></li>' -f (ConvertTo-WudHtmlText $finding.Severity.ToLowerInvariant()), (ConvertTo-WudHtmlText $finding.Severity), (ConvertTo-WudHtmlText $finding.Title), (ConvertTo-WudHtmlText $finding.Confidence), (ConvertTo-WudHtmlText $finding.Status)) }
            Add-WudHtmlLine $builder '</ul>'
        }
        else { Add-WudHtmlLine $builder '<p class="muted">No domain-specific finding was emitted. This is not proof that all evidence was available or clean.</p>' }
        if (@($domainEvidence).Count -gt 0) { Add-WudHtmlLine $builder ('<p class="evidence-ref"><strong>Representative evidence:</strong> {0}</p>' -f (ConvertTo-WudHtmlText (@($domainEvidence | Select-Object -First 8 | ForEach-Object RelativePath) -join '; '))) }
        else { Add-WudHtmlLine $builder '<p class="evidence-ref"><strong>Representative evidence:</strong> none indexed.</p>' }
        Add-WudHtmlLine $builder '</section>'
    }

    $categories = @($Context.Findings | ForEach-Object Category | Sort-Object -Unique)
    Add-WudHtmlLine $builder '<section class="panel"><h2>Findings and evidence chains</h2><div class="toolbar"><input id="finding-search" type="search" placeholder="Search findings, codes, drivers, applications, or evidence" aria-label="Search findings"><select id="severity-filter" aria-label="Filter by severity"><option value="">All severities</option><option value="blocker">Blocker</option><option value="error">Error</option><option value="warning">Warning</option><option value="information">Information</option></select><select id="status-filter" aria-label="Filter by status"><option value="">All statuses</option><option value="active">Active</option><option value="historical">Historical</option></select><select id="category-filter" aria-label="Filter by category"><option value="">All categories</option>'
    foreach ($category in $categories) { Add-WudHtmlLine $builder ('<option value="{0}">{1}</option>' -f (ConvertTo-WudHtmlText $category.ToLowerInvariant()), (ConvertTo-WudHtmlText $category)) }
    Add-WudHtmlLine $builder '</select></div><div id="finding-cards">'
    $findingIndex = 0
    foreach ($finding in @($Context.Findings | Sort-Object @{ Expression = { Get-WudSeverityRank $_.Severity }; Descending = $true }, @{ Expression = { Get-WudConfidenceRank $_.Confidence }; Descending = $true }, Title)) {
        $findingIndex++
        $severityClass = $finding.Severity.ToLowerInvariant()
        $categoryClass = $finding.Category.ToLowerInvariant()
        $findingAnchor = 'finding-' + (([string]$finding.FindingId) -replace '[^A-Za-z0-9_.-]', '-')
        Add-WudHtmlLine $builder ('<details id="{4}" class="finding-card {0}" data-severity="{0}" data-category="{1}" data-status="{2}"{3}><summary>{5}<span class="badges align-right"><span class="badge {0}">{6}</span><span class="badge neutral">{7}</span><span class="badge neutral">{8}</span></span></summary><div class="finding-body">' -f (ConvertTo-WudHtmlText $severityClass), (ConvertTo-WudHtmlText $categoryClass), (ConvertTo-WudHtmlText $finding.Status.ToLowerInvariant()), $(if ($findingIndex -le 3) { ' open' } else { '' }), (ConvertTo-WudHtmlText $findingAnchor), (ConvertTo-WudHtmlText $finding.Title), (ConvertTo-WudHtmlText $finding.Severity), (ConvertTo-WudHtmlText $finding.Confidence), (ConvertTo-WudHtmlText $finding.Status))
        $recommendationId = "recommendation-$findingIndex"
        Add-WudHtmlLine $builder ('<p><strong>Why it matters:</strong> {0}</p><p><strong>Recommended action:</strong> <span id="{1}">{2}</span> <button class="copy-inline" type="button" data-copy-target="{1}">Copy recommendation</button></p>' -f (ConvertTo-WudHtmlText $finding.Explanation), $recommendationId, (ConvertTo-WudHtmlText $finding.Recommendation))
        if ($finding.AffectedEntity) { Add-WudHtmlLine $builder ('<p><strong>Affected entity:</strong> <code>{0}</code></p>' -f (ConvertTo-WudHtmlText $finding.AffectedEntity)) }
        if ($finding.DispositionReason) { Add-WudHtmlLine $builder ('<p class="muted"><strong>Disposition:</strong> {0}</p>' -f (ConvertTo-WudHtmlText $finding.DispositionReason)) }
        if ($finding.ResultCode -or $finding.ExtendCode -or $finding.Phase) {
            Add-WudHtmlLine $builder ('<p class="muted"><strong>Codes/phase:</strong> {0} {1} &middot; {2} / {3}</p>' -f (ConvertTo-WudHtmlText $finding.ResultCode), (ConvertTo-WudHtmlText $finding.ExtendCode), (ConvertTo-WudHtmlText $finding.Phase), (ConvertTo-WudHtmlText $finding.Operation))
        }
        Add-WudHtmlLine $builder '<div class="evidence-list">'
        $evidenceIndex = 0
        foreach ($evidence in @($finding.Evidence)) {
            $evidenceIndex++
            $copyId = "evidence-$findingIndex-$evidenceIndex"
            $evidenceLabel = if ($evidence.TimestampUtc) { '{0} | {1}' -f $evidence.Reference, $evidence.TimestampUtc } else { [string]$evidence.Reference }
            Add-WudHtmlLine $builder ('<div class="evidence"><button class="copy-inline" type="button" data-copy-target="{0}">Copy excerpt</button><div class="evidence-ref">{1}</div><pre id="{0}">{2}</pre></div>' -f $copyId, (ConvertTo-WudHtmlText $evidenceLabel), (ConvertTo-WudHtmlText $evidence.Excerpt))
        }
        Add-WudHtmlLine $builder '</div>'
        if (@($finding.References).Count -gt 0) {
            Add-WudHtmlLine $builder '<p><strong>Microsoft references:</strong> '
            $links = @($finding.References | ForEach-Object { '<a href="{0}">{1}</a>' -f (ConvertTo-WudHtmlText $_), (ConvertTo-WudHtmlText $_) })
            Add-WudHtmlLine $builder (($links -join ' | ') + '</p>')
        }
        Add-WudHtmlLine $builder '</div></details>'
    }
    if (@($Context.Findings).Count -eq 0) { Add-WudHtmlLine $builder '<p class="muted">No findings were emitted.</p>' }
    Add-WudHtmlLine $builder '</div>'
    Add-WudHtmlLine $builder '<div class="table-wrap"><table id="finding-table"><thead><tr><th data-sort>Severity</th><th data-sort>Category</th><th data-sort>Confidence</th><th data-sort>Status</th><th data-sort>Finding</th><th>Codes / phase</th><th>Evidence</th></tr></thead><tbody>'
    foreach ($finding in $Context.Findings) {
        $findingAnchor = 'finding-' + (([string]$finding.FindingId) -replace '[^A-Za-z0-9_.-]', '-')
        $refs = @($finding.Evidence | ForEach-Object Reference) -join '; '
        Add-WudHtmlLine $builder ('<tr data-severity="{0}" data-category="{1}" data-status="{2}"><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td><a href="#{7}">{8}</a></td><td><code>{9}</code><br>{10} {11}</td><td>{12}</td></tr>' -f (ConvertTo-WudHtmlText $finding.Severity.ToLowerInvariant()), (ConvertTo-WudHtmlText $finding.Category.ToLowerInvariant()), (ConvertTo-WudHtmlText $finding.Status.ToLowerInvariant()), (ConvertTo-WudHtmlText $finding.Severity), (ConvertTo-WudHtmlText $finding.Category), (ConvertTo-WudHtmlText $finding.Confidence), (ConvertTo-WudHtmlText $finding.Status), (ConvertTo-WudHtmlText $findingAnchor), (ConvertTo-WudHtmlText $finding.Title), (ConvertTo-WudHtmlText (@($finding.Codes) -join ' ')), (ConvertTo-WudHtmlText $finding.Phase), (ConvertTo-WudHtmlText $finding.Operation), (ConvertTo-WudHtmlText $refs))
    }
    Add-WudHtmlLine $builder '</tbody></table></div></section>'

    Add-WudHtmlLine $builder '<section class="panel"><h2>Attempt inventory</h2><div class="table-wrap"><table><thead><tr><th>Attempt</th><th>Phase hint</th><th>Last write (UTC)</th><th>Codes</th><th>Source</th></tr></thead><tbody>'
    foreach ($attempt in $Context.Attempts) {
        Add-WudHtmlLine $builder ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td><code>{3}</code></td><td>{4}</td></tr>' -f (ConvertTo-WudHtmlText $attempt.AttemptId), (ConvertTo-WudHtmlText $attempt.PhaseHint), (ConvertTo-WudHtmlText $attempt.LastWriteUtc), (ConvertTo-WudHtmlText (@($attempt.Codes) -join ', ')), (ConvertTo-WudHtmlText $attempt.Source))
    }
    Add-WudHtmlLine $builder '</tbody></table></div></section>'

    Add-WudHtmlLine $builder '<section class="panel"><h2>Correlated timeline</h2><p class="section-note">The report displays up to the latest 500 normalized events. Timeline entries are evidence, not automatically causal.</p><div class="table-wrap"><table class="timeline-table"><thead><tr><th data-sort>UTC timestamp</th><th>Attempt</th><th>Phase / operation</th><th>Code</th><th>Severity</th><th>Component</th><th>Event</th><th>Source</th></tr></thead><tbody>'
    foreach ($event in @($Context.Timeline | Select-Object -Last 500)) {
        Add-WudHtmlLine $builder ('<tr><td>{0}</td><td>{1}</td><td>{2}<br>{3}</td><td><code>{4}</code></td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td></tr>' -f (ConvertTo-WudHtmlText $event.TimestampUtc), (ConvertTo-WudHtmlText $event.AttemptId), (ConvertTo-WudHtmlText $event.Phase), (ConvertTo-WudHtmlText $event.Operation), (ConvertTo-WudHtmlText $event.Code), (ConvertTo-WudHtmlText $event.Severity), (ConvertTo-WudHtmlText $event.Component), (ConvertTo-WudHtmlText $event.Event), (ConvertTo-WudHtmlText $event.SourceRef))
    }
    Add-WudHtmlLine $builder '</tbody></table></div></section>'

    $diff = Get-WudProperty -Object $Context.Inventory -Name 'Diff'
    Add-WudHtmlLine $builder '<section class="panel"><h2>Pre/post comparison</h2>'
    if ($diff -and $diff.Available) {
        $appAdded = @($diff.Applications.Added).Count; $appRemoved = @($diff.Applications.Removed).Count; $appChanged = @($diff.Applications.Changed).Count
        $driverAdded = @($diff.Drivers.Added).Count; $driverRemoved = @($diff.Drivers.Removed).Count; $driverChanged = @($diff.Drivers.Changed).Count
        Add-WudHtmlLine $builder ('<div class="summary-grid"><div class="metric"><div class="metric-label">Applications</div><div class="metric-value">+{0} / -{1}</div><div class="metric-detail">{2} version changes</div></div><div class="metric"><div class="metric-label">Drivers</div><div class="metric-value">+{3} / -{4}</div><div class="metric-detail">{5} version changes</div></div><div class="metric"><div class="metric-label">Source build</div><div class="metric-value">{6}</div></div><div class="metric"><div class="metric-label">Current build</div><div class="metric-value">{7}</div></div></div>' -f $appAdded, $appRemoved, $appChanged, $driverAdded, $driverRemoved, $driverChanged, (ConvertTo-WudHtmlText $diff.SourceBuild), (ConvertTo-WudHtmlText $diff.CurrentBuild))
        Add-WudHtmlLine $builder '<div class="table-wrap"><table><thead><tr><th>Snapshot family</th><th>Added</th><th>Removed</th><th>Changed</th></tr></thead><tbody>'
        foreach ($groupName in @('Packages', 'Devices', 'Services', 'Policies', 'Security', 'Disks', 'Networks')) {
            $group = Get-WudProperty $diff $groupName
            Add-WudHtmlLine $builder ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>' -f $groupName, @($group.Added).Count, @($group.Removed).Count, @($group.Changed).Count)
        }
        Add-WudHtmlLine $builder '</tbody></table></div>'
    }
    else { Add-WudHtmlLine $builder '<p class="muted">No matching preflight/current snapshot pair was available. Inventory.json still contains the current snapshot.</p>' }
    Add-WudHtmlLine $builder '</section>'

    Add-WudHtmlLine $builder '<section class="panel"><h2>Collection coverage</h2><p class="section-note">A failed optional collector can reduce confidence without changing the report to incomplete; required collector failures set exit code 30.</p><div class="table-wrap"><table><thead><tr><th>Snapshot</th><th>Collector</th><th>Version</th><th>Status</th><th>Duration</th><th>Detail</th></tr></thead><tbody>'
    foreach ($record in $CollectorRecords) {
        $statusClass = 'coverage-' + $record.Status.ToLowerInvariant()
        Add-WudHtmlLine $builder ('<tr><td>{0}</td><td><strong>{1}</strong><br><span class="muted">{2}</span></td><td>{3}</td><td class="{4}">{5}</td><td>{6:N1}s</td><td>{7}</td></tr>' -f (ConvertTo-WudHtmlText $record.Snapshot), (ConvertTo-WudHtmlText $record.Id), (ConvertTo-WudHtmlText $record.Description), (ConvertTo-WudHtmlText $record.Version), $statusClass, (ConvertTo-WudHtmlText $record.Status), ([double]$record.DurationMs / 1000), (ConvertTo-WudHtmlText $record.Detail))
    }
    Add-WudHtmlLine $builder '</tbody></table></div></section>'

    Add-WudHtmlLine $builder '<section class="panel"><h2>Collection gaps</h2><p class="section-note">Missing, locked, skipped, timed-out, capacity-limited, or archive-mismatched evidence is listed explicitly.</p><div class="table-wrap"><table><thead><tr><th>Impact</th><th>Collector</th><th>Status</th><th>Source</th><th>Detail</th></tr></thead><tbody>'
    foreach ($gap in @($Summary.CollectionGaps)) {
        Add-WudHtmlLine $builder ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f (ConvertTo-WudHtmlText $gap.Impact), (ConvertTo-WudHtmlText $gap.Collector), (ConvertTo-WudHtmlText $gap.Status), (ConvertTo-WudHtmlText $gap.Source), (ConvertTo-WudHtmlText $gap.Detail))
    }
    if (@($Summary.CollectionGaps).Count -eq 0) { Add-WudHtmlLine $builder '<tr><td colspan="5">No explicit collection gaps were recorded.</td></tr>' }
    Add-WudHtmlLine $builder '</tbody></table></div></section>'

    [long]$totalBytes = 0
    foreach ($item in @($EvidenceManifest)) { if ($item) { $totalBytes += [long]$item.Length } }
    Add-WudHtmlLine $builder ('<section class="panel"><h2>Evidence index</h2><p class="section-note">{0} files &middot; {1}. Full paths and SHA-256 values are in Manifest.json; raw content is in Evidence.zip.</p><div class="table-wrap"><table><thead><tr><th>Path</th><th>Size</th><th>Modified UTC</th><th>SHA-256</th></tr></thead><tbody>' -f @($EvidenceManifest).Count, (ConvertTo-WudHtmlText (ConvertTo-WudByteSize $totalBytes)))
    foreach ($item in @($EvidenceManifest | Select-Object -First 500)) {
        Add-WudHtmlLine $builder ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td><code>{3}</code></td></tr>' -f (ConvertTo-WudHtmlText $item.RelativePath), (ConvertTo-WudHtmlText (ConvertTo-WudByteSize ([long]$item.Length))), (ConvertTo-WudHtmlText $item.LastWriteUtc), (ConvertTo-WudHtmlText $item.Sha256))
    }
    Add-WudHtmlLine $builder '</tbody></table></div></section>'
    Add-WudHtmlLine $builder ('<div class="footer">Generated by Win11UpgradeDiag {0} &middot; Run <code>{1}</code> &middot; No remediation was executed.</div>' -f (ConvertTo-WudHtmlText $Context.ToolVersion), (ConvertTo-WudHtmlText $Context.RunId))
    Add-WudHtmlLine $builder '</main>'
    $json = ($Summary | ConvertTo-Json -Depth 40 -Compress).Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026')
    Add-WudHtmlLine $builder ('<script nonce="{0}" type="application/json" id="report-data">{1}</script><script nonce="{0}">{2}</script></body></html>' -f $nonce, $json, $javascript)
    return $builder.ToString()
}

function Copy-WudOutputToShare {
    param($Context)
    if ([string]::IsNullOrWhiteSpace($Context.CopyTo)) { return [pscustomobject]@{ Requested = $false; Deferred = $false; Succeeded = $true; Destination = $null; Error = $null } }
    if (-not (Test-WudInteractiveUser)) {
        Write-WudLog -Context $Context -Level WARN -Message 'UNC copy was deferred because this phase is running without an interactive technician token.'
        return [pscustomobject]@{ Requested = $true; Deferred = $true; Succeeded = $false; Destination = $null; Error = 'No interactive technician token.' }
    }
    $destination = $null
    try {
        $destination = Join-Path $Context.CopyTo (Split-Path -Leaf $Context.OutputPath)
        $null = New-WudDirectory -Path $destination
        $arguments = @($Context.OutputPath, $destination, '/E', '/COPY:DAT', '/DCOPY:T', '/R:2', '/W:2', '/XJ', '/NP')
        $argumentLine = (@($arguments | ForEach-Object { ConvertTo-WudCommandLineArgument -Value ([string]$_) }) -join ' ')
        $process = Start-Process -FilePath 'robocopy.exe' -ArgumentList $argumentLine -PassThru
        $timeoutSeconds = [int]$Context.Settings.timeoutsSeconds.copyToShare
        $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }
        if (-not $process.HasExited) {
            try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch { }
            throw "robocopy exceeded its $timeoutSeconds second share-copy limit. A partial destination may remain and is safe to retry."
        }
        try { $process.WaitForExit() } catch { }
        if ($process.ExitCode -gt 7) { throw "robocopy returned $($process.ExitCode)." }
        Write-WudLog -Context $Context -Level INFO -Message "Copied finalized artifacts to $destination."
        return [pscustomobject]@{ Requested = $true; Deferred = $false; Succeeded = $true; Destination = $destination; Error = $null }
    }
    catch {
        Write-WudLog -Context $Context -Level WARN -Message ("Could not copy finalized artifacts to the UNC destination: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{ Requested = $true; Deferred = $false; Succeeded = $false; Destination = $destination; Error = $_.Exception.Message }
    }
}

function Copy-WudToolStateForArchive {
    param($Context)
    $stateRoot = Join-Path $Context.RunPath 'State'
    if (-not (Test-Path -LiteralPath $stateRoot)) { return }
    $destinationRoot = New-WudDirectory -Path (Join-Path $Context.SnapshotPath 'ToolState')
    foreach ($file in @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'run.lock')) {
        try {
            $relative = Get-WudRelativePath -BasePath $stateRoot -Path $file.FullName
            $destination = Join-Path $destinationRoot $relative
            $null = New-WudDirectory -Path (Split-Path -Parent $destination)
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
        }
        catch {
            $null = Add-WudCollectionGap -Context $Context -Collector 'report-state' -Source $file.FullName -Status 'CopyFailed' -Detail $_.Exception.Message
        }
    }
}

function Export-WudReportArtifacts {
    param([Parameter(Mandatory = $true)]$Context)
    Write-WudLog -Context $Context -Level INFO -Message "Finalizing report artifacts in $($Context.OutputPath)."
    $null = New-WudDirectory -Path $Context.OutputPath
    Copy-WudToolStateForArchive -Context $Context
    $collectorRecords = Get-WudAllCollectorRecords -Context $Context
    $evidenceManifest = @(Get-WudFileInventory -RootPath $Context.EvidencePath)
    foreach ($unhashed in @($evidenceManifest | Where-Object { -not $_.Sha256 })) {
        $null = Add-WudCollectionGap -Context $Context -Collector 'report-manifest' -Source $unhashed.StagedPath -Status 'HashUnavailable' -Detail 'The staged evidence file was indexed, but SHA-256 calculation did not complete.'
    }
    $evidenceZip = Join-Path $Context.OutputPath 'Evidence.zip'
    New-WudEvidenceArchive -SourcePath $Context.EvidencePath -DestinationPath $evidenceZip -Context $Context
    $archiveVerification = Test-WudEvidenceArchiveIntegrity -ArchivePath $evidenceZip -EvidenceManifest $evidenceManifest
    if (-not $archiveVerification.Verified) {
        $Context.CollectionComplete = $false
        $Context.ExitCode = Resolve-WudExitCode -Context $Context
        $null = Add-WudCollectionGap -Context $Context -Collector 'report-archive' -Source $evidenceZip -Status 'IntegrityMismatch' -Detail ((@($archiveVerification.Missing) + @($archiveVerification.HashMismatches)) -join '; ') -Impact 'Material'
    }
    Write-WudJsonAtomic -Path (Join-Path $Context.OutputPath 'Inventory.json') -InputObject $Context.Inventory -Depth 40
    $findingRows = foreach ($finding in $Context.Findings) {
        [pscustomobject][ordered]@{
            FindingId      = $finding.FindingId
            RuleId         = $finding.RuleId
            Severity       = $finding.Severity
            Category       = $finding.Category
            Confidence     = $finding.Confidence
            Status         = $finding.Status
            DispositionReason = ConvertTo-WudCsvCell $finding.DispositionReason
            Title          = ConvertTo-WudCsvCell $finding.Title
            ResultCode     = $finding.ResultCode
            ExtendCode     = $finding.ExtendCode
            Codes          = ConvertTo-WudCsvCell (@($finding.Codes) -join '; ')
            Phase          = $finding.Phase
            Operation      = $finding.Operation
            AffectedEntity = ConvertTo-WudCsvCell $finding.AffectedEntity
            Evidence       = ConvertTo-WudCsvCell (@($finding.Evidence | ForEach-Object Reference) -join '; ')
            Recommendation = ConvertTo-WudCsvCell $finding.Recommendation
            References     = ConvertTo-WudCsvCell (@($finding.References) -join '; ')
        }
    }
    $findingHeaders = @('FindingId', 'RuleId', 'Severity', 'Category', 'Confidence', 'Status', 'DispositionReason', 'Title', 'ResultCode', 'ExtendCode', 'Codes', 'Phase', 'Operation', 'AffectedEntity', 'Evidence', 'Recommendation', 'References')
    Export-WudCsvContract -Rows @($findingRows) -Headers $findingHeaders -Path (Join-Path $Context.OutputPath 'Findings.csv')
    $timelineHeaders = @('TimestampUtc', 'LocalOffset', 'TimestampAmbiguous', 'AttemptId', 'Phase', 'Operation', 'Code', 'Component', 'Event', 'Message', 'Severity', 'SourceRef', 'EvidenceReference', 'Entity', 'CorrelationId')
    $timelineRows = @($Context.Timeline | ForEach-Object {
        $sourceEvent = $_
        $row = [ordered]@{}
        foreach ($header in $timelineHeaders) { $row[$header] = ConvertTo-WudCsvCell (Get-WudProperty -Object $sourceEvent -Name $header) }
        [pscustomobject]$row
    })
    Export-WudCsvContract -Rows $timelineRows -Headers $timelineHeaders -Path (Join-Path $Context.OutputPath 'Timeline.csv')
    if (Test-Path -LiteralPath $Context.LogPath) { Copy-Item -LiteralPath $Context.LogPath -Destination (Join-Path $Context.OutputPath 'Collector.log') -Force }
    $preSummaryArtifacts = @('Evidence.zip', 'Inventory.json', 'Findings.csv', 'Timeline.csv', 'Collector.log') | ForEach-Object { Get-WudArtifactRecord -Path (Join-Path $Context.OutputPath $_) -BasePath $Context.OutputPath } | Where-Object { $_ }
    $summary = New-WudSummaryObject -Context $Context -CollectorRecords $collectorRecords -ArtifactRecords $preSummaryArtifacts
    Write-WudJsonAtomic -Path (Join-Path $Context.OutputPath 'Summary.json') -InputObject $summary -Depth 40
    $html = Build-WudReportHtml -Context $Context -Summary $summary -EvidenceManifest $evidenceManifest -CollectorRecords $collectorRecords
    Write-WudText -Path (Join-Path $Context.OutputPath 'Report.html') -Text $html
    $artifactFiles = @('Report.html', 'Summary.json', 'Findings.csv', 'Timeline.csv', 'Inventory.json', 'Evidence.zip', 'Collector.log')
    $artifactManifest = @($artifactFiles | ForEach-Object { Get-WudArtifactRecord -Path (Join-Path $Context.OutputPath $_) -BasePath $Context.OutputPath } | Where-Object { $_ })
    $sourceMappings = Get-WudEvidenceSourceMappings -Context $Context
    $manifest = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ToolVersion   = $Context.ToolVersion
        RunId         = $Context.RunId
        Sensitive     = $true
        CreatedUtc    = [DateTime]::UtcNow.ToString('o')
        Artifacts     = $artifactManifest
        Evidence     = $evidenceManifest
        SourceMappings = $sourceMappings
        CollectionGaps = @($Context.CollectionGaps)
        ArchiveVerification = $archiveVerification
    }
    Write-WudJsonAtomic -Path (Join-Path $Context.OutputPath 'Manifest.json') -InputObject $manifest -Depth 20
    $checksumLines = New-Object Collections.ArrayList
    foreach ($file in Get-ChildItem -LiteralPath $Context.OutputPath -File | Where-Object Name -ne 'Checksums.sha256' | Sort-Object Name) {
        $hash = Get-WudFileHashSafe -Path $file.FullName
        if ($hash) { $null = $checksumLines.Add("$hash  $($file.Name)") }
    }
    Write-WudText -Path (Join-Path $Context.OutputPath 'Checksums.sha256') -Text ((@($checksumLines) -join [Environment]::NewLine) + [Environment]::NewLine)
    $Context.LastCopyResult = Copy-WudOutputToShare -Context $Context
    return (Join-Path $Context.OutputPath 'Report.html')
}

Export-ModuleMember -Function @('Export-WudReportArtifacts', 'New-WudEvidenceArchive', 'Build-WudReportHtml', 'ConvertTo-WudHtmlText', 'Copy-WudOutputToShare')
