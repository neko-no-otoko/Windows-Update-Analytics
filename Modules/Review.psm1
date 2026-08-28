Set-StrictMode -Version 2.0

function ConvertTo-WudReviewUtc {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime.ToString('o') }
        if ($Value -is [DateTime]) { return $Value.ToUniversalTime().ToString('o') }
        return ([DateTimeOffset]::Parse([string]$Value)).UtcDateTime.ToString('o')
    }
    catch { return $null }
}

function Get-WudReviewProperty {
    param($Object, [string]$Name, $Default = $null)
    return Get-WudObjectPropertyValue -InputObject $Object -Name $Name -Default $Default
}

function Add-WudReviewFact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [ValidateSet('Observed', 'Decoded', 'SourceReported', 'Computed')][string]$FactType,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Statement,
        $Value,
        [string]$TimestampUtc,
        [string]$AttemptId,
        [string]$SourceRef,
        [string]$EvidenceRef,
        [string]$Code,
        [string]$Phase,
        [string]$Operation,
        [ValidateSet('Included', 'ContextOnly', 'Excluded')][string]$ScopeStatus = 'Included',
        [string]$Excerpt
    )
    $fact = [pscustomobject][ordered]@{
        FactId        = 'FACT-{0:D6}' -f (@($Context.Facts).Count + 1)
        FactType      = $FactType
        Category      = $Category
        Statement     = $Statement
        Value         = $Value
        TimestampUtc  = $TimestampUtc
        AttemptId     = $AttemptId
        SourceRef     = $SourceRef
        EvidenceRef   = if ($EvidenceRef) { $EvidenceRef } else { $SourceRef }
        Code          = $Code
        Phase         = $Phase
        Operation     = $Operation
        ScopeStatus   = $ScopeStatus
        Excerpt       = $Excerpt
        ExcerptFile   = $null
    }
    $null = $Context.Facts.Add($fact)
    return $fact
}

function Get-WudSetupLogProfile {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][int]$Sequence
    )
    $relative = (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $File.FullName).Replace('\', '/')
    $hash = Get-WudFileHashSafe -Path $File.FullName
    $started = $null
    $ended = $null
    $sourceBuild = $null
    $targetBuild = $null
    $codes = New-Object Collections.ArrayList
    $errorRecords = New-Object Collections.ArrayList
    $signals = New-Object Collections.ArrayList
    $lineNumber = 0
    $charactersRead = 0L
    $truncated = $false
    $maximumBytes = [Math]::Min([long]$Context.Settings.maximumTextParseBytes, 67108864L)
    $reader = $null
    try {
        $reader = New-Object IO.StreamReader($File.FullName, $true)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            $lineNumber++
            $charactersRead += ([long]$line.Length + 2L)
            if ($charactersRead -gt $maximumBytes) { $truncated = $true; break }
            $timestamp = $null
            if ($line -match '^(?<date>\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)') {
                $timestampInfo = ConvertTo-WudLogTimestamp -Text $matches.date
                if ($timestampInfo) {
                    $timestamp = [string]$timestampInfo.TimestampUtc
                    if (-not $started) { $started = $timestamp }
                    $ended = $timestamp
                }
            }
            if (-not $sourceBuild -and $line -match '(?i)(?:source(?:\s+os)?\s+build|host\s+build)\D{0,24}(\d{5})') { $sourceBuild = $matches[1] }
            if (-not $targetBuild -and $line -match '(?i)(?:target(?:\s+os)?\s+build|image\s+build)\D{0,24}(\d{5})') { $targetBuild = $matches[1] }

            if ($line -match '(?i)/Compat\s+ScanOnly|CompatScanOnly|MOSETUP_E_COMPAT_SCANONLY|0xC1900210') {
                if (-not $signals.Contains('DiagnosticCompatibilityScan')) { $null = $signals.Add('DiagnosticCompatibilityScan') }
            }
            if ($line -match '(?i)\b(?:MOUPG|CSetupHost|SetupHost|Modern Setup Host|SP_EXECUTION_|source\s+(?:os\s+)?build|target\s+(?:os\s+)?build|upgrade platform)\b') {
                if (-not $signals.Contains('FeatureUpgradeSemantics')) { $null = $signals.Add('FeatureUpgradeSemantics') }
            }
            if ($line -match '(?i)\b(?:Windows Update|UpdateSessionOrchestration|Update Orchestrator|UsoClient|UsoSvc|WUClient|WaaS|BlueBox)\b') {
                if (-not $signals.Contains('WindowsUpdateOwnerInSetupLog')) { $null = $signals.Add('WindowsUpdateOwnerInSetupLog') }
            }
            if ($line -match '(?i)\b(?:ConfigMgr|CCMExec|OSDUpgrade|Task Sequence|setup\.exe\s+/auto|install(?:ation)?\s+media)\b') {
                if (-not $signals.Contains('NonWindowsUpdateOwnerInSetupLog')) { $null = $signals.Add('NonWindowsUpdateOwnerInSetupLog') }
            }
            if ($line -match '(?i)\b(?:windeploy|auditSystem|specialize|IMAGE_STATE_|Applying (?:Windows )?image|Deployment Image Servicing and Management|unattend\.xml)\b') {
                if (-not $signals.Contains('DeploymentOrImagingSemantics')) { $null = $signals.Add('DeploymentOrImagingSemantics') }
            }

            foreach ($match in [Regex]::Matches($line, '(?i)0x(?:[0-9A-F]{8}|[0-5][0-9A-F]{4})(?![0-9A-F])')) {
                $code = '0x' + $match.Value.Substring(2).ToUpperInvariant()
                if (-not $codes.Contains($code)) { $null = $codes.Add($code) }
            }
            if (@($errorRecords).Count -lt 200 -and $line -match '(?i)\b(?:error|fatal|rollback|hardblock|failed|failure|abort(?:ed)?)\b|0x(?:[0-9A-F]{8}|[0-5][0-9A-F]{4})') {
                $excerpt = $line.Trim()
                if ($excerpt.Length -gt 1000) { $excerpt = $excerpt.Substring(0, 1000) + '...' }
                $lineCodes = Get-WudCodesFromText -Text $line
                $decoded = if ($lineCodes.ExtendCode) { Get-WudPhaseOperation -ExtendCode $lineCodes.ExtendCode } else { $null }
                $null = $errorRecords.Add([pscustomobject][ordered]@{
                    LineNumber   = $lineNumber
                    TimestampUtc = $timestamp
                    Reference    = "${relative}:$lineNumber"
                    Excerpt      = $excerpt
                    Codes        = @($lineCodes.Codes)
                    ResultCode   = $lineCodes.ResultCode
                    ExtendCode   = $lineCodes.ExtendCode
                    Phase        = if ($decoded) { $decoded.Phase } else { $null }
                    Operation    = if ($decoded) { $decoded.Operation } else { $null }
                })
            }
        }
    }
    catch {
        $null = Add-WudCollectionGap -Context $Context -Collector 'fact-scope' -Source $File.FullName -Status 'ParseFailed' -Detail (Get-WudErrorDetail $_)
    }
    finally { if ($reader) { $reader.Dispose() } }

    if (-not $started) { $started = $File.LastWriteTimeUtc.ToString('o') }
    if (-not $ended) { $ended = $File.LastWriteTimeUtc.ToString('o') }
    $idSeed = if ($hash) { $hash.Substring(0, 12) } else { '{0:D4}' -f $Sequence }
    return [pscustomobject][ordered]@{
        AttemptId       = "attempt-$idSeed"
        SourcePath      = $relative
        SourceDirectory = (Split-Path -Parent $relative).Replace('\', '/')
        Sha256          = $hash
        Length          = $File.Length
        LastWriteUtc    = $File.LastWriteTimeUtc.ToString('o')
        StartedUtc      = $started
        EndedUtc        = $ended
        SourceBuild     = $sourceBuild
        TargetBuild     = $targetBuild
        Codes           = @($codes)
        ContentSignals  = @($signals)
        ErrorRecords    = @($errorRecords)
        ParseTruncated  = $truncated
        DuplicateOf     = $null
        Classification  = $null
        IncludedForUpgradeReview = $false
        ExclusionReason = $null
        Gates           = $null
        CorroboratingEvidence = @()
    }
}

function Get-WudFeatureUpdateHistory {
    param($Context, $CurrentInventory)
    $records = New-Object Collections.ArrayList
    $servicing = Get-WudReviewProperty $CurrentInventory 'Servicing'
    $history = @(Get-WudReviewProperty $servicing 'UpdateHistory' @())
    $targetPattern = [Regex]::Escape([string]$Context.TargetVersion)
    for ($index = 0; $index -lt $history.Count; $index++) {
        $entry = $history[$index]
        $title = [string](Get-WudReviewProperty $entry 'Title')
        if ($title -notmatch "(?i)(?:Feature update to Windows 11|Windows 11,?\s+version)" -and $title -notmatch "(?i)Windows 11.*$targetPattern") { continue }
        $null = $records.Add([pscustomobject][ordered]@{
            Index               = $index
            DateUtc             = ConvertTo-WudReviewUtc (Get-WudReviewProperty $entry 'Date')
            Title               = $title
            Operation           = [string](Get-WudReviewProperty $entry 'Operation')
            ResultCode          = [string](Get-WudReviewProperty $entry 'ResultCode')
            HResult             = Get-WudReviewProperty $entry 'HResult'
            HResultHex          = Get-WudReviewProperty $entry 'HResultHex'
            ClientApplicationID = Get-WudReviewProperty $entry 'ClientApplicationID'
            ServerSelection     = Get-WudReviewProperty $entry 'ServerSelection'
            ServiceID           = Get-WudReviewProperty $entry 'ServiceID'
            UpdateID            = Get-WudReviewProperty $entry 'UpdateID'
            RevisionNumber      = Get-WudReviewProperty $entry 'RevisionNumber'
            SourceRef           = ('{0}/Servicing/servicing.json#UpdateHistory[{1}]' -f $Context.PhaseLabel, $index)
            Raw                 = $entry
        })
    }
    return @($records)
}

function Test-WudReviewTimeOverlap {
    param([string]$AttemptStart, [string]$AttemptEnd, [string]$EvidenceTime, [int]$PaddingHours = 36)
    if (-not $EvidenceTime) { return $false }
    try {
        $start = [DateTimeOffset]::Parse($AttemptStart).UtcDateTime.AddHours(-1 * $PaddingHours)
        $end = [DateTimeOffset]::Parse($AttemptEnd).UtcDateTime.AddHours($PaddingHours)
        $point = [DateTimeOffset]::Parse($EvidenceTime).UtcDateTime
        return $point -ge $start -and $point -le $end
    }
    catch { return $false }
}

function Find-WudUpdateLogSignals {
    param($Context, $Attempt)
    $signals = New-Object Collections.ArrayList
    $targetText = [Regex]::Escape([string]$Context.TargetVersion)
    $targetBuild = [Regex]::Escape([string]$Context.Target.buildFamily)
    $files = @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)BlueBox.*\.log$|WindowsUpdate\.log$' -or $_.FullName -match '(?i)Windows-MoSetup'
    } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 40)
    foreach ($file in $files) {
        if (-not (Test-WudReviewTimeOverlap $Attempt.StartedUtc $Attempt.EndedUtc $file.LastWriteTimeUtc.ToString('o') 48)) { continue }
        $relative = (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName).Replace('\', '/')
        $reader = $null
        try {
            $reader = New-Object IO.StreamReader($file.FullName, $true)
            $lineNumber = 0
            while (-not $reader.EndOfStream -and @($signals).Count -lt 20) {
                $line = $reader.ReadLine(); $lineNumber++
                if ($line -notmatch "(?i)(?:Feature update to Windows 11|Windows 11,?\s+version|$targetText|$targetBuild)") { continue }
                $timestamp = $null
                if ($line -match '^(?<date>\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)') {
                    $timestamp = ConvertTo-WudReviewUtc $matches.date
                    if ($timestamp -and -not (Test-WudReviewTimeOverlap $Attempt.StartedUtc $Attempt.EndedUtc $timestamp 36)) { continue }
                }
                $excerpt = $line.Trim(); if ($excerpt.Length -gt 600) { $excerpt = $excerpt.Substring(0, 600) + '...' }
                $null = $signals.Add([pscustomobject][ordered]@{
                    Kind = if ($file.Name -match '(?i)BlueBox') { 'BlueBoxTargetSignal' } else { 'WindowsUpdateTargetSignal' }
                    TimestampUtc = $timestamp
                    Reference = "${relative}:$lineNumber"
                    Excerpt = $excerpt
                })
            }
        }
        catch { }
        finally { if ($reader) { $reader.Dispose() } }
    }
    return @($signals)
}

function Test-WudImageStateComplete {
    param($Identity)
    $imageState = [string](Get-WudReviewProperty $Identity 'WindowsImageState')
    if ($imageState -match '(?i)^IMAGE_STATE_COMPLETE$') { return $true }
    $setup = Get-WudReviewProperty $Identity 'SystemSetupState'
    if ($setup) {
        $systemSetup = Get-WudReviewProperty $setup 'SystemSetupInProgress'
        $oobe = Get-WudReviewProperty $setup 'OOBEInProgress'
        if ($null -ne $systemSetup -and $null -ne $oobe -and [int]$systemSetup -eq 0 -and [int]$oobe -eq 0) { return $true }
    }
    return $false
}

function Set-WudAttemptScope {
    param($Context, $Attempt, $FeatureHistory, $Identity)
    $historyMatches = New-Object Collections.ArrayList
    foreach ($entry in @($FeatureHistory)) {
        if (Test-WudReviewTimeOverlap $Attempt.StartedUtc $Attempt.EndedUtc $entry.DateUtc 72) { $null = $historyMatches.Add($entry) }
    }
    $logSignals = @(Find-WudUpdateLogSignals -Context $Context -Attempt $Attempt)
    $sameLogOwner = @($Attempt.ContentSignals) -contains 'WindowsUpdateOwnerInSetupLog'
    $featureSemantics = (@($Attempt.ContentSignals) -contains 'FeatureUpgradeSemantics') -or
        (($Attempt.SourcePath -match '(?i)WindowsBT|WindowsOld|SetupCopyLogs') -and ($Attempt.SourceBuild -or $Attempt.TargetBuild))
    $diagnosticScan = @($Attempt.ContentSignals) -contains 'DiagnosticCompatibilityScan'
    $toolGenerated = $Attempt.SourcePath -match '(?i)/(?:Commands|CurrentDiagnostics|Compatibility/MediaScan|SetupDiag)/'
    $imagingPath = $Attempt.SourcePath -match '(?i)/Raw/Windows-Panther/' -and $Attempt.SourcePath -notmatch '(?i)WindowsOld'
    $imagingSemantics = @($Attempt.ContentSignals) -contains 'DeploymentOrImagingSemantics'
    $nonWuOwner = @($Attempt.ContentSignals) -contains 'NonWindowsUpdateOwnerInSetupLog'
    $wuOwnership = $sameLogOwner -or @($historyMatches).Count -gt 0 -or @($logSignals).Count -gt 0
    $temporalOverlap = $sameLogOwner -or @($historyMatches).Count -gt 0 -or @($logSignals).Count -gt 0
    $targetEvidence = ([string]$Attempt.TargetBuild -eq [string]$Context.Target.buildFamily) -or
        (@($historyMatches | Where-Object { $_.Title -match [Regex]::Escape([string]$Context.TargetVersion) }).Count -gt 0) -or
        (@($logSignals).Count -gt 0)
    $imageComplete = Test-WudImageStateComplete -Identity $Identity
    $included = (-not $diagnosticScan) -and (-not $toolGenerated) -and (-not $imagingPath) -and (-not $imagingSemantics) -and $featureSemantics -and $wuOwnership -and $temporalOverlap -and $targetEvidence -and $imageComplete

    $classification = 'UnclassifiedSetupEvidence'
    $reason = $null
    if ($diagnosticScan) { $classification = 'DiagnosticCompatibilityScan'; $reason = 'Setup explicitly reported scan-only compatibility execution.' }
    elseif ($toolGenerated) { $classification = 'ToolGenerated'; $reason = 'The evidence path is owned by this diagnostic run.' }
    elseif ($imagingPath -and ($imagingSemantics -or -not $wuOwnership)) { $classification = 'InitialDeploymentOrImaging'; $reason = 'The log is in Windows\\Panther and lacks the complete Windows Update feature-upgrade gate set.' }
    elseif ($imagingPath -or $imagingSemantics) { $classification = 'InitialDeploymentOrImaging'; $reason = 'The source path or log content directly identifies deployment/imaging context, which is excluded even when Windows Update text is also present.' }
    elseif ($included) { $classification = 'WindowsUpdateFeatureUpgrade' }
    elseif ($featureSemantics -and $nonWuOwner) { $classification = 'NonWindowsUpdateFeatureUpgrade'; $reason = 'The setup log directly names a non-Windows-Update deployment owner.' }
    elseif ($Attempt.SourcePath -match '(?i)/Raw/(?:Windows-CBS|Windows-DISM)/') { $classification = 'GeneralWindowsServicing'; $reason = 'The source is general servicing evidence, not a feature-upgrade setup source.' }
    else {
        $missing = New-Object Collections.ArrayList
        if (-not $featureSemantics) { $null = $missing.Add('feature-upgrade semantics') }
        if (-not $wuOwnership) { $null = $missing.Add('Windows Update ownership') }
        if (-not $temporalOverlap) { $null = $missing.Add('temporal overlap') }
        if (-not $targetEvidence) { $null = $missing.Add('target version/build evidence') }
        if (-not $imageComplete) { $null = $missing.Add('completed Windows image state') }
        $reason = 'Excluded because the following required gate(s) were absent: ' + (@($missing) -join ', ') + '.'
    }

    $corroboration = New-Object Collections.ArrayList
    foreach ($entry in @($historyMatches)) {
        $null = $corroboration.Add([pscustomobject]@{ Kind = 'WindowsUpdateHistory'; Reference = $entry.SourceRef; TimestampUtc = $entry.DateUtc; Value = $entry.Title; UpdateID = $entry.UpdateID })
    }
    foreach ($signal in @($logSignals)) { $null = $corroboration.Add($signal) }
    if ($sameLogOwner) { $null = $corroboration.Add([pscustomobject]@{ Kind = 'WindowsUpdateOwnerInSetupLog'; Reference = $Attempt.SourcePath; TimestampUtc = $null; Value = 'Windows Update ownership token present in setupact.' }) }

    $Attempt.Classification = $classification
    $Attempt.IncludedForUpgradeReview = $included
    $Attempt.ExclusionReason = $reason
    $Attempt.Gates = [pscustomobject][ordered]@{
        UniqueEvidence             = $true
        NotDiagnosticScan          = -not $diagnosticScan
        NotToolGenerated           = -not $toolGenerated
        NotInitialDeploymentOrImaging = (-not $imagingPath) -and (-not $imagingSemantics)
        FeatureUpgradeSemantics    = $featureSemantics
        WindowsUpdateOwnership     = $wuOwnership
        TemporalOverlap            = $temporalOverlap
        TargetVersionOrBuild       = $targetEvidence
        CompletedWindowsImageState = $imageComplete
    }
    $Attempt.CorroboratingEvidence = @($corroboration)
    return $Attempt
}

function Get-WudReviewInventoryDiff {
    param($Context, $CurrentInventory)
    $snapshots = @(Get-ChildItem -LiteralPath $Context.EvidencePath -Directory -ErrorAction SilentlyContinue)
    $baselineFile = @($snapshots | Where-Object { $_.Name -eq 'Preflight' } | ForEach-Object { Join-Path $_.FullName 'inventory.json' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    $baseline = if (@($baselineFile).Count -gt 0) { Read-WudJson -Path $baselineFile[0] } else { $null }
    $changed = New-Object Collections.ArrayList
    foreach ($section in @('Identity', 'Hardware', 'Drivers', 'Management', 'Servicing')) {
        $beforeValue = Get-WudReviewProperty $baseline $section
        $afterValue = Get-WudReviewProperty $CurrentInventory $section
        if ($null -eq $beforeValue -and $null -eq $afterValue) { continue }
        $beforeJson = if ($null -ne $beforeValue) { $beforeValue | ConvertTo-Json -Compress -Depth 30 } else { $null }
        $afterJson = if ($null -ne $afterValue) { $afterValue | ConvertTo-Json -Compress -Depth 30 } else { $null }
        if ($beforeJson -ne $afterJson) { $null = $changed.Add($section) }
    }
    $baselineIdentity = Get-WudReviewProperty $baseline 'Identity'
    $currentIdentity = Get-WudReviewProperty $CurrentInventory 'Identity'
    return [pscustomobject][ordered]@{
        Available        = $null -ne $baseline
        ChangedSections  = @($changed)
        BaselineSnapshot = if (@($baselineFile).Count -gt 0) { (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $baselineFile[0]).Replace('\', '/') } else { $null }
        SourceVersion    = Get-WudReviewProperty $baselineIdentity 'DisplayVersion'
        SourceBuild      = Get-WudReviewProperty $baselineIdentity 'CurrentBuild'
        CurrentVersion   = Get-WudReviewProperty $currentIdentity 'DisplayVersion'
        CurrentBuild     = Get-WudReviewProperty $currentIdentity 'CurrentBuild'
    }, $baseline
}

function Get-WudOperationResultLabel {
    param([string]$ResultCode)
    switch -Regex ($ResultCode) {
        '^(?:2|orcSucceeded)$' { return 'Succeeded' }
        '^(?:3|orcSucceededWithErrors)$' { return 'SucceededWithErrors' }
        '^(?:4|orcFailed)$' { return 'Failed' }
        '^(?:5|orcAborted)$' { return 'Aborted' }
        '^(?:1|orcInProgress)$' { return 'InProgress' }
        '^(?:0|orcNotStarted)$' { return 'NotStarted' }
        default { return $ResultCode }
    }
}

function Add-WudSetupDiagFacts {
    param($Context, $Attempts)
    foreach ($metadataFile in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter 'setupdiag-tool.json' -ErrorAction SilentlyContinue)) {
        $metadata = Read-WudJson -Path $metadataFile.FullName
        $inputRef = [string](Get-WudReviewProperty $metadata 'InputEvidenceRef')
        if (-not $inputRef) { continue }
        $attempt = @($Attempts | Where-Object { $_.IncludedForUpgradeReview -and $_.SourcePath -eq $inputRef } | Select-Object -First 1)
        if (@($attempt).Count -eq 0) { continue }
        $resultPath = Join-Path $metadataFile.DirectoryName 'SetupDiagResults.json'
        if (-not (Test-Path -LiteralPath $resultPath)) { continue }
        $result = Read-WudJson -Path $resultPath
        if (-not $result) { continue }
        $relative = (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $resultPath).Replace('\', '/')
        foreach ($name in @('ProfileName', 'RuleName', 'RuleId', 'ErrorCode', 'LastPhase', 'LastOperation', 'FailureData', 'FailureDetails', 'MatchingProfile', 'Message', 'Remediation', 'Result', 'SystemInfo')) {
            $value = Get-WudReviewProperty $result $name
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { continue }
            $text = if ($value -is [string]) { [string]$value } else { $value | ConvertTo-Json -Compress -Depth 10 }
            if ($text.Length -gt 2000) { $text = $text.Substring(0, 2000) + '...' }
            $null = Add-WudReviewFact -Context $Context -FactType SourceReported -Category 'SetupDiag' -Statement ("SetupDiag reported {0}." -f $name) -Value $text -AttemptId $attempt[0].AttemptId -SourceRef ("{0}#{1}" -f $relative, $name) -Excerpt $text
        }
    }
}

function Add-WudInventoryFacts {
    param($Context, $CurrentInventory)
    $servicing = Get-WudReviewProperty $CurrentInventory 'Servicing'
    $pending = Get-WudReviewProperty $servicing 'PendingReboot'
    if ($pending -and [bool](Get-WudReviewProperty $pending 'IsPending' $false)) {
        $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'ServicingState' -Statement 'At least one collected pending-restart indicator is set.' -Value $pending -SourceRef ("{0}/Servicing/servicing.json#PendingReboot" -f $Context.PhaseLabel) -ScopeStatus ContextOnly
    }

    $hardware = Get-WudReviewProperty $CurrentInventory 'Hardware'
    if ($hardware) {
        $logicalDisks = @(Get-WudReviewProperty $hardware 'LogicalDisks' @())
        foreach ($disk in @($logicalDisks | Where-Object { [string](Get-WudReviewProperty $_ 'DeviceID') -eq [string]$env:SystemDrive } | Select-Object -First 1)) {
            $value = [pscustomobject][ordered]@{
                DeviceID = Get-WudReviewProperty $disk 'DeviceID'; Size = Get-WudReviewProperty $disk 'Size'
                FreeSpace = Get-WudReviewProperty $disk 'FreeSpace'; FileSystem = Get-WudReviewProperty $disk 'FileSystem'
                Status = Get-WudReviewProperty $disk 'Status'
            }
            $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'StorageState' -Statement 'The collector read the operating-system volume capacity and free space.' -Value $value -SourceRef ("{0}/Inventory/hardware.json#LogicalDisks" -f $Context.PhaseLabel) -ScopeStatus ContextOnly
        }
        foreach ($disk in @(Get-WudReviewProperty $hardware 'PhysicalDisks' @())) {
            $health = [string](Get-WudReviewProperty $disk 'HealthStatus')
            if (-not $health -or $health -eq 'Healthy') { continue }
            $null = Add-WudReviewFact -Context $Context -FactType SourceReported -Category 'StorageState' -Statement ("Windows storage health reported physical disk state '{0}'." -f $health) -Value $disk -SourceRef ("{0}/Inventory/hardware.json#PhysicalDisks" -f $Context.PhaseLabel) -ScopeStatus ContextOnly
        }
        $secureBoot = Get-WudReviewProperty $hardware 'SecureBoot'
        if ($null -ne $secureBoot) {
            $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'SecurityState' -Statement 'The collector read the Secure Boot state.' -Value $secureBoot -SourceRef ("{0}/Inventory/hardware.json#SecureBoot" -f $Context.PhaseLabel) -ScopeStatus ContextOnly
        }
        $tpm = Get-WudReviewProperty $hardware 'Tpm'
        if ($tpm) {
            $null = Add-WudReviewFact -Context $Context -FactType SourceReported -Category 'SecurityState' -Statement 'The Windows TPM provider returned its current state.' -Value $tpm -SourceRef ("{0}/Inventory/hardware.json#Tpm" -f $Context.PhaseLabel) -ScopeStatus ContextOnly
        }
    }

    $drivers = Get-WudReviewProperty $CurrentInventory 'Drivers'
    foreach ($device in @(Get-WudReviewProperty $drivers 'Devices' @())) {
        $problemCode = Get-WudReviewProperty $device 'ConfigManagerErrorCode'
        $number = 0
        if ($null -eq $problemCode -or -not [int]::TryParse([string]$problemCode, [ref]$number) -or $number -eq 0) { continue }
        $name = [string](Get-WudReviewProperty $device 'Name' '<unnamed-device>')
        $null = Add-WudReviewFact -Context $Context -FactType SourceReported -Category 'DeviceState' -Statement ("PnP reported ConfigManager error code {0} for device '{1}'." -f $number, $name) -Value $device -SourceRef ("{0}/Inventory/drivers.json#Devices" -f $Context.PhaseLabel) -Code ([string]$number) -ScopeStatus ContextOnly
    }

    $management = Get-WudReviewProperty $CurrentInventory 'Management'
    foreach ($test in @(Get-WudReviewProperty $management 'Connectivity' @())) {
        if ([bool](Get-WudReviewProperty $test 'Reachable' $false)) { continue }
        $uri = [string](Get-WudReviewProperty $test 'Uri')
        $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'Connectivity' -Statement ("The bounded endpoint test did not reach '{0}'." -f $uri) -Value $test -SourceRef ("{0}/Management/management-summary.json#Connectivity" -f $Context.PhaseLabel) -ScopeStatus ContextOnly
    }
    $registryExports = Get-WudReviewProperty $management 'RegistryExports'
    if ($registryExports) {
        $importantNames = @('TargetReleaseVersion', 'TargetReleaseVersionInfo', 'ProductVersion', 'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PausedFeatureStatus', 'WUServer', 'WUStatusServer', 'UseWUServer', 'DisableWUfBSafeguards')
        foreach ($export in $registryExports.PSObject.Properties) {
            foreach ($record in @($export.Value)) {
                $values = Get-WudReviewProperty $record 'Values'
                if (-not $values) { continue }
                $valueEntries = New-Object Collections.ArrayList
                if ($values -is [Collections.IDictionary]) {
                    foreach ($valueName in $values.Keys) { $null = $valueEntries.Add([pscustomobject]@{ Name = [string]$valueName; Value = $values[$valueName] }) }
                }
                else {
                    foreach ($valueProperty in $values.PSObject.Properties) { $null = $valueEntries.Add([pscustomobject]@{ Name = $valueProperty.Name; Value = $valueProperty.Value }) }
                }
                foreach ($valueProperty in @($valueEntries)) {
                    if ($importantNames -notcontains [string]$valueProperty.Name) { continue }
                    $recordPath = [string](Get-WudReviewProperty $record 'Path')
                    $value = [pscustomobject][ordered]@{ RegistryPath = $recordPath; Name = $valueProperty.Name; Value = $valueProperty.Value }
                    $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'UpdatePolicy' -Statement ("Update-related registry value '{0}' was present." -f $valueProperty.Name) -Value $value -SourceRef ("{0}/Management/{1}#{2}/{3}" -f $Context.PhaseLabel, $export.Name, $recordPath, $valueProperty.Name) -ScopeStatus ContextOnly
                }
            }
        }
    }

    $software = Get-WudReviewProperty $CurrentInventory 'Software'
    $softwareCollection = [string](Get-WudReviewProperty $software 'CollectionStatus' 'Collected')
    $inventoryCounts = [pscustomobject][ordered]@{
        SoftwareCollection = $softwareCollection
        Applications = if ($softwareCollection -eq 'DisabledByDesign') { $null } else { @(Get-WudReviewProperty $software 'Applications' @()).Count }
        Services = if ($softwareCollection -eq 'DisabledByDesign') { $null } else { @(Get-WudReviewProperty $software 'Services' @()).Count }
        SignedDrivers = @(Get-WudReviewProperty $drivers 'SignedDrivers' @()).Count
        Devices = @(Get-WudReviewProperty $drivers 'Devices' @()).Count
        Packages = @(Get-WudReviewProperty $servicing 'Packages' @()).Count
    }
    $null = Add-WudReviewFact -Context $Context -FactType Computed -Category 'InventoryCoverage' -Statement 'The collector recorded normalized inventory coverage and counts; broad installed-software inventory is disabled by design.' -Value $inventoryCounts -SourceRef ("{0}/inventory.json" -f $Context.PhaseLabel) -ScopeStatus ContextOnly
}

function Add-WudActiveDiagnosticFacts {
    param($Context)
    foreach ($process in @($Context.ProcessRecords)) {
        $name = [string](Get-WudReviewProperty $process 'Name' '<unnamed-process>')
        if ($name -notin @('dism-scanhealth', 'sfc-verifyonly', 'setup-compat-scan', 'setupdiag')) { continue }
        $stdout = [string](Get-WudReviewProperty $process 'StandardOut')
        $excerpt = $null
        if ($stdout -and (Test-Path -LiteralPath $stdout)) {
            try {
                $text = [IO.File]::ReadAllText($stdout)
                $matches = @([Regex]::Matches($text, '(?im)^.*(?:component store|Windows Resource Protection|compatib|error|corrupt|repairable).*$') | Select-Object -First 20 | ForEach-Object { $_.Value.Trim() })
                if (@($matches).Count -gt 0) { $excerpt = @($matches) -join [Environment]::NewLine }
            }
            catch { }
        }
        $value = [pscustomobject][ordered]@{
            Name = $name; Succeeded = Get-WudReviewProperty $process 'Succeeded'; ExitCode = Get-WudReviewProperty $process 'ExitCode'
            ExitCodeHex = Get-WudReviewProperty $process 'ExitCodeHex'; TimedOut = Get-WudReviewProperty $process 'TimedOut'; Error = Get-WudReviewProperty $process 'Error'
        }
        $sourceRef = if ($stdout) { (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $stdout).Replace('\', '/') } else { "{0}/Commands/{1}.result.json" -f $Context.PhaseLabel, $name }
        $category = if ($name -eq 'setup-compat-scan') { 'DiagnosticCompatibilityScan' } elseif ($name -eq 'setupdiag') { 'ToolGeneratedSetupDiag' } else { 'CurrentHealthDiagnostic' }
        $null = Add-WudReviewFact -Context $Context -FactType SourceReported -Category $category -Statement ("Diagnostic process '{0}' returned its recorded execution result." -f $name) -Value $value -TimestampUtc (Get-WudReviewProperty $process 'EndedUtc') -SourceRef $sourceRef -Code ([string](Get-WudReviewProperty $process 'ExitCodeHex')) -ScopeStatus ContextOnly -Excerpt $excerpt
    }
}

function Get-WudUpgradeStatusModel {
    param(
        [Parameter(Mandatory = $true)]$Context,
        $Identity,
        $FeatureHistory = @(),
        $EligibleAttempts = @()
    )
    $display = [string](Get-WudReviewProperty $Identity 'DisplayVersion')
    $build = 0
    $buildReadable = [int]::TryParse([string](Get-WudReviewProperty $Identity 'CurrentBuild'), [ref]$build)
    $targetPresent = $display -eq [string]$Context.TargetVersion -or ($buildReadable -and $build -ge [int]$Context.Target.buildFamily)
    $currentState = if (-not $Identity -or (-not $display -and -not $buildReadable)) { 'Unreadable' } elseif ($targetPresent) { 'TargetPresent' } else { 'TargetNotPresent' }

    $samples = @()
    $samplePath = Join-Path $Context.RunPath 'Evidence\Recorder\ProgressSamples.jsonl'
    if (Test-Path -LiteralPath $samplePath) {
        try { $samples = @((Read-WudJsonLines -Path $samplePath).Records) }
        catch { $samples = @() }
    }
    $observedBuilds = @($samples | ForEach-Object {
        $os = Get-WudReviewProperty $_ 'Os'
        [string](Get-WudReviewProperty $os 'Build')
    } | Where-Object { $_ } | Select-Object -Unique)
    $buildTransition = if ($observedBuilds.Count -gt 1) { 'Observed' } else { 'NotObserved' }
    $baseline = $null
    try {
        $state = Read-WudJson -Path (Join-Path $Context.RunPath 'State\run-state.json')
        $baseline = Get-WudReviewProperty $state 'BaselineIdentity'
    }
    catch { }
    if ($baseline) {
        $baselineBuild = 0
        $baselineReadable = [int]::TryParse([string](Get-WudReviewProperty $baseline 'CurrentBuild'), [ref]$baselineBuild)
        if ($baselineReadable -and $buildReadable -and $baselineBuild -ne $build) { $buildTransition = 'Observed' }
    }

    $featureRows = @($FeatureHistory)
    $windowsUpdateConfirmed = @($EligibleAttempts).Count -gt 0 -or @($featureRows).Count -gt 0
    $deploymentSource = if ($windowsUpdateConfirmed) { 'WindowsUpdateConfirmed' } else { 'Unattributed' }
    $rollbackMarker = Test-Path -LiteralPath (Join-Path $Context.RunPath 'State\Markers\post-rollback.marker')
    $failedHistory = @($featureRows | Where-Object { (Get-WudOperationResultLabel $_.ResultCode) -in @('Failed', 'Aborted') })
    $lastRecorderState = if ($samples.Count -gt 0) { [string](Get-WudReviewProperty $samples[$samples.Count - 1] 'RecorderState') } else { $null }
    $attemptOutcome = if ($rollbackMarker) { 'RolledBack' }
        elseif ($targetPresent -and $buildTransition -eq 'Observed') { 'Succeeded' }
        elseif ($failedHistory.Count -gt 0) { 'Failed' }
        elseif ($lastRecorderState -in @('WindowsUpdateTransportObserved', 'DeliveryOptimizationTransferObserved', 'DownloadObservedComplete', 'SetupActive', 'SetupDownlevel', 'SetupSafeOS', 'SetupFirstBoot', 'SetupOOBE', 'RebootPending')) { 'InProgress' }
        else { 'NotObserved' }
    $outcome = switch ($attemptOutcome) {
        'Succeeded' { 'Upgrade Succeeded' }
        'RolledBack' { 'Rolled Back' }
        'Failed' { 'Failed' }
        'InProgress' { 'Upgrade In Progress' }
        default {
            if ($targetPresent) { 'Target OS Present' }
            elseif ($Context.Mode -eq 'Preflight') { 'Monitoring Armed' }
            else { 'No Upgrade Outcome Observed' }
        }
    }
    return [pscustomobject][ordered]@{
        CurrentOsState = $currentState
        BuildTransition = $buildTransition
        AttemptOutcome = $attemptOutcome
        DeploymentSource = $deploymentSource
        OutcomeBanner = $outcome
        TargetPresent = $targetPresent
        WindowsUpdateEvidenceConfirmed = $windowsUpdateConfirmed
        ObservedBuilds = @($observedBuilds)
    }
}

function Invoke-WudFactAnalysis {
    param([Parameter(Mandatory = $true)]$Context)
    Write-WudLog -Context $Context -Level INFO -Message 'Building direct facts and applying strict Windows Update evidence scope gates. No root-cause inference will be performed.'
    $Context.Facts.Clear(); $Context.Attempts.Clear(); $Context.Timeline.Clear(); $Context.Findings.Clear(); $Context.ExcludedEvidence.Clear()
    $currentInventory = [pscustomobject]$Context.Inventory
    $identity = Get-WudReviewProperty $currentInventory 'Identity'
    $featureHistory = @(Get-WudFeatureUpdateHistory -Context $Context -CurrentInventory $currentInventory)
    $currentServicing = Get-WudReviewProperty $currentInventory 'Servicing'
    $allUpdateHistory = @(Get-WudReviewProperty $currentServicing 'UpdateHistory' @())

    $sequence = 0
    $decodedFacts = @{}
    $seenAttemptHashes = @{}
    $setupFiles = @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter 'setupact*.log' -ErrorAction SilentlyContinue | Sort-Object `
        @{ Expression = { if ($_.FullName -match '(?i)WindowsBT|SetupCopyLogs') { 4 } elseif ($_.FullName -match '(?i)WindowsOld') { 3 } elseif ($_.FullName -match '(?i)Windows-Panther') { 1 } else { 2 } }; Descending = $true },
        @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true })
    foreach ($file in $setupFiles) {
        $sequence++
        $attempt = Get-WudSetupLogProfile -Context $Context -File $file -Sequence $sequence
        $attempt = Set-WudAttemptScope -Context $Context -Attempt $attempt -FeatureHistory $featureHistory -Identity $identity
        if ($attempt.Sha256 -and $seenAttemptHashes.ContainsKey([string]$attempt.Sha256)) {
            $attempt.DuplicateOf = [string]$seenAttemptHashes[[string]$attempt.Sha256]
            $attempt.IncludedForUpgradeReview = $false
            $attempt.Classification = 'UnclassifiedSetupEvidence'
            $attempt.ExclusionReason = "Byte-identical duplicate of $($attempt.DuplicateOf); retained once for provenance and excluded from duplicate analysis."
            $attempt.Gates.UniqueEvidence = $false
        }
        elseif ($attempt.Sha256) { $seenAttemptHashes[[string]$attempt.Sha256] = $attempt.AttemptId }
        $null = $Context.Attempts.Add($attempt)
        if (-not $attempt.IncludedForUpgradeReview) {
            $null = $Context.ExcludedEvidence.Add([pscustomobject][ordered]@{
                EvidenceRef = $attempt.SourcePath
                Sha256 = $attempt.Sha256
                Classification = $attempt.Classification
                Reason = $attempt.ExclusionReason
                Gates = $attempt.Gates
            })
        }
        $scope = if ($attempt.IncludedForUpgradeReview) { 'Included' } else { 'Excluded' }
        $null = Add-WudReviewFact -Context $Context -FactType Computed -Category 'AttemptScope' -Statement ("Setup evidence was classified as {0}." -f $attempt.Classification) -Value $attempt.Gates -TimestampUtc $attempt.EndedUtc -AttemptId $attempt.AttemptId -SourceRef $attempt.SourcePath -ScopeStatus $scope
        if ($attempt.IncludedForUpgradeReview) {
            foreach ($record in @($attempt.ErrorRecords)) {
                $code = if (@($record.Codes).Count -gt 0) { @($record.Codes) -join '; ' } else { $null }
                $fact = Add-WudReviewFact -Context $Context -FactType Observed -Category 'WindowsSetup' -Statement 'Windows Setup recorded an error/failure token or error code in a validated Windows Update feature-upgrade log.' -Value $record.Excerpt -TimestampUtc $record.TimestampUtc -AttemptId $attempt.AttemptId -SourceRef $record.Reference -Code $code -Phase $record.Phase -Operation $record.Operation -Excerpt $record.Excerpt
                $null = $Context.Timeline.Add([pscustomobject][ordered]@{
                    TimestampUtc = $record.TimestampUtc; AttemptId = $attempt.AttemptId; FactId = $fact.FactId
                    EventType = 'SetupLogRecord'; Code = $code; Phase = $record.Phase; Operation = $record.Operation
                    Message = $record.Excerpt; EvidenceReference = $record.Reference
                })
                if ($record.ExtendCode -and ($record.Phase -or $record.Operation)) {
                    $decodeKey = '{0}|{1}|{2}' -f $record.ExtendCode, $record.Phase, $record.Operation
                    if (-not $decodedFacts.ContainsKey($decodeKey)) {
                        $decodedFacts[$decodeKey] = $true
                        $null = Add-WudReviewFact -Context $Context -FactType Decoded -Category 'SetupCode' -Statement ("Setup extend code {0} deterministically decodes to phase '{1}' and operation '{2}'." -f $record.ExtendCode, $record.Phase, $record.Operation) -Value ([pscustomobject]@{ ExtendCode = $record.ExtendCode; Phase = $record.Phase; Operation = $record.Operation }) -TimestampUtc $record.TimestampUtc -AttemptId $attempt.AttemptId -SourceRef $record.Reference -Code $record.ExtendCode -Phase $record.Phase -Operation $record.Operation
                    }
                }
                $parsedCodes = Get-WudCodesFromText -Text ([string]$record.Excerpt)
                foreach ($detail in @($parsedCodes.CodeDetails | Where-Object { $_.Name -and [string]$_.Name -match '^[A-Z][A-Z0-9_]+$' })) {
                    $decodeKey = '{0}|{1}' -f $detail.Code, $detail.Name
                    if ($decodedFacts.ContainsKey($decodeKey)) { continue }
                    $decodedFacts[$decodeKey] = $true
                    $null = Add-WudReviewFact -Context $Context -FactType Decoded -Category 'ErrorCode' -Statement ("Code {0} maps to documented symbolic name {1}." -f $detail.Code, $detail.Name) -Value ([pscustomobject]@{ Code = $detail.Code; Type = $detail.Type; SymbolicName = $detail.Name }) -TimestampUtc $record.TimestampUtc -AttemptId $attempt.AttemptId -SourceRef $record.Reference -Code $detail.Code
                }
            }
        }
    }

    $identityRef = '{0}/Inventory/identity.json' -f $Context.PhaseLabel
    if ($identity) {
        $osValue = [pscustomobject][ordered]@{
            DisplayVersion = Get-WudReviewProperty $identity 'DisplayVersion'
            Build = Get-WudReviewProperty $identity 'CurrentBuild'
            UBR = Get-WudReviewProperty $identity 'UBR'
            Edition = Get-WudReviewProperty $identity 'EditionId'
            WindowsImageState = Get-WudReviewProperty $identity 'WindowsImageState'
        }
        $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'DeviceIdentity' -Statement 'The collector read the current Windows version and image state.' -Value $osValue -TimestampUtc (Get-WudReviewProperty $identity 'CapturedUtc') -SourceRef $identityRef
    }
    Add-WudInventoryFacts -Context $Context -CurrentInventory $currentInventory

    foreach ($entry in $featureHistory) {
        $resultLabel = Get-WudOperationResultLabel -ResultCode $entry.ResultCode
        $statement = 'Windows Update history contains a Windows 11 feature-update entry with result {0}.' -f $resultLabel
        $value = [pscustomobject][ordered]@{
            Title = $entry.Title; Result = $resultLabel; HResultHex = $entry.HResultHex; UpdateID = $entry.UpdateID
            ClientApplicationID = $entry.ClientApplicationID; ServerSelection = $entry.ServerSelection; ServiceID = $entry.ServiceID
        }
        $fact = Add-WudReviewFact -Context $Context -FactType SourceReported -Category 'WindowsUpdateHistory' -Statement $statement -Value $value -TimestampUtc $entry.DateUtc -SourceRef $entry.SourceRef -Code $entry.HResultHex -Excerpt ($value | ConvertTo-Json -Compress -Depth 5)
        $null = $Context.Timeline.Add([pscustomobject][ordered]@{
            TimestampUtc = $entry.DateUtc; AttemptId = $null; FactId = $fact.FactId; EventType = 'WindowsUpdateHistory'
            Code = $entry.HResultHex; Phase = $null; Operation = $entry.Operation; Message = $entry.Title; EvidenceReference = $entry.SourceRef
        })
    }

    foreach ($process in @($Context.ProcessRecords)) {
        if ([bool](Get-WudReviewProperty $process 'Succeeded' $false)) { continue }
        $name = [string](Get-WudReviewProperty $process 'Name' '<unnamed-process>')
        $value = [pscustomobject][ordered]@{
            ExecutionStatus = Get-WudReviewProperty $process 'ExecutionStatus' 'UnknownStatus'
            ExitCode = Get-WudReviewProperty $process 'ExitCode'; ExitCodeHex = Get-WudReviewProperty $process 'ExitCodeHex'
            ExitCodeAvailable = Get-WudReviewProperty $process 'ExitCodeAvailable'
            TimedOut = Get-WudReviewProperty $process 'TimedOut'; Detail = Get-WudReviewProperty $process 'Detail'; Error = Get-WudReviewProperty $process 'ErrorDetail' (Get-WudReviewProperty $process 'Error')
            ExpectedArtifacts = Get-WudReviewProperty $process 'ExpectedArtifacts' @()
        }
        $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'CollectorExecution' -Statement ("Collector process '{0}' did not report success." -f $name) -Value $value -TimestampUtc (Get-WudReviewProperty $process 'EndedUtc') -SourceRef ("{0}/Commands/{1}.result.json" -f $Context.PhaseLabel, ($name -replace '[^A-Za-z0-9._-]', '_')) -ScopeStatus ContextOnly
    }
    foreach ($gap in @($Context.CollectionGaps)) {
        $null = Add-WudReviewFact -Context $Context -FactType Observed -Category 'CollectionCoverage' -Statement ("Collector '{0}' recorded coverage status '{1}'." -f (Get-WudReviewProperty $gap 'Collector'), (Get-WudReviewProperty $gap 'Status')) -Value (Get-WudReviewProperty $gap 'Detail') -TimestampUtc (Get-WudReviewProperty $gap 'RecordedUtc') -SourceRef (Get-WudReviewProperty $gap 'Source') -ScopeStatus ContextOnly
    }
    Add-WudActiveDiagnosticFacts -Context $Context

    Add-WudSetupDiagFacts -Context $Context -Attempts @($Context.Attempts)

    if ($Context.Recorder) {
        $null = Add-WudReviewFact -Context $Context -FactType Computed -Category 'PersistentRecorder' -Statement 'The recorder summarized its timestamped observations without assigning cause.' -Value $Context.Recorder -TimestampUtc (Get-WudReviewProperty $Context.Recorder 'LastSampleUtc') -SourceRef 'Recorder/ProgressSamples.jsonl' -ScopeStatus ContextOnly
        foreach ($transition in @((Get-WudReviewProperty $Context.Recorder 'StateTransitions' @()))) {
            $null = $Context.Timeline.Add([pscustomobject][ordered]@{
                TimestampUtc = Get-WudReviewProperty $transition 'TimestampUtc'; AttemptId = $null; FactId = $null
                EventType = 'RecorderState'; Code = $null; Phase = Get-WudReviewProperty $transition 'State'; Operation = $null
                Message = ('Recorder state changed from {0} to {1}.' -f (Get-WudReviewProperty $transition 'PreviousState'), (Get-WudReviewProperty $transition 'State'))
                EvidenceReference = Get-WudReviewProperty $transition 'EvidenceReference' 'Recorder/ProgressSamples.jsonl'
            })
        }
    }

    $comparisonResult = @(Get-WudReviewInventoryDiff -Context $Context -CurrentInventory $currentInventory)
    $inventoryDiff = $comparisonResult[0]
    $baselineInventory = if ($comparisonResult.Count -gt 1) { $comparisonResult[1] } else { $null }
    $Context.Inventory = [ordered]@{ Baseline = $baselineInventory; Current = $currentInventory; Diff = $inventoryDiff }

    $eligibleAttempts = @($Context.Attempts | Where-Object IncludedForUpgradeReview)
    $Context.StatusModel = Get-WudUpgradeStatusModel -Context $Context -Identity $identity -FeatureHistory $featureHistory -EligibleAttempts $eligibleAttempts
    $Context.Outcome = $Context.StatusModel.OutcomeBanner
    $Context.PrimaryFinding = $null
    $Context.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $Context.ExitCode = if (-not $Context.CollectionComplete) { 30 } elseif ($Context.Outcome -in @('Failed', 'Rolled Back')) { 20 } else { 0 }
    $sortedTimeline = @($Context.Timeline | Sort-Object { if ($_.TimestampUtc) { [DateTimeOffset]::Parse([string]$_.TimestampUtc).UtcTicks } else { [long]::MaxValue } })
    $Context.Timeline.Clear(); foreach ($item in $sortedTimeline) { $null = $Context.Timeline.Add($item) }
    $Context.ReviewData = [pscustomobject][ordered]@{
        AnalysisMode = 'FactOnly'
        FeatureUpdateHistory = @($featureHistory)
        AllUpdateHistory = @($allUpdateHistory)
        InventoryDiff = $inventoryDiff
        Recorder = $Context.Recorder
        StatusModel = $Context.StatusModel
        ValidatedAttemptCount = @($eligibleAttempts).Count
        ExcludedAttemptCount = @($Context.Attempts | Where-Object { -not $_.IncludedForUpgradeReview }).Count
    }
    $analysis = [pscustomobject][ordered]@{
        SchemaVersion = 3; SchemaSemanticVersion = '2.0.0'; ToolVersion = $Context.ToolVersion; RunId = $Context.RunId
        AnalysisMode = 'FactOnly'; Outcome = $Context.Outcome; StatusModel = $Context.StatusModel; Recorder = $Context.Recorder; ExitCode = $Context.ExitCode
        Attempts = @($Context.Attempts); Facts = @($Context.Facts); Findings = @(); Timeline = @($Context.Timeline)
        ExcludedEvidence = @($Context.ExcludedEvidence); Inventory = $Context.Inventory
        StartedUtc = $Context.StartedUtc; CompletedUtc = $Context.CompletedUtc
    }
    Write-WudJsonAtomic -Path (Join-Path $Context.RunPath 'analysis.json') -InputObject $analysis -Depth 50
    return $analysis
}

function Write-WudJsonLines {
    param([string]$Path, $Records)
    $builder = New-Object Text.StringBuilder
    foreach ($record in @($Records)) { $null = $builder.AppendLine(($record | ConvertTo-Json -Compress -Depth 30)) }
    Write-WudText -Path $Path -Text $builder.ToString()
}

function Export-WudReviewCsv {
    param($Records, [string[]]$Headers, [string]$Path)
    $rows = @($Records)
    if ($rows.Count -gt 0) {
        @($rows | Select-Object -Property $Headers) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
    else {
        $line = (@($Headers | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }) -join ',') + [Environment]::NewLine
        Write-WudText -Path $Path -Text $line
    }
}

function Get-WudEvidenceScopeClass {
    param([string]$RelativePath, $Attempts)
    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized -match '(?i)/CurrentDiagnostics/' -or $normalized -match '(?i)/Commands/(?:dism-scanhealth|sfc-verifyonly)') { return 'CurrentHealthDiagnostic' }
    if ($normalized -match '(?i)/Compatibility/MediaScan/') { return 'DiagnosticCompatibilityScan' }
    if ($normalized -match '(?i)/(?:Commands|SetupDiag|Compatibility/AppraiserRefresh)/') { return 'ToolGenerated' }
    if ($normalized -match '(?i)/Raw/Windows-Panther/') { return 'InitialDeploymentOrImaging' }
    if ($normalized -match '(?i)/Raw/(?:Windows-CBS|Windows-DISM)/') { return 'GeneralWindowsServicing' }
    foreach ($attempt in @($Attempts)) {
        $prefix = [string]$attempt.SourceDirectory
        if ($prefix -and $normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return [string]$attempt.Classification }
    }
    if ($normalized -match '(?i)/Raw/(?:WindowsBT|WindowsOld|WUPA-SetupCopyLogs)') { return 'UnclassifiedSetupEvidence' }
    return 'ContextEvidence'
}

function Export-WudReviewBundle {
    param([Parameter(Mandatory = $true)]$Context)
    Write-WudLog -Context $Context -Level INFO -Message 'Creating the provider-neutral drag-and-drop ReviewBundle.zip.'
    $staging = Join-Path $Context.RunPath 'ReviewBundleStaging'
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    $null = New-WudDirectory -Path $staging
    $excerptPath = New-WudDirectory -Path (Join-Path $staging 'Excerpts')
    $recorderSummary = if ($Context.Recorder) { $Context.Recorder } else { [pscustomobject][ordered]@{ SampleCount = 0; FirstSampleUtc = $null; LastSampleUtc = $null; StatesObserved = @(); StateTransitions = @(); DeliveryOptimization = $null } }

    foreach ($fact in @($Context.Facts)) {
        if ([string]::IsNullOrWhiteSpace([string]$fact.Excerpt)) { continue }
        $name = $fact.FactId + '.txt'
        Write-WudText -Path (Join-Path $excerptPath $name) -Text ([string]$fact.Excerpt)
        $fact.ExcerptFile = 'Excerpts/' + $name
    }

    $current = Get-WudReviewProperty $Context.Inventory 'Current'
    $identity = Get-WudReviewProperty $current 'Identity'
    $case = [pscustomobject][ordered]@{
        SchemaVersion = 2
        SchemaSemanticVersion = '2.0.0'
        ToolVersion = $Context.ToolVersion
        AnalysisMode = 'FactOnly'
        RunId = $Context.RunId
        Mode = $Context.Mode
        PhaseLabel = $Context.PhaseLabel
        StartedUtc = $Context.StartedUtc
        CompletedUtc = $Context.CompletedUtc
        Sensitive = $true
        Device = [pscustomobject][ordered]@{
            ComputerName = Get-WudReviewProperty $identity 'ComputerName'; Manufacturer = Get-WudReviewProperty $identity 'Manufacturer'
            Model = Get-WudReviewProperty $identity 'Model'; SerialNumber = Get-WudReviewProperty $identity 'SerialNumber'
        }
        CurrentOs = [pscustomobject][ordered]@{
            DisplayVersion = Get-WudReviewProperty $identity 'DisplayVersion'; Build = Get-WudReviewProperty $identity 'CurrentBuild'
            UBR = Get-WudReviewProperty $identity 'UBR'; Edition = Get-WudReviewProperty $identity 'EditionId'
            WindowsImageState = Get-WudReviewProperty $identity 'WindowsImageState'
        }
        TargetOs = [pscustomobject][ordered]@{ DisplayVersion = $Context.TargetVersion; BuildFamily = $Context.Target.buildFamily }
        ObservedOutcome = $Context.Outcome
        StatusModel = $Context.StatusModel
        Recorder = $recorderSummary
        CollectionComplete = $Context.CollectionComplete
        ValidatedWindowsUpdateAttempts = @($Context.Attempts | Where-Object IncludedForUpgradeReview).Count
        ExcludedSetupCandidates = @($Context.Attempts | Where-Object { -not $_.IncludedForUpgradeReview }).Count
        InterpretationBoundary = 'The package emits direct observations, source-reported results, deterministic decodes, and transparent computed scope gates. It does not assert root cause.'
    }
    Write-WudJsonAtomic -Path (Join-Path $staging 'Case.json') -InputObject $case -Depth 20
    Write-WudJsonAtomic -Path (Join-Path $staging 'Attempts.json') -InputObject @($Context.Attempts) -Depth 40
    Write-WudJsonAtomic -Path (Join-Path $staging 'Inventory.json') -InputObject $Context.Inventory -Depth 40
    Write-WudJsonAtomic -Path (Join-Path $staging 'InventoryDiff.json') -InputObject $Context.ReviewData.InventoryDiff -Depth 20
    Write-WudJsonAtomic -Path (Join-Path $staging 'CollectionCoverage.json') -InputObject ([pscustomobject]@{ Complete = $Context.CollectionComplete; Collectors = @($Context.CollectorRecords); Gaps = @($Context.CollectionGaps) }) -Depth 30
    Write-WudJsonAtomic -Path (Join-Path $staging 'RecorderSummary.json') -InputObject $recorderSummary -Depth 30
    Write-WudJsonAtomic -Path (Join-Path $staging 'ExcludedEvidence.json') -InputObject @($Context.ExcludedEvidence) -Depth 30
    Write-WudJsonLines -Path (Join-Path $staging 'Facts.jsonl') -Records @($Context.Facts)
    Write-WudJsonLines -Path (Join-Path $staging 'Timeline.jsonl') -Records @($Context.Timeline)
    Write-WudJsonLines -Path (Join-Path $staging 'UpdateHistory.jsonl') -Records @($Context.ReviewData.AllUpdateHistory)
    $recorderRoot = Join-Path $Context.RunPath 'Evidence\Recorder'
    foreach ($name in @('ProgressSamples.jsonl', 'StateTransitions.jsonl')) {
        $source = Join-Path $recorderRoot $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $staging $name) -Force }
        else { Write-WudText -Path (Join-Path $staging $name) -Text '' }
    }
    $checkpointManifests = @(Get-ChildItem -LiteralPath (Join-Path $recorderRoot 'Checkpoints') -File -Recurse -Filter 'checkpoint-manifest.json' -ErrorAction SilentlyContinue | ForEach-Object { Read-WudJson -Path $_.FullName })
    Write-WudJsonAtomic -Path (Join-Path $staging 'Checkpoints.json') -InputObject @($checkpointManifests) -Depth 30

    $factRows = @($Context.Facts | ForEach-Object {
        [pscustomobject][ordered]@{
            FactId = $_.FactId; FactType = $_.FactType; Category = $_.Category; ScopeStatus = $_.ScopeStatus
            TimestampUtc = $_.TimestampUtc; AttemptId = $_.AttemptId; Statement = ConvertTo-WudCsvCell $_.Statement
            Value = ConvertTo-WudCsvCell $(if ($_.Value -is [string]) { $_.Value } else { $_.Value | ConvertTo-Json -Compress -Depth 10 })
            Code = $_.Code; Phase = $_.Phase; Operation = $_.Operation; EvidenceRef = ConvertTo-WudCsvCell $_.EvidenceRef; ExcerptFile = $_.ExcerptFile
        }
    })
    Export-WudReviewCsv -Records $factRows -Headers @('FactId', 'FactType', 'Category', 'ScopeStatus', 'TimestampUtc', 'AttemptId', 'Statement', 'Value', 'Code', 'Phase', 'Operation', 'EvidenceRef', 'ExcerptFile') -Path (Join-Path $staging 'Facts.csv')
    Export-WudReviewCsv -Records @($Context.Timeline) -Headers @('TimestampUtc', 'AttemptId', 'FactId', 'EventType', 'Code', 'Phase', 'Operation', 'Message', 'EvidenceReference') -Path (Join-Path $staging 'Timeline.csv')

    $evidenceIndex = New-Object Collections.ArrayList
    foreach ($item in @(Get-WudFileInventory -RootPath $Context.EvidencePath)) {
        $class = Get-WudEvidenceScopeClass -RelativePath $item.RelativePath -Attempts @($Context.Attempts)
        $null = $evidenceIndex.Add([pscustomobject][ordered]@{
            EvidenceRef = $item.RelativePath.Replace('\', '/'); ScopeClass = $class
            IncludedForUpgradeReview = $class -eq 'WindowsUpdateFeatureUpgrade'
            Length = $item.Length; LastWriteUtc = $item.LastWriteUtc; Sha256 = $item.Sha256
        })
    }
    Write-WudJsonLines -Path (Join-Path $staging 'EvidenceIndex.jsonl') -Records @($evidenceIndex)

    $readMe = @'
# WUPA — external review bundle

This archive is sensitive. It can contain device names, users, domains, paths, network identifiers, serial numbers, software inventory, and bounded log excerpts.

## Interpretation contract

- `Observed`: the collector directly read the value or log record.
- `SourceReported`: Windows Update, Windows Setup, or SetupDiag reported the value.
- `Decoded`: a documented numeric code was deterministically decoded.
- `Computed`: transparent arithmetic, diff, or evidence-scope gates; never a causal claim.
- Only attempts classified `WindowsUpdateFeatureUpgrade` passed every scope gate and are included in the upgrade timeline.
- Imaging, general servicing, compatibility scan-only, and tool-generated evidence remain indexed but are excluded from upgrade conclusions.
- This tool does not determine root cause. A human or external review utility must distinguish direct failure records, contributing conditions, coincidence, and cause.

Start with `Case.json`, `RecorderSummary.json`, `ProgressSamples.jsonl`, `Attempts.json`, `Facts.jsonl`, `Timeline.jsonl`, and `CollectionCoverage.json`. Recorder states are observations, not proof that a delay was caused by download, Setup, reboot, or user activity. Use `EvidenceIndex.jsonl` to resolve hashes and `Excerpts/` for bounded source text. Request `Evidence.zip` separately when full raw logs are necessary.
'@
    Write-WudText -Path (Join-Path $staging 'READ_ME_FIRST.md') -Text $readMe
    $prompt = @'
# Suggested external-review prompt

Review this Windows feature-update evidence bundle. Treat `Facts.jsonl` and `ProgressSamples.jsonl` as statements of record, not as proof of causation. Analyze setup content only for attempts in `Attempts.json` where `IncludedForUpgradeReview` is true. Explicitly ignore excluded imaging, scan-only, general-servicing, and tool-generated records when determining the upgrade sequence. Recorder state changes may segment observed activity but do not prove why an interval was quiet.

Report:
1. The factual upgrade sequence, with evidence references.
2. Every source-reported failure/result code and its deterministic phase/operation decode.
3. Plausible explanations separated into supported, unsupported, and information-needed categories.
4. Contradictory evidence and collection gaps.
5. The smallest next investigative step; do not recommend a repair unless evidence supports it.

Never state root cause without quoting the exact evidence reference that supports the causal link. Temporal proximity alone is not causation.
'@
    Write-WudText -Path (Join-Path $staging 'REVIEW_PROMPT.md') -Text $prompt

    $manifestLines = New-Object Collections.ArrayList
    foreach ($file in @(Get-ChildItem -LiteralPath $staging -File -Recurse | Sort-Object FullName)) {
        $relative = (Get-WudRelativePath -BasePath $staging -Path $file.FullName).Replace('\', '/')
        $hash = Get-WudFileHashSafe -Path $file.FullName
        if ($hash) { $null = $manifestLines.Add("$hash  $relative") }
    }
    Write-WudText -Path (Join-Path $staging 'Manifest.sha256') -Text ((@($manifestLines) -join [Environment]::NewLine) + [Environment]::NewLine)
    $destination = Join-Path $Context.OutputPath 'ReviewBundle.zip'
    New-WudEvidenceArchive -SourcePath $staging -DestinationPath $destination -Context $Context
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive = [IO.Compression.ZipFile]::OpenRead($destination)
    try {
        $entryNames = @($archive.Entries | ForEach-Object FullName)
        foreach ($required in @('READ_ME_FIRST.md', 'Case.json', 'RecorderSummary.json', 'ProgressSamples.jsonl', 'StateTransitions.jsonl', 'Checkpoints.json', 'Attempts.json', 'Facts.jsonl', 'Timeline.jsonl', 'EvidenceIndex.jsonl', 'Manifest.sha256')) {
            if ($entryNames -notcontains $required) { throw "Review bundle is missing required entry '$required'." }
        }
        $entryMap = @{}
        foreach ($entry in $archive.Entries) { $entryMap[$entry.FullName.ToLowerInvariant()] = $entry }
        foreach ($line in @($manifestLines)) {
            if ($line -notmatch '^([a-f0-9]{64})\s+(.+)$') { throw "Review bundle manifest line is malformed: $line" }
            $expected = $matches[1]
            $entryName = $matches[2]
            $key = $entryName.ToLowerInvariant()
            if (-not $entryMap.ContainsKey($key)) { throw "Review bundle manifest entry is missing from the archive: $entryName" }
            $stream = $null
            $sha = $null
            try {
                $stream = $entryMap[$key].Open()
                $sha = [Security.Cryptography.SHA256]::Create()
                $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
                if ($actual -ne $expected) { throw "Review bundle hash mismatch: $entryName" }
            }
            finally {
                if ($sha) { $sha.Dispose() }
                if ($stream) { $stream.Dispose() }
            }
        }
    }
    finally { $archive.Dispose() }
    $Context.ReviewBundle = [pscustomobject][ordered]@{
        Path = $destination; Sha256 = Get-WudFileHashSafe -Path $destination; Verified = $true; FactCount = @($Context.Facts).Count
        ValidatedAttemptCount = @($Context.Attempts | Where-Object IncludedForUpgradeReview).Count
        ExcludedAttemptCount = @($Context.Attempts | Where-Object { -not $_.IncludedForUpgradeReview }).Count
    }
    return $Context.ReviewBundle
}

Export-ModuleMember -Function @('Invoke-WudFactAnalysis', 'Export-WudReviewBundle', 'Get-WudSetupLogProfile', 'Set-WudAttemptScope', 'Get-WudUpgradeStatusModel')
