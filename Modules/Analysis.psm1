Set-StrictMode -Version 2.0

function New-WudFindingObject {
    param(
        [string]$Id,
        [string]$Category,
        [string]$Severity,
        [string]$Confidence,
        [string]$Title,
        [string]$Explanation,
        [string]$Recommendation,
        [string[]]$References = @(),
        [string]$InstanceKey = 'default'
    )
    $findingId = '{0}:{1}' -f $Id, (($InstanceKey -replace '[^A-Za-z0-9._-]', '_'))
    return [pscustomobject][ordered]@{
        FindingId      = $findingId
        Id             = $Id
        RuleId         = $Id
        InstanceKey    = $InstanceKey
        Category       = $Category
        Severity       = $Severity
        Confidence     = $Confidence
        Status         = 'Active'
        DispositionReason = $null
        Title          = $Title
        Explanation    = $Explanation
        Summary        = $Explanation
        WhyItMatters   = $Explanation
        Recommendation = $Recommendation
        Phase          = $null
        Operation      = $null
        ResultCode     = $null
        ExtendCode     = $null
        Codes          = @()
        CodeDetails    = @()
        AffectedEntity = $null
        FirstSeenUtc   = $null
        LastSeenUtc    = $null
        Evidence       = New-Object Collections.ArrayList
        References     = @($References)
        MicrosoftReferences = @($References)
    }
}

function Get-WudPhaseOperation {
    param([string]$ExtendCode)
    if ($ExtendCode -notmatch '(?i)^0x([0-5])[0-9A-F]{2}([0-9A-F]{2})$') {
        return [pscustomobject]@{ Phase = $null; Operation = $null }
    }
    $phase = switch ($matches[1].ToUpperInvariant()) {
        '0' { 'Unknown' }
        '1' { 'Downlevel' }
        '2' { 'SafeOS' }
        '3' { 'First Boot' }
        '4' { 'OOBE Boot' }
        '5' { 'Uninstall/Rollback' }
    }
    $operations = @{
        '00' = 'Unknown'; '01' = 'Copy payload'; '02' = 'Download updates'; '03' = 'Install updates';
        '04' = 'Install recovery environment'; '05' = 'Install recovery image'; '06' = 'Replicate optional components';
        '07' = 'Install drivers'; '08' = 'Prepare SafeOS'; '09' = 'Prepare rollback'; '0A' = 'Prepare First Boot';
        '0B' = 'Prepare OOBE Boot'; '0C' = 'Apply image'; '0D' = 'Migrate data'; '0E' = 'Set product key';
        '0F' = 'Add unattend'; '10' = 'Add driver'; '11' = 'Enable feature'; '12' = 'Disable feature';
        '13' = 'Register asynchronous process'; '14' = 'Register synchronous process'; '15' = 'Create file';
        '16' = 'Create registry'; '17' = 'Boot'; '18' = 'Sysprep'; '19' = 'OOBE'; '1A' = 'Begin First Boot';
        '1B' = 'End First Boot'; '1C' = 'Begin OOBE Boot'; '1D' = 'End OOBE Boot'; '1E' = 'Pre-OOBE';
        '1F' = 'Post-OOBE'; '20' = 'Add provisioning package'
    }
    $operationCode = $matches[2].ToUpperInvariant()
    $operation = if ($operations.ContainsKey($operationCode)) { $operations[$operationCode] } else { "Operation 0x$operationCode" }
    return [pscustomobject]@{ Phase = $phase; Operation = $operation }
}

function Get-WudCodesFromText {
    param([string]$Text)
    $codes = New-Object Collections.ArrayList
    foreach ($match in [Regex]::Matches([string]$Text, '(?i)0x(?:[0-9A-F]{8}|[0-5][0-9A-F]{4})(?![0-9A-F])')) {
        $code = '0x' + $match.Value.Substring(2).ToUpperInvariant()
        if (-not $codes.Contains($code)) { $null = $codes.Add($code) }
    }
    $result = @($codes | Where-Object { $_.Length -eq 10 } | Select-Object -First 1)
    $preferredResult = @($codes | Where-Object { $_ -match '^0xC190' } | Select-Object -First 1)
    if (@($preferredResult).Count -gt 0) { $result = $preferredResult }
    $extend = @($codes | Where-Object { $_.Length -eq 7 } | Select-Object -First 1)
    $known = @{
        '0xC1900210' = 'MOSETUP_E_COMPAT_SCANONLY'; '0xC1900208' = 'MOSETUP_E_COMPAT_INSTALLREQ_BLOCK'
        '0xC1900204' = 'MOSETUP_E_COMPAT_MIGCHOICE_BLOCK'; '0xC1900200' = 'MOSETUP_E_COMPAT_SYSREQ_BLOCK'
        '0xC190020E' = 'MOSETUP_E_INSTALLDISKSPACE_BLOCK'; '0xC1900215' = 'MOSETUP_E_NO_MATCHING_INSTALL_IMAGE'
        '0xC1900101' = 'Generic driver rollback family'
        '0xC1900107' = 'Previous installation cleanup is pending'; '0xC190010E' = 'MOSETUP_E_EULA_ACCEPT_REQUIRED'
        '0x8024402C' = 'WU_E_PT_WINHTTP_NAME_NOT_RESOLVED'; '0x80072EE2' = 'WININET_E_TIMEOUT'
        '0x80072F8F' = 'TLS, certificate, content-decoding, or clock failure'; '0x800F0922' = 'Servicing or reserved-partition failure family'
        '0x800F081F' = 'CBS_E_SOURCE_MISSING'; '0x80073712' = 'ERROR_SXS_COMPONENT_STORE_CORRUPT'
    }
    $details = @($codes | ForEach-Object {
        $type = if ($_.Length -eq 7) { 'SetupExtend' } elseif ($_ -match '^0xC190') { 'MoSetup/HRESULT' } elseif ($_ -match '^0x8') { 'HRESULT' } elseif ($_ -match '^0xC') { 'NTSTATUS/HRESULT' } else { 'Win32/Status' }
        [pscustomobject][ordered]@{ Code = $_; Type = $type; Name = if ($known.ContainsKey($_)) { $known[$_] } else { $null } }
    })
    return [pscustomobject]@{
        ResultCode = if (@($result).Count -gt 0) { [string]($result[0]) } else { $null }
        ExtendCode = if (@($extend).Count -gt 0) { [string]($extend[0]) } else { $null }
        Codes = @($codes)
        CodeDetails = $details
    }
}

function ConvertTo-WudLogTimestamp {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $parsed = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [Globalization.DateTimeStyles]::AssumeLocal
    if (-not [DateTimeOffset]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return $null }
    $hasExplicitOffset = $Text -match '(?i)(?:Z|[+-]\d{2}:?\d{2})\s*$'
    $wallClock = [DateTime]::SpecifyKind($parsed.DateTime, [DateTimeKind]::Unspecified)
    $ambiguous = (-not $hasExplicitOffset) -and [TimeZoneInfo]::Local.IsAmbiguousTime($wallClock)
    return [pscustomobject][ordered]@{
        TimestampUtc       = $parsed.UtcDateTime.ToString('o')
        OriginalOffset     = $parsed.Offset.ToString()
        ExplicitOffset     = $hasExplicitOffset
        AmbiguousLocalTime = $ambiguous
        OriginalText       = $Text
    }
}

function Get-WudTextFilesForAnalysis {
    param($Context)
    $extensions = @('.log', '.txt', '.xml', '.json', '.csv', '.ini')
    return @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
        $extensions -contains $_.Extension.ToLowerInvariant() -and $_.Length -le [long]$Context.Settings.maximumTextParseBytes
    })
}

function Find-WudRuleEvidence {
    param($Context, $Rule, [IO.FileInfo[]]$Files)
    $matchesFound = New-Object Collections.ArrayList
    $maximum = [int]$Context.Settings.maximumEvidenceMatchesPerRule
    $regexes = New-Object Collections.ArrayList
    foreach ($pattern in @($Rule.patterns)) {
        try { $null = $regexes.Add((New-Object Regex($pattern, ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)))) }
        catch { $null = $regexes.Add((New-Object Regex([Regex]::Escape([string]$pattern), [Text.RegularExpressions.RegexOptions]::IgnoreCase))) }
    }
    foreach ($file in $Files) {
        if (@($matchesFound).Count -ge $maximum) { break }
        $reader = $null
        try {
            $reader = New-Object IO.StreamReader($file.FullName, $true)
            $lineNumber = 0
            while (-not $reader.EndOfStream -and @($matchesFound).Count -lt $maximum) {
                $line = $reader.ReadLine()
                $lineNumber++
                $isMatch = $false
                foreach ($regex in $regexes) {
                    if ($regex.IsMatch($line)) { $isMatch = $true; break }
                }
                if (-not $isMatch) { continue }
                $excerpt = $line.Trim()
                if ($excerpt.Length -gt 1000) { $excerpt = $excerpt.Substring(0, 1000) + '...' }
                $relative = Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName
                $timestamp = $null
                if ($line -match '^(?<date>\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)') {
                    $timestampInfo = ConvertTo-WudLogTimestamp -Text $matches.date
                    if ($timestampInfo) { $timestamp = $timestampInfo.TimestampUtc }
                }
                $null = $matchesFound.Add([pscustomobject][ordered]@{
                    Reference  = "${relative}:$lineNumber"
                    SourcePath = $relative
                    Line       = $lineNumber
                    TimestampUtc = $timestamp
                    Excerpt    = $excerpt
                })
            }
        }
        catch { }
        finally { if ($reader) { $reader.Dispose() } }
    }
    return @($matchesFound)
}

function Add-WudRuleFindings {
    param($Context)
    $catalog = Read-WudJson -Path (Join-Path $Context.ToolRoot 'Data/rules.json')
    $files = Get-WudTextFilesForAnalysis -Context $Context
    $maximum = [int]$Context.Settings.maximumEvidenceMatchesPerRule
    $states = New-Object Collections.ArrayList
    foreach ($rule in @($catalog.rules)) {
        $parts = New-Object Collections.ArrayList
        foreach ($pattern in @($rule.patterns)) {
            try { $null = $parts.Add("(?:$pattern)") }
            catch { $null = $parts.Add("(?:$([Regex]::Escape([string]$pattern)))") }
        }
        try { $regex = New-Object Regex((@($parts) -join '|'), ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)) }
        catch { $regex = New-Object Regex([Regex]::Escape((@($rule.patterns) -join '|')), [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        $null = $states.Add([pscustomobject]@{ Rule = $rule; Regex = $regex; Evidence = New-Object Collections.ArrayList })
    }
    foreach ($file in $files) {
        $reader = $null
        try {
            $reader = New-Object IO.StreamReader($file.FullName, $true)
            $lineNumber = 0
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                $lineNumber++
                foreach ($state in $states) {
                    if (@($state.Evidence).Count -ge $maximum -or -not $state.Regex.IsMatch($line)) { continue }
                    $excerpt = $line.Trim()
                    if ($excerpt.Length -gt 1000) { $excerpt = $excerpt.Substring(0, 1000) + '...' }
                    $relative = Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName
                    $timestamp = $null
                    if ($line -match '^(?<date>\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)') {
                        $timestampInfo = ConvertTo-WudLogTimestamp -Text $matches.date
                        if ($timestampInfo) { $timestamp = $timestampInfo.TimestampUtc }
                    }
                    if (-not $timestamp) { $timestamp = $file.LastWriteTimeUtc.ToString('o') }
                    $null = $state.Evidence.Add([pscustomobject][ordered]@{
                        Reference    = "${relative}:$lineNumber"
                        SourcePath   = $relative
                        Line         = $lineNumber
                        TimestampUtc = $timestamp
                        Excerpt      = $excerpt
                    })
                }
            }
        }
        catch { }
        finally { if ($reader) { $reader.Dispose() } }
    }
    foreach ($state in $states) {
        $rule = $state.Rule
        $evidence = @($state.Evidence)
        if (@($evidence).Count -eq 0) { continue }
        $finding = New-WudFindingObject -Id $rule.id -Category $rule.category -Severity $rule.severity -Confidence $rule.confidence -Title $rule.title -Explanation $rule.explanation -Recommendation $rule.recommendation -References @($rule.references) -InstanceKey 'aggregate'
        foreach ($item in $evidence) { $null = $finding.Evidence.Add($item) }
        $codes = Get-WudCodesFromText -Text (($evidence | ForEach-Object { $_.Excerpt }) -join ' ')
        $finding.ResultCode = $codes.ResultCode
        $finding.ExtendCode = $codes.ExtendCode
        $finding.Codes = @($codes.Codes)
        $finding.CodeDetails = @($codes.CodeDetails)
        $joinedEvidence = (($evidence | ForEach-Object Excerpt) -join ' ')
        if ($joinedEvidence -match '(?i)\b([A-Za-z0-9_.-]+\.(?:sys|inf|dll|exe|msi))\b') { $finding.AffectedEntity = $matches[1] }
        if ($finding.ExtendCode) {
            $phaseOperation = Get-WudPhaseOperation -ExtendCode $finding.ExtendCode
            $finding.Phase = $phaseOperation.Phase
            $finding.Operation = $phaseOperation.Operation
        }
        $timestamps = @($evidence | Where-Object { $_.TimestampUtc } | ForEach-Object { [DateTimeOffset]::Parse([string]$_.TimestampUtc) } | Sort-Object UtcTicks)
        if (@($timestamps).Count -gt 0) {
            $finding.FirstSeenUtc = $timestamps[0].UtcDateTime.ToString('o')
            $finding.LastSeenUtc = $timestamps[-1].UtcDateTime.ToString('o')
            if (@($Context.Attempts).Count -gt 0) {
                $latestAttempt = @($Context.Attempts | ForEach-Object { [DateTimeOffset]::Parse([string]$_.LastWriteUtc) } | Sort-Object UtcTicks | Select-Object -Last 1)
                if (@($latestAttempt).Count -gt 0 -and $timestamps[-1] -lt $latestAttempt[0].AddDays(-2)) { $finding.Status = 'Historical' }
            }
        }
        $null = Add-WudFinding -Context $Context -Finding $finding
    }
}

function Get-WudNestedPropertyValues {
    param($InputObject, [string[]]$Names, [int]$Depth = 0)
    $values = New-Object Collections.ArrayList
    if ($null -eq $InputObject -or $Depth -gt 8) { return @() }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive) { return @() }
    if ($InputObject -is [Collections.IEnumerable] -and $InputObject -isnot [Collections.IDictionary] -and $InputObject -isnot [string]) {
        foreach ($item in $InputObject) {
            foreach ($value in @(Get-WudNestedPropertyValues -InputObject $item -Names $Names -Depth ($Depth + 1))) { $null = $values.Add($value) }
        }
        return @($values)
    }
    foreach ($property in $InputObject.PSObject.Properties) {
        if ($Names -contains $property.Name -and $null -ne $property.Value -and [string]$property.Value) {
            $null = $values.Add([string]$property.Value)
        }
        if ($null -ne $property.Value -and $property.Value -isnot [string] -and -not $property.Value.GetType().IsPrimitive) {
            foreach ($value in @(Get-WudNestedPropertyValues -InputObject $property.Value -Names $Names -Depth ($Depth + 1))) { $null = $values.Add($value) }
        }
    }
    return @($values)
}

function Enhance-WudFindingsFromSetupDiag {
    param($Context)
    $catalog = Read-WudJson -Path (Join-Path $Context.ToolRoot 'Data/rules.json')
    foreach ($file in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^SetupDiagResults.*\.(json|xml)$' })) {
        $raw = $null
        try { $raw = [IO.File]::ReadAllText($file.FullName) } catch { continue }
        $document = $null
        try {
            if ($file.Extension -ieq '.json') { $document = $raw | ConvertFrom-Json }
            else { $document = [xml]$raw }
        }
        catch { continue }
        $rule = @($catalog.rules | Where-Object {
            $matched = $false
            foreach ($pattern in @($_.patterns)) { if ($raw -match $pattern) { $matched = $true; break } }
            $matched
        } | Select-Object -First 1)
        $ruleId = if (@($rule).Count -gt 0) { [string]$rule[0].id } else { 'WUD-SETUPDIAG-RESULT' }
        $finding = @($Context.Findings | Where-Object Id -eq $ruleId | Select-Object -First 1)
        if (@($finding).Count -gt 0) { $finding = $finding[0] }
        else {
            if (@($rule).Count -gt 0) {
                $definition = $rule[0]
                $finding = New-WudFindingObject -Id $definition.id -Category $definition.category -Severity $definition.severity -Confidence 'High' -Title $definition.title -Explanation $definition.explanation -Recommendation $definition.recommendation -References @($definition.references) -InstanceKey 'setupdiag'
            }
            else {
                $finding = New-WudFindingObject -Id $ruleId -Category 'Setup' -Severity 'Error' -Confidence 'High' -Title 'SetupDiag identified an upgrade issue' -Explanation 'Microsoft SetupDiag produced a structured result that did not map to the local rule catalog.' -Recommendation 'Review the structured SetupDiag evidence and its named profile before planning the next attempt.' -References @('https://learn.microsoft.com/windows/deployment/upgrade/setupdiag') -InstanceKey 'setupdiag'
            }
            $null = Add-WudFinding -Context $Context -Finding $finding
        }
        $finding.Confidence = 'High'
        $codes = Get-WudCodesFromText -Text $raw
        if ($codes.ResultCode) { $finding.ResultCode = $codes.ResultCode }
        if ($codes.ExtendCode) { $finding.ExtendCode = $codes.ExtendCode }
        $finding.Codes = @($codes.Codes)
        $finding.CodeDetails = @($codes.CodeDetails)
        $phases = @(Get-WudNestedPropertyValues $document @('LastPhase', 'Phase'))
        $operations = @(Get-WudNestedPropertyValues $document @('LastOperation', 'Operation'))
        if (@($phases).Count -gt 0) { $finding.Phase = $phases[0] }
        if (@($operations).Count -gt 0) { $finding.Operation = $operations[0] }
        if (-not $finding.Phase -and $finding.ExtendCode) {
            $decoded = Get-WudPhaseOperation $finding.ExtendCode
            $finding.Phase = $decoded.Phase; $finding.Operation = $decoded.Operation
        }
        $entities = @(Get-WudNestedPropertyValues $document @('BlockingApplication', 'ApplicationName', 'DriverName', 'DeviceName', 'InfName', 'FileName', 'FilePath', 'Path', 'ObjectName'))
        if (@($entities).Count -gt 0) { $finding.AffectedEntity = $entities[0] }
        elseif ($raw -match '(?i)CompatBlockedApplication\s*:\s*(.+?)(?:\s+must\b|\s+is\b|[\r\n"]|$)') { $finding.AffectedEntity = $matches[1].Trim() }
        elseif ($raw -match '(?i)\b([A-Za-z0-9_.-]+\.sys)\b') { $finding.AffectedEntity = $matches[1] }
        $messages = @(Get-WudNestedPropertyValues $document @('Message', 'FailureData', 'Remediation', 'ProfileName', 'RuleName'))
        $excerpt = if (@($messages).Count -gt 0) { (@($messages | Select-Object -First 5) -join ' | ') } else { $raw }
        if ($excerpt.Length -gt 1500) { $excerpt = $excerpt.Substring(0, 1500) + '...' }
        $relative = Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName
        $reference = "$relative#structured"
        if (-not @($finding.Evidence | Where-Object Reference -eq $reference).Count) {
            $null = $finding.Evidence.Add([pscustomobject][ordered]@{ Reference = $reference; SourcePath = $relative; Line = $null; TimestampUtc = $file.LastWriteTimeUtc.ToString('o'); Excerpt = $excerpt })
        }
        $finding.FirstSeenUtc = $file.LastWriteTimeUtc.ToString('o')
        $finding.LastSeenUtc = $file.LastWriteTimeUtc.ToString('o')
        if (@($Context.Attempts).Count -gt 0) {
            $latestAttempt = @($Context.Attempts | ForEach-Object { [DateTimeOffset]::Parse([string]$_.LastWriteUtc) } | Sort-Object UtcTicks | Select-Object -Last 1)
            if (@($latestAttempt).Count -gt 0 -and ([DateTimeOffset]$file.LastWriteTimeUtc) -lt $latestAttempt[0].AddDays(-2)) { $finding.Status = 'Historical' }
        }
    }
}

function Add-WudStructuredCompatibilityFindings {
    param($Context)
    foreach ($file in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter '*.xml' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)CompatData|Appraiser|CompatReport' })) {
        $xml = $null
        try { $xml = [xml][IO.File]::ReadAllText($file.FullName) } catch { continue }
        $nodeIndex = 0
        foreach ($node in @($xml.SelectNodes('//*'))) {
            if ($nodeIndex -ge 50) { break }
            $explicitBlock = $false
            foreach ($attribute in @($node.Attributes)) {
                $name = [string]$attribute.Name
                $value = [string]$attribute.Value
                if ($name -match '(?i)BlockingType|BlockMigration|HardBlock|BlockUpgrade|Block' -and $value -match '(?i)^(?:Hard|True|Yes|1|Block|Blocked)$') { $explicitBlock = $true; break }
            }
            if (-not $explicitBlock -and $node.Attributes['Name'] -and $node.Attributes['Value']) {
                $explicitBlock = ([string]$node.Attributes['Name'].Value -match '(?i)Block(?:ing|ed|Upgrade|Migration)' -and [string]$node.Attributes['Value'].Value -match '(?i)^(?:True|Yes|1|Hard|Block|Blocked)$')
            }
            if (-not $explicitBlock) { continue }
            $nodeIndex++
            $entity = $null
            $cursor = $node
            for ($level = 0; $level -lt 5 -and $cursor -and -not $entity; $level++) {
                foreach ($attributeName in @('DisplayName', 'AppName', 'Name', 'DriverName', 'Inf', 'Path', 'LowerCaseLongPath', 'Id')) {
                    if ($cursor.Attributes -and $cursor.Attributes[$attributeName] -and [string]$cursor.Attributes[$attributeName].Value) { $entity = [string]$cursor.Attributes[$attributeName].Value; break }
                }
                $cursor = $cursor.ParentNode
            }
            if (-not $entity) { $entity = $node.Name }
            $instanceKey = (($entity + '-' + $nodeIndex) -replace '[^A-Za-z0-9._-]', '_')
            $finding = New-WudFindingObject -Id 'WUD-COMPAT-XML-HARDBLOCK' -Category 'Compatibility' -Severity 'Blocker' -Confidence 'High' -Title 'Structured compatibility data contains an explicit hard block' -Explanation 'A CompatData or Appraiser XML node explicitly marks an application, driver, object, or migration choice as blocked.' -Recommendation 'Review the named entity and its parent XML context, then use the vendor-supported update/removal path or resolve the stated requirement before another scan.' -References @('https://learn.microsoft.com/troubleshoot/windows-client/setup-upgrade-and-drivers/use-windows-setup-compatibility-scan-logs-to-identify-blocking-issues') -InstanceKey $instanceKey
            $finding.AffectedEntity = $entity
            $finding.Phase = 'Downlevel'
            $finding.Operation = 'Compatibility scan'
            $finding.FirstSeenUtc = $file.LastWriteTimeUtc.ToString('o')
            $finding.LastSeenUtc = $file.LastWriteTimeUtc.ToString('o')
            $excerpt = [string]$node.OuterXml
            if ($excerpt.Length -gt 1500) { $excerpt = $excerpt.Substring(0, 1500) + '...' }
            $relative = Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName
            $null = $finding.Evidence.Add([pscustomobject][ordered]@{ Reference = "$relative#node-$nodeIndex"; SourcePath = $relative; Line = $null; TimestampUtc = $file.LastWriteTimeUtc.ToString('o'); Excerpt = $excerpt })
            if (@($Context.Attempts).Count -gt 0) {
                $latestAttempt = @($Context.Attempts | ForEach-Object { [DateTimeOffset]::Parse([string]$_.LastWriteUtc) } | Sort-Object UtcTicks | Select-Object -Last 1)
                if (@($latestAttempt).Count -gt 0 -and ([DateTimeOffset]$file.LastWriteTimeUtc) -lt $latestAttempt[0].AddDays(-2)) { $finding.Status = 'Historical' }
            }
            $null = Add-WudFinding -Context $Context -Finding $finding
        }
    }
}

function Add-WudCustomFinding {
    param(
        $Context,
        [string]$Id,
        [string]$Category,
        [string]$Severity,
        [string]$Confidence,
        [string]$Title,
        [string]$Explanation,
        [string]$Reference,
        [string]$Excerpt,
        [string[]]$References = @(),
        [string]$InstanceKey = 'default',
        [string]$Recommendation
    )
    if ([string]::IsNullOrWhiteSpace($Recommendation)) {
        $Recommendation = switch ($Category) {
            'Compatibility' { 'Resolve the cited requirement, hold, or named compatibility entity through Microsoft or vendor-supported guidance, then rerun the compatibility assessment.' }
            'Update Delivery' { 'Validate the selected update source, DNS, proxy/TLS, time, routing, and firewall path shown in the evidence, then repeat the diagnostic scan.' }
            'Policy' { 'Reconcile the effective setting in its authoritative GPO, MDM, WSUS, or ConfigMgr owner, allow policy to refresh, and then recapture diagnostics.' }
            'Drivers' { 'Review the cited device and problem codes, use the OEM or enterprise driver-management path to evaluate an appropriate supported driver, and then recapture.' }
            'Servicing' { 'Complete the outstanding servicing or restart prerequisite through the normal organizational maintenance process, then rerun diagnostics before another feature-update attempt.' }
            'Storage' { 'Validate capacity, partition/WinRE state, and storage health using approved operational procedures, then correlate the result with any explicit Windows Setup code.' }
            'Hardware' { 'Review the cited firmware or security state against the hardware vendor and organizational Windows 11 baseline before another attempt.' }
            'Crash' { 'Preserve and analyze the cited dump with an approved debugger, then correlate the identified stack or module with the adjacent Setup and event evidence.' }
            'Tooling' { 'Review the collection coverage and obtain the missing or inaccessible evidence before treating the report as a complete root-cause determination.' }
            default { 'Review the exact cited evidence and address the identified condition through the owning Microsoft, hardware-vendor, or enterprise-management process before retrying.' }
        }
    }
    $finding = New-WudFindingObject -Id $Id -Category $Category -Severity $Severity -Confidence $Confidence -Title $Title -Explanation $Explanation -Recommendation $Recommendation -References $References -InstanceKey $InstanceKey
    if ($Reference) {
        $suffix = ''
        $sourcePath = [string]$Reference
        if ($sourcePath -match '^(.*?)(#.*)$') { $sourcePath = $matches[1]; $suffix = $matches[2] }
        elseif ($sourcePath -match '^(.*?)(:\d+)$') { $sourcePath = $matches[1]; $suffix = $matches[2] }
        $directCandidate = Join-Path $Context.EvidencePath $sourcePath
        if (-not (Test-Path -LiteralPath $directCandidate)) {
            $snapshotCandidate = Join-Path $Context.SnapshotPath $sourcePath
            if ((Test-Path -LiteralPath $snapshotCandidate) -or $sourcePath -notmatch ('^{0}[\\/]' -f [Regex]::Escape([string]$Context.PhaseLabel))) {
                $sourcePath = Get-WudRelativePath -BasePath $Context.EvidencePath -Path $snapshotCandidate
            }
        }
        $normalizedReference = $sourcePath + $suffix
        $null = $finding.Evidence.Add([pscustomobject][ordered]@{ Reference = $normalizedReference; SourcePath = $sourcePath; Line = $null; TimestampUtc = $null; Excerpt = $Excerpt })
    }
    $null = Add-WudFinding -Context $Context -Finding $finding
}

function Find-WudRegistryValue {
    param([string]$Path, [string]$Name)
    $document = Read-WudJson -Path $Path
    if (-not $document) { return @() }
    $results = New-Object Collections.ArrayList
    foreach ($record in @($document)) {
        if ($record.Values -and $record.Values.PSObject.Properties[$Name]) {
            $null = $results.Add([pscustomobject]@{ Path = $record.Path; Value = $record.Values.PSObject.Properties[$Name].Value })
        }
    }
    return @($results)
}

function Add-WudInventoryFindings {
    param($Context)
    $identity = $Context.Inventory['Identity']
    $hardware = $Context.Inventory['Hardware']
    $servicing = $Context.Inventory['Servicing']
    if ($identity -and $identity.SystemLocale -and $identity.SystemLocale -notmatch '^en(?:-|$)') {
        Add-WudCustomFinding $Context 'WUD-LOCALE-CONFIDENCE' 'Tooling' 'Information' 'High' 'Free-text analysis has reduced locale coverage' "The system locale is $($identity.SystemLocale). Structured XML and event identifiers remain authoritative, but English text rules can miss localized messages." 'Inventory\identity.json' $identity.SystemLocale @() 'locale'
    }
    if ($hardware) {
        $osDisk = @($hardware.LogicalDisks | Where-Object { $_.DeviceID -eq $env:SystemDrive }) | Select-Object -First 1
        if ($osDisk -and [long]$osDisk.FreeSpace -lt [long]$Context.Settings.minimumRecommendedOsFreeBytes) {
            Add-WudCustomFinding $Context 'WUD-LOW-OS-FREE-SPACE' 'Storage' 'Warning' 'High' 'OS volume free space is below the recommended diagnostic threshold' ("The OS volume has {0:N2} GB free. Actual Setup requirements vary; an explicit 0xC190020E remains the authoritative installation-space block." -f ([long]$osDisk.FreeSpace / 1GB)) 'Inventory\hardware.json' ("{0} free bytes" -f $osDisk.FreeSpace) @('https://learn.microsoft.com/windows/whats-new/windows-11-requirements') 'os-volume'
        }
        if ($hardware.Tpm -and $hardware.Tpm.PSObject.Properties['TpmPresent'] -and -not $hardware.Tpm.TpmPresent) {
            Add-WudCustomFinding $Context 'WUD-TPM-NOT-PRESENT' 'Hardware' 'Warning' 'High' 'TPM 2.0 readiness could not be confirmed' 'The local TPM provider reports no present TPM. Treat this as a risk signal unless Setup compatibility evidence produces a system-requirements block.' 'Inventory\hardware.json' 'TpmPresent=False' @('https://learn.microsoft.com/windows/whats-new/windows-11-requirements') 'tpm'
        }
        $tpmWmiValues = if ($hardware.PSObject.Properties['TpmWmi']) { @($hardware.TpmWmi) } else { @() }
        $tpmSpec = @($tpmWmiValues | Where-Object { Get-WudObjectPropertyValue $_ 'SpecVersion' } | Select-Object -First 1)
        if (@($tpmSpec).Count -gt 0 -and [string]$tpmSpec[0].SpecVersion -notmatch '(^|,\s*)2\.0(?:,|$)') {
            Add-WudCustomFinding $Context 'WUD-TPM-VERSION' 'Hardware' 'Warning' 'High' 'TPM 2.0 was not reported' ("The firmware TPM provider reports specification versions '{0}', without TPM 2.0." -f $tpmSpec[0].SpecVersion) 'Inventory\hardware.json' ("SpecVersion=$($tpmSpec[0].SpecVersion)") @('https://learn.microsoft.com/windows/whats-new/windows-11-requirements') 'tpm-version'
        }
        if ($hardware.SecureBoot -is [bool] -and -not $hardware.SecureBoot) {
            Add-WudCustomFinding $Context 'WUD-SECUREBOOT-DISABLED' 'Hardware' 'Warning' 'High' 'Secure Boot is disabled' 'Secure Boot is disabled. Because the device already runs Windows 11, use compatibility evidence to decide whether this contributes to the target upgrade.' 'Inventory\hardware.json' 'SecureBoot=False' @('https://learn.microsoft.com/windows/whats-new/windows-11-requirements') 'secureboot'
        }
        $unhealthy = @($hardware.PhysicalDisks | Where-Object { [string]$_.HealthStatus -notin @('', 'Healthy') })
        if (@($unhealthy).Count -gt 0) {
            Add-WudCustomFinding $Context 'WUD-STORAGE-HEALTH' 'Storage' 'Warning' 'High' 'One or more physical disks are not healthy' 'Storage health reports a non-healthy state. Correlate this with disk, NTFS, WHEA, and Setup errors before retrying.' 'Inventory\hardware.json' (($unhealthy | ForEach-Object { "$($_.FriendlyName): $($_.HealthStatus)" }) -join '; ') @() 'physical-disks'
        }
    }
    if ($servicing -and $servicing.PendingReboot -and $servicing.PendingReboot.IsPending) {
        Add-WudCustomFinding $Context 'WUD-PENDING-REBOOT' 'Servicing' 'Warning' 'High' 'A restart or servicing operation is pending' 'One or more supported pending-restart indicators are present. Complete and verify the restart before interpreting later upgrade results.' 'Servicing\servicing.json' ($servicing.PendingReboot | ConvertTo-Json -Compress) @() 'pending-reboot'
    }
    $drivers = $Context.Inventory['Drivers']
    if ($drivers) {
        $problemDevices = @($drivers.Devices | Where-Object {
            $problemCode = Get-WudObjectPropertyValue $_ 'ConfigManagerErrorCode'
            $null -ne $problemCode -and [int]$problemCode -ne 0
        })
        if (@($problemDevices).Count -gt 0) {
            Add-WudCustomFinding $Context 'WUD-PROBLEM-DEVICES' 'Drivers' 'Warning' 'High' 'PnP devices have active problem codes' ("{0} devices report a nonzero ConfigManager error code. They are risk signals, not proven upgrade causes without matching Setup evidence." -f @($problemDevices).Count) 'Inventory\drivers.json' (($problemDevices | Select-Object -First 10 | ForEach-Object { "$(Get-WudObjectPropertyValue $_ 'Name' '<unnamed-device>') [$(Get-WudObjectPropertyValue $_ 'ConfigManagerErrorCode')]" }) -join '; ') @() 'problem-devices'
        }
    }
    $policyFile = Join-Path (Join-Path $Context.SnapshotPath 'Management') 'policy-windows-update.json'
    foreach ($targetPolicy in @(Find-WudRegistryValue -Path $policyFile -Name 'TargetReleaseVersionInfo')) {
        if ($targetPolicy.Value -and [string]$targetPolicy.Value -ne $Context.TargetVersion) {
            Add-WudCustomFinding $Context 'WUD-TARGET-POLICY-CONFLICT' 'Policy' 'Blocker' 'High' 'The configured feature-update target conflicts with this run' ("Effective policy requests {0}, while this diagnostic run targets {1}." -f $targetPolicy.Value, $Context.TargetVersion) 'Management\policy-windows-update.json' ("$($targetPolicy.Path): TargetReleaseVersionInfo=$($targetPolicy.Value)") @('https://learn.microsoft.com/windows/deployment/update/waas-manage-updates-wufb') 'target-version'
        }
    }
    foreach ($productPolicy in @(Find-WudRegistryValue -Path $policyFile -Name 'ProductVersion')) {
        if ($productPolicy.Value -and [string]$productPolicy.Value -notmatch '(?i)^Windows 11$') {
            Add-WudCustomFinding $Context 'WUD-PRODUCT-POLICY-CONFLICT' 'Policy' 'Blocker' 'High' 'The configured target product is not Windows 11' ("Effective policy requests product '{0}', while this diagnostic run targets Windows 11 {1}." -f $productPolicy.Value, $Context.TargetVersion) 'Management\policy-windows-update.json' ("$($productPolicy.Path): ProductVersion=$($productPolicy.Value)") @('https://learn.microsoft.com/windows/deployment/update/waas-manage-updates-wufb') 'target-product'
        }
    }
    foreach ($deferral in @(Find-WudRegistryValue -Path $policyFile -Name 'DeferFeatureUpdatesPeriodInDays')) {
        $deferralDays = 0
        if ([int]::TryParse([string]$deferral.Value, [ref]$deferralDays) -and $deferralDays -gt 0) {
            Add-WudCustomFinding $Context 'WUD-FEATURE-DEFERRAL' 'Policy' 'Warning' 'High' 'Feature updates are deferred by policy' ("The effective policy defers feature updates by {0} days. This can delay when 25H2 is offered even when the device is otherwise compatible." -f $deferral.Value) 'Management\policy-windows-update.json' ("$($deferral.Path): DeferFeatureUpdatesPeriodInDays=$($deferral.Value)") @('https://learn.microsoft.com/windows/deployment/update/waas-configure-wufb') 'feature-deferral'
        }
    }
    foreach ($bypass in @(Find-WudRegistryValue -Path $policyFile -Name 'DisableWUfBSafeguards')) {
        $bypassValue = 0
        if ([int]::TryParse([string]$bypass.Value, [ref]$bypassValue) -and $bypassValue -eq 1) {
            Add-WudCustomFinding $Context 'WUD-SAFEGUARD-BYPASS-POLICY' 'Policy' 'Warning' 'High' 'Policy disables Windows Update safeguard protections' 'The effective policy permits feature updates to be offered without normal safeguard-hold protection. Win11UpgradeDiag does not change this policy or bypass a hold.' 'Management\policy-windows-update.json' ("$($bypass.Path): DisableWUfBSafeguards=1") @('https://learn.microsoft.com/windows/deployment/update/safeguard-opt-out') 'safeguard-policy'
        }
    }
    $uxPolicyFile = Join-Path (Join-Path $Context.SnapshotPath 'Management') 'ux-settings.json'
    $pauseValues = @()
    foreach ($pauseName in @('PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PausedFeatureStatus')) { $pauseValues += @(Find-WudRegistryValue -Path $uxPolicyFile -Name $pauseName) }
    if (@($pauseValues | Where-Object { $null -ne $_.Value -and [string]$_.Value -notin @('', '0') }).Count -gt 0) {
        Add-WudCustomFinding $Context 'WUD-FEATURE-UPDATE-PAUSE' 'Policy' 'Warning' 'Medium' 'Feature-update pause state is configured' 'Windows Update UX state contains an active or retained feature-update pause indicator. Confirm the effective pause dates in Settings, MDM, or Group Policy.' 'Management\ux-settings.json' (($pauseValues | ForEach-Object { "$($_.Path): $($_.Value)" }) -join '; ') @('https://learn.microsoft.com/windows/deployment/update/waas-configure-wufb') 'feature-pause'
    }
    $appCompatFile = Join-Path (Join-Path $Context.SnapshotPath 'Management') 'appcompat-flags.json'
    $gstatus = Find-WudRegistryValue -Path $appCompatFile -Name 'GStatus'
    $blockIds = Find-WudRegistryValue -Path $appCompatFile -Name 'GatedBlockId'
    foreach ($status in @($gstatus | Where-Object { [string]$_.Value -eq '0' })) {
        $candidate = @($blockIds | Where-Object { $_.Path -eq $status.Path } | Select-Object -First 1)
        if (@($candidate).Count -eq 0) { $candidate = @($blockIds | Where-Object { $_.Path -match [Regex]::Escape($Context.TargetVersion) } | Select-Object -First 1) }
        $id = if (@($candidate).Count -gt 0) { [string]$candidate[0].Value } else { 'not exposed' }
        Add-WudCustomFinding $Context 'WUD-SAFEGUARD-HOLD' 'Compatibility' 'Blocker' 'High' 'A Windows safeguard hold is active' ("Compatibility intelligence reports GStatus=0. Safeguard ID: $id.") 'Management\appcompat-flags.json' ("$($status.Path); GStatus=0; GatedBlockId=$id") @('https://learn.microsoft.com/windows/deployment/update/safeguard-holds', [string]$Context.Target.releaseHealthUrl) ("safeguard-$id")
    }
    $management = $Context.Inventory['Management']
    if ($management) {
        $unreachableConfigured = @($management.Connectivity | Where-Object { -not $_.Reachable -and $_.Kind -eq 'ConfiguredUpdateService' })
        if (@($unreachableConfigured).Count -gt 0) {
            Add-WudCustomFinding $Context 'WUD-CONFIGURED-SOURCE-UNREACHABLE' 'Update Delivery' 'Error' 'High' 'The configured WSUS or intranet update service was unreachable' 'The endpoint selected by effective Windows Update policy could not be reached during the bounded test. Review its exact URI, DNS, proxy bypass, TLS/certificate, route, firewall, and service health.' 'Management\management-summary.json' (($unreachableConfigured | ForEach-Object { "$($_.Uri): $($_.Error)" }) -join '; ') @('https://learn.microsoft.com/windows-server/administration/windows-server-update-services/manage/connecting-to-update-services') 'configured-update-source'
        }
        $unreachable = @($management.Connectivity | Where-Object { -not $_.Reachable -and $_.Kind -eq 'MicrosoftPublic' })
        if (-not $management.InternetTestsSuppressed -and @($unreachable).Count -gt 0) {
            Add-WudCustomFinding $Context 'WUD-CONNECTIVITY' 'Update Delivery' 'Warning' 'High' 'One or more Microsoft diagnostic endpoints were unreachable' 'This can prevent current compatibility intelligence or update content from being obtained. Review proxy, DNS, TLS inspection, time, and firewall evidence.' 'Management\management-summary.json' (($unreachable | ForEach-Object { "$($_.Uri): $($_.Error)" }) -join '; ') @('https://learn.microsoft.com/windows/deployment/update/safeguard-holds') 'microsoft-endpoints'
        }
    }
    $mediaFile = Join-Path (Join-Path (Join-Path $Context.SnapshotPath 'Compatibility') 'MediaScan') 'media-scan.json'
    $media = Read-WudJson -Path $mediaFile
    if ($media -and $media.Requested -and -not $media.EulaAccepted) {
        Add-WudCustomFinding $Context 'WUD-MEDIA-EULA-NOT-ACCEPTED' 'Compatibility' 'Warning' 'High' 'The requested media scan was not run because EULA acceptance was absent' $media.Reason 'Compatibility\MediaScan\media-scan.json' $media.Reason @('https://learn.microsoft.com/windows-hardware/manufacture/desktop/windows-setup-command-line-options') 'media-eula'
    }
    elseif ($media -and $media.Requested -and $media.EulaAccepted -and -not $media.Validated) {
        Add-WudCustomFinding $Context 'WUD-MEDIA-VALIDATION' 'Compatibility' 'Warning' 'High' 'The supplied target media did not pass validation' $media.Reason 'Compatibility\MediaScan\media-scan.json' $media.Reason @('https://learn.microsoft.com/windows-hardware/manufacture/desktop/windows-setup-command-line-options') 'media-validation'
    }
    if ($media -and $media.Executed -and $media.Result.ExitCodeHex -eq '0xC1900210') {
        Add-WudCustomFinding $Context 'WUD-COMPAT-SCAN-CLEAN' 'Compatibility' 'Information' 'High' 'Target-media compatibility scan found no actionable concerns' 'Windows Setup returned MOSETUP_E_COMPAT_SCANONLY (0xC1900210), the documented clean scan-only result.' 'Compatibility\MediaScan\media-scan.json' '0xC1900210' @('https://learn.microsoft.com/troubleshoot/windows-client/setup-upgrade-and-drivers/use-windows-setup-compatibility-scan-logs-to-identify-blocking-issues') 'media-scan'
    }
    $setupDumps = @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'setupmem.dmp' })
    if (@($setupDumps).Count -gt 0) {
        $references = @($setupDumps | ForEach-Object { Get-WudRelativePath -BasePath $Context.EvidencePath -Path $_.FullName })
        Add-WudCustomFinding $Context 'WUD-SETUP-MEMORY-DUMP' 'Crash' 'Error' 'High' 'Windows Setup captured a setup-related memory dump' 'A setupmem.dmp file is direct evidence that a bug check occurred during the upgrade. The report does not claim a driver until the dump is debugged and correlated.' $references[0] (@($references) -join '; ') @('https://learn.microsoft.com/windows/deployment/upgrade/setupdiag') 'setupmem'
    }
    if (-not $Context.CollectionComplete) {
        $failed = @($Context.CollectorRecords | Where-Object { $_.Status -in @('Failed', 'TimedOut') })
        $materialGaps = @($Context.CollectionGaps | Where-Object Impact -eq 'Material')
        Add-WudCustomFinding $Context 'WUD-COLLECTION-INCOMPLETE' 'Tooling' 'Warning' 'High' 'Material evidence collection was incomplete' ("{0} required collectors failed or timed out and {1} material gaps were recorded. Conclusions must be read with the coverage table." -f @($failed).Count, @($materialGaps).Count) 'collector-records.json' ((@($failed | ForEach-Object { "$($_.Id): $($_.Detail)" }) + @($materialGaps | ForEach-Object { "$($_.Source): $($_.Status)" })) -join '; ') @() 'coverage'
    }
}

function Add-WudTimelineFromLogs {
    param($Context)
    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter '*.log' -ErrorAction SilentlyContinue)) {
        if ($count -ge 2000 -or $file.Length -gt [long]$Context.Settings.maximumTextParseBytes) { continue }
        $reader = $null
        try {
            $reader = New-Object IO.StreamReader($file.FullName, $true)
            $lineNumber = 0
            while (-not $reader.EndOfStream -and $count -lt 2000) {
                $line = $reader.ReadLine()
                $lineNumber++
                if ($line -notmatch '(?i)Error|Fatal|Rollback|Safe.OS|First.Boot|OOBE|Downlevel|compatib') { continue }
                if ($line -notmatch '^(?<date>\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)') { continue }
                $timestampInfo = ConvertTo-WudLogTimestamp -Text $matches.date
                if (-not $timestampInfo) { continue }
                $relative = Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName
                $severity = if ($line -match '(?i)Fatal|Error|Rollback') { 'Error' } else { 'Information' }
                $codes = Get-WudCodesFromText -Text $line
                $phase = $null
                $operation = $null
                if ($codes.ExtendCode) {
                    $decoded = Get-WudPhaseOperation -ExtendCode $codes.ExtendCode
                    $phase = $decoded.Phase; $operation = $decoded.Operation
                }
                $message = $line.Trim()
                if ($message.Length -gt 500) { $message = $message.Substring(0, 500) + '...' }
                Add-WudTimelineEvent $Context ([pscustomobject][ordered]@{
                    TimestampUtc = $timestampInfo.TimestampUtc
                    LocalOffset  = $timestampInfo.OriginalOffset
                    TimestampAmbiguous = $timestampInfo.AmbiguousLocalTime
                    AttemptId    = $null
                    Phase        = $phase
                    Operation    = $operation
                    Code         = (@($codes.Codes) -join '; ')
                    Component    = $file.Name
                    Event        = $message
                    Message      = $message
                    Severity     = $severity
                    SourceRef    = "${relative}:$lineNumber"
                    EvidenceReference = "${relative}:$lineNumber"
                    Entity       = $null
                    CorrelationId = $null
                })
                $count++
            }
        }
        catch { }
        finally { if ($reader) { $reader.Dispose() } }
    }
    foreach ($eventFile in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter 'errors-and-warnings.json' -ErrorAction SilentlyContinue)) {
        foreach ($event in @(Read-WudJson -Path $eventFile.FullName | Select-Object -First 2000)) {
            if (-not $event.TimeCreated) { continue }
            $eventTimestampInfo = ConvertTo-WudLogTimestamp -Text ([string]$event.TimeCreated)
            if (-not $eventTimestampInfo) { continue }
            Add-WudTimelineEvent $Context ([pscustomobject][ordered]@{
                TimestampUtc = $eventTimestampInfo.TimestampUtc
                LocalOffset  = $eventTimestampInfo.OriginalOffset
                TimestampAmbiguous = $eventTimestampInfo.AmbiguousLocalTime
                AttemptId    = $null
                Phase        = $null
                Operation    = $null
                Code         = $null
                Component    = $event.Provider
                Event        = if ([string]$event.Message) { ([string]$event.Message).Substring(0, [Math]::Min(500, ([string]$event.Message).Length)) } else { "Event $($event.Id)" }
                Message      = if ([string]$event.Message) { ([string]$event.Message).Substring(0, [Math]::Min(500, ([string]$event.Message).Length)) } else { "Event $($event.Id)" }
                Severity     = $event.Level
                SourceRef    = (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $eventFile.FullName) + "#RecordId=$($event.RecordId)"
                EvidenceReference = (Get-WudRelativePath -BasePath $Context.EvidencePath -Path $eventFile.FullName) + "#RecordId=$($event.RecordId)"
                Entity       = $event.Provider
                CorrelationId = $event.Id
            })
        }
    }
    $sorted = @($Context.Timeline | Sort-Object { [DateTimeOffset]::Parse([string]$_.TimestampUtc).UtcTicks })
    $Context.Timeline.Clear()
    foreach ($event in $sorted) {
        if (-not $event.AttemptId -and $event.TimestampUtc) {
            $eventTime = [DateTimeOffset]::Parse([string]$event.TimestampUtc).UtcDateTime
            $candidate = @($Context.Attempts | Where-Object {
                $start = if ($_.StartedUtc) { [DateTimeOffset]::Parse([string]$_.StartedUtc).UtcDateTime.AddHours(-2) } else { [DateTimeOffset]::Parse([string]$_.LastWriteUtc).UtcDateTime.AddHours(-12) }
                $end = if ($_.EndedUtc) { [DateTimeOffset]::Parse([string]$_.EndedUtc).UtcDateTime.AddHours(2) } else { [DateTimeOffset]::Parse([string]$_.LastWriteUtc).UtcDateTime.AddHours(2) }
                $eventTime -ge $start -and $eventTime -le $end
            } | Sort-Object { [Math]::Abs(([DateTimeOffset]::Parse([string]$_.LastWriteUtc).UtcDateTime - $eventTime).TotalSeconds) } | Select-Object -First 1)
            if (@($candidate).Count -gt 0) { $event.AttemptId = $candidate[0].AttemptId }
        }
        $null = $Context.Timeline.Add($event)
    }
}

function Get-WudAttemptInventory {
    param($Context)
    $attempts = New-Object Collections.ArrayList
    $index = 0
    $seenHashes = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -Filter 'setupact*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)) {
        $index++
        $hash = Get-WudFileHashSafe -Path $file.FullName
        if ($hash -and $seenHashes.ContainsKey($hash)) { continue }
        if ($hash) { $seenHashes[$hash] = $true }
        $codes = New-Object Collections.ArrayList
        $firstTimestamp = $null
        $lastTimestamp = $null
        $sourceBuild = $null
        $targetBuild = $null
        $reader = $null
        try {
            $reader = New-Object IO.StreamReader($file.FullName, $true)
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($line -match '^(?<date>\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)') {
                    $timestampInfo = ConvertTo-WudLogTimestamp -Text $matches.date
                    if ($timestampInfo) {
                        $parsedUtc = [DateTimeOffset]::Parse([string]$timestampInfo.TimestampUtc).UtcDateTime
                        if (-not $firstTimestamp) { $firstTimestamp = $parsedUtc }
                        $lastTimestamp = $parsedUtc
                    }
                }
                if (-not $sourceBuild -and $line -match '(?i)source build\s+(\d{5})') { $sourceBuild = $matches[1] }
                if (-not $targetBuild -and $line -match '(?i)target build\s+(\d{5})') { $targetBuild = $matches[1] }
                if (@($codes).Count -lt 30) {
                    foreach ($match in [Regex]::Matches($line, '(?i)0x(?:[0-9A-F]{8}|[0-5][0-9A-F]{4})(?![0-9A-F])')) {
                        $code = '0x' + $match.Value.Substring(2).ToUpperInvariant()
                        if (-not $codes.Contains($code)) { $null = $codes.Add($code) }
                        if (@($codes).Count -ge 30) { break }
                    }
                }
            }
        }
        catch { }
        finally { if ($reader) { $reader.Dispose() } }
        $relative = Get-WudRelativePath -BasePath $Context.EvidencePath -Path $file.FullName
        $phase = if ($relative -match '(?i)Rollback') { 'Rollback' } elseif ($relative -match '(?i)NewOS') { 'NewOS' } else { 'Downlevel/Post-upgrade' }
        $null = $attempts.Add([pscustomobject][ordered]@{
            AttemptId    = "attempt-$index"
            Source       = $relative
            PhaseHint    = $phase
            LastWriteUtc = $file.LastWriteTimeUtc.ToString('o')
            StartedUtc    = if ($firstTimestamp) { $firstTimestamp.ToString('o') } else { $null }
            EndedUtc      = if ($lastTimestamp) { $lastTimestamp.ToString('o') } else { $file.LastWriteTimeUtc.ToString('o') }
            SourceBuild   = $sourceBuild
            TargetBuild   = $targetBuild
            Sha256        = $hash
            Codes        = @($codes)
        })
    }
    return @($attempts)
}

function ConvertTo-WudApplicationMap {
    param($Inventory)
    $map = @{}
    if (-not $Inventory -or -not $Inventory.Software) { return $map }
    foreach ($item in @($Inventory.Software.Applications)) {
        $key = ([string](Get-WudObjectPropertyValue $item 'DisplayName')).Trim().ToLowerInvariant()
        if ($key) { $map[$key] = [string](Get-WudObjectPropertyValue $item 'DisplayVersion') }
    }
    return $map
}

function ConvertTo-WudDriverMap {
    param($Inventory)
    $map = @{}
    if (-not $Inventory -or -not $Inventory.Drivers) { return $map }
    foreach ($item in @($Inventory.Drivers.SignedDrivers)) {
        $key = ([string](Get-WudObjectPropertyValue $item 'DeviceID')).Trim().ToLowerInvariant()
        if ($key) { $map[$key] = [string](Get-WudObjectPropertyValue $item 'DriverVersion') }
    }
    return $map
}

function ConvertTo-WudInventoryItemMap {
    param($Items, [string]$KeyProperty, [string[]]$ValueProperties)
    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $keyMember = $item.PSObject.Properties[$KeyProperty]
        if (-not $keyMember) { continue }
        $key = ([string]$keyMember.Value).Trim().ToLowerInvariant()
        if (-not $key) { continue }
        $parts = New-Object Collections.ArrayList
        foreach ($name in $ValueProperties) {
            $member = $item.PSObject.Properties[$name]
            if ($member) { $null = $parts.Add(("{0}={1}" -f $name, [string]$member.Value)) }
        }
        $map[$key] = @($parts) -join '|'
    }
    return $map
}

function Get-WudInventoryCollection {
    param($Inventory, [string]$Section, [string]$Property)
    if (-not $Inventory) { return @() }
    $sectionMember = $Inventory.PSObject.Properties[$Section]
    if (-not $sectionMember -or -not $sectionMember.Value) { return @() }
    $propertyMember = $sectionMember.Value.PSObject.Properties[$Property]
    if (-not $propertyMember) { return @() }
    return @($propertyMember.Value)
}

function ConvertTo-WudPolicyMap {
    param($Inventory)
    $map = @{}
    if (-not $Inventory -or -not $Inventory.Management -or -not $Inventory.Management.PSObject.Properties['RegistryExports']) { return $map }
    foreach ($export in $Inventory.Management.RegistryExports.PSObject.Properties) {
        foreach ($record in @($export.Value)) {
            $key = ("{0}|{1}" -f $export.Name, [string]$record.Path).ToLowerInvariant()
            $map[$key] = if ($record.Values) { $record.Values | ConvertTo-Json -Compress -Depth 8 } else { '{}' }
        }
    }
    return $map
}

function ConvertTo-WudSecurityMap {
    param($Inventory)
    $map = @{}
    if (-not $Inventory) { return $map }
    if ($Inventory.Hardware) {
        $map['secureboot'] = [string]$Inventory.Hardware.SecureBoot
        if ($Inventory.Hardware.Tpm) { $map['tpm'] = $Inventory.Hardware.Tpm | ConvertTo-Json -Compress -Depth 5 }
    }
    if ($Inventory.Software) {
        $antivirusProducts = if ($Inventory.Software.PSObject.Properties['AntivirusProducts']) { @($Inventory.Software.AntivirusProducts) } else { @() }
        foreach ($product in $antivirusProducts) {
            $key = ('antivirus|' + [string]$product.displayName).ToLowerInvariant()
            $map[$key] = '{0}|{1}' -f $product.productState, $product.timestamp
        }
    }
    return $map
}

function Compare-WudMap {
    param([hashtable]$Before, [hashtable]$After)
    $added = New-Object Collections.ArrayList
    $removed = New-Object Collections.ArrayList
    $changed = New-Object Collections.ArrayList
    foreach ($key in $After.Keys) {
        if (-not $Before.ContainsKey($key)) { $null = $added.Add([pscustomobject]@{ Key = $key; After = $After[$key] }) }
        elseif ($Before[$key] -ne $After[$key]) { $null = $changed.Add([pscustomobject]@{ Key = $key; Before = $Before[$key]; After = $After[$key] }) }
    }
    foreach ($key in $Before.Keys) {
        if (-not $After.ContainsKey($key)) { $null = $removed.Add([pscustomobject]@{ Key = $key; Before = $Before[$key] }) }
    }
    return [pscustomobject]@{ Added = @($added); Removed = @($removed); Changed = @($changed) }
}

function Get-WudSnapshotComparison {
    param($Context)
    $snapshotDirs = @(Get-ChildItem -LiteralPath $Context.EvidencePath -Directory -ErrorAction SilentlyContinue)
    $baselineDir = @($snapshotDirs | Where-Object Name -eq 'Preflight' | Select-Object -First 1)
    $currentDir = @($snapshotDirs | Where-Object Name -eq $Context.PhaseLabel | Select-Object -First 1)
    if (@($currentDir).Count -eq 0) { $currentDir = @($snapshotDirs | Sort-Object LastWriteTimeUtc | Select-Object -Last 1) }
    $baseline = if (@($baselineDir).Count -gt 0) { Read-WudJson -Path (Join-Path $baselineDir[0].FullName 'inventory.json') } else { $null }
    $current = if (@($currentDir).Count -gt 0) { Read-WudJson -Path (Join-Path $currentDir[0].FullName 'inventory.json') } else { $Context.Inventory }
    $diff = [pscustomobject][ordered]@{
        Available    = ($null -ne $baseline -and $null -ne $current -and @($baselineDir).Count -gt 0 -and $baselineDir[0].FullName -ne $currentDir[0].FullName)
        Applications = $null
        Drivers      = $null
        Packages     = $null
        Devices      = $null
        Services     = $null
        Policies     = $null
        Security     = $null
        Disks        = $null
        Networks     = $null
        SourceBuild  = if ($baseline -and $baseline.Identity) { $baseline.Identity.CurrentBuild } else { $null }
        CurrentBuild = if ($current -and $current.Identity) { $current.Identity.CurrentBuild } else { $null }
    }
    if ($diff.Available) {
        $diff.Applications = Compare-WudMap -Before (ConvertTo-WudApplicationMap $baseline) -After (ConvertTo-WudApplicationMap $current)
        $diff.Drivers = Compare-WudMap -Before (ConvertTo-WudDriverMap $baseline) -After (ConvertTo-WudDriverMap $current)
        $diff.Packages = Compare-WudMap -Before (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $baseline 'Servicing' 'Packages') 'PackageName' @('PackageState', 'ReleaseType', 'InstallTime')) -After (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $current 'Servicing' 'Packages') 'PackageName' @('PackageState', 'ReleaseType', 'InstallTime'))
        $diff.Devices = Compare-WudMap -Before (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $baseline 'Drivers' 'Devices') 'DeviceID' @('Name', 'Status', 'ConfigManagerErrorCode', 'Service')) -After (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $current 'Drivers' 'Devices') 'DeviceID' @('Name', 'Status', 'ConfigManagerErrorCode', 'Service'))
        $diff.Services = Compare-WudMap -Before (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $baseline 'Software' 'Services') 'Name' @('State', 'StartMode', 'PathName', 'StartName')) -After (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $current 'Software' 'Services') 'Name' @('State', 'StartMode', 'PathName', 'StartName'))
        $diff.Policies = Compare-WudMap -Before (ConvertTo-WudPolicyMap $baseline) -After (ConvertTo-WudPolicyMap $current)
        $diff.Security = Compare-WudMap -Before (ConvertTo-WudSecurityMap $baseline) -After (ConvertTo-WudSecurityMap $current)
        $diff.Disks = Compare-WudMap -Before (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $baseline 'Hardware' 'LogicalDisks') 'DeviceID' @('FileSystem', 'Size', 'FreeSpace', 'Status')) -After (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $current 'Hardware' 'LogicalDisks') 'DeviceID' @('FileSystem', 'Size', 'FreeSpace', 'Status'))
        $diff.Networks = Compare-WudMap -Before (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $baseline 'Management' 'NetworkAdapters') 'InterfaceDescription' @('Name', 'Status', 'MacAddress', 'LinkSpeed', 'DriverVersion')) -After (ConvertTo-WudInventoryItemMap (Get-WudInventoryCollection $current 'Management' 'NetworkAdapters') 'InterfaceDescription' @('Name', 'Status', 'MacAddress', 'LinkSpeed', 'DriverVersion'))
    }
    return [pscustomobject]@{ Baseline = $baseline; Current = $current; Diff = $diff }
}

function Resolve-WudOutcome {
    param($Context)
    $identity = $Context.Inventory['Identity']
    if (-not $identity -and $Context.Inventory['Current']) { $identity = $Context.Inventory['Current'].Identity }
    $targetReached = $false
    if ($identity) {
        $targetReached = ([string]$identity.DisplayVersion -eq [string]$Context.TargetVersion) -or ([int]$identity.CurrentBuild -ge [int]$Context.Target.buildFamily)
    }
    $rollbackMarker = Test-Path -LiteralPath (Join-Path $Context.RunPath 'State\Markers\post-rollback.marker')
    $rollbackEvidence = @(Get-ChildItem -LiteralPath $Context.EvidencePath -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '(?i)Rollback' }).Count -gt 0
    $activeFindings = @($Context.Findings | Where-Object Status -ne 'Historical')
    $blockers = @($activeFindings | Where-Object Severity -eq 'Blocker').Count
    $errors = @($activeFindings | Where-Object Severity -eq 'Error').Count
    $warnings = @($activeFindings | Where-Object Severity -eq 'Warning').Count
    if ($targetReached) { return 'Upgrade Succeeded' }
    if ($rollbackMarker -or ($Context.Mode -ne 'Preflight' -and $rollbackEvidence -and $errors -gt 0)) { return 'Rolled Back' }
    if ($Context.Mode -eq 'Preflight') {
        if ($blockers -gt 0) { return 'Blocked' }
        if ($errors -gt 0 -or $warnings -gt 0) { return 'Attention Required' }
        return 'Ready'
    }
    if ($errors -gt 0 -or $blockers -gt 0) { return 'Failed' }
    if ($warnings -gt 0) { return 'Attention Required' }
    return 'Unknown'
}

function Apply-WudLaterSuccessSuppression {
    param($Context)
    $identity = $Context.Inventory['Identity']
    if (-not $identity) { return }
    $targetReached = ([string]$identity.DisplayVersion -eq [string]$Context.TargetVersion) -or ([int]$identity.CurrentBuild -ge [int]$Context.Target.buildFamily)
    if (-not $targetReached) { return }
    foreach ($finding in @($Context.Findings | Where-Object { $_.Status -ne 'Historical' -and $_.Severity -ne 'Information' })) {
        if ($finding.InstanceKey -notin @('aggregate', 'setupdiag') -and $finding.RuleId -ne 'WUD-COMPAT-XML-HARDBLOCK') { continue }
        $setupEvidence = @($finding.Evidence | Where-Object { $_.SourcePath -match '(?i)Panther|Rollback|SetupDiag|MoSetup|SetupCopyLogs|MediaScan' })
        $currentHealthEvidence = @($finding.Evidence | Where-Object { $_.SourcePath -match '(?i)Commands[\\/](?:dism-scanhealth|sfc-verifyonly)|Events[\\/](?:errors-and-warnings|reliability)' })
        if (@($setupEvidence).Count -gt 0 -and @($currentHealthEvidence).Count -eq 0) {
            $finding.Status = 'Historical'
            $finding.DispositionReason = 'A later milestone proves that the configured target build is currently running; this setup-attempt failure is retained as historical evidence.'
        }
    }
}

function Select-WudPrimaryFinding {
    param($Context)
    $ranked = @($Context.Findings | Where-Object { $_.Status -ne 'Historical' } | Sort-Object `
        @{ Expression = { Get-WudSeverityRank $_.Severity }; Descending = $true },
        @{ Expression = { Get-WudConfidenceRank $_.Confidence }; Descending = $true },
        @{ Expression = { if ($_.Id -eq 'WUD-SETUP-FATAL') { 1 } else { 0 } }; Descending = $true },
        @{ Expression = { $_.LastSeenUtc }; Descending = $true })
    return @($ranked | Where-Object { $_.Severity -ne 'Information' } | Select-Object -First 1)
}

function Invoke-WudAnalysis {
    param([Parameter(Mandatory = $true)]$Context)
    Write-WudLog -Context $Context -Level INFO -Message 'Analyzing and correlating collected evidence.'
    foreach ($attempt in @(Get-WudAttemptInventory -Context $Context)) { $null = $Context.Attempts.Add($attempt) }
    Add-WudRuleFindings -Context $Context
    Enhance-WudFindingsFromSetupDiag -Context $Context
    Add-WudStructuredCompatibilityFindings -Context $Context
    Add-WudInventoryFindings -Context $Context
    Apply-WudLaterSuccessSuppression -Context $Context
    Add-WudTimelineFromLogs -Context $Context
    $comparison = Get-WudSnapshotComparison -Context $Context
    $Context.Inventory = [ordered]@{ Baseline = $comparison.Baseline; Current = $comparison.Current; Diff = $comparison.Diff }
    $primary = Select-WudPrimaryFinding -Context $Context
    if (@($primary).Count -gt 0) { $Context.PrimaryFinding = $primary[0] }
    $Context.Outcome = Resolve-WudOutcome -Context $Context
    $Context.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $Context.ExitCode = Resolve-WudExitCode -Context $Context
    $analysis = [pscustomobject][ordered]@{
        SchemaVersion   = 1
        RunId           = $Context.RunId
        ToolVersion     = $Context.ToolVersion
        Mode            = $Context.Mode
        PhaseLabel      = $Context.PhaseLabel
        Outcome         = $Context.Outcome
        ExitCode        = $Context.ExitCode
        PrimaryFinding  = $Context.PrimaryFinding
        Findings        = @($Context.Findings)
        Timeline        = @($Context.Timeline)
        Attempts        = @($Context.Attempts)
        CollectorRecords = @($Context.CollectorRecords)
        Inventory       = $Context.Inventory
        StartedUtc      = $Context.StartedUtc
        CompletedUtc    = $Context.CompletedUtc
    }
    Write-WudJsonAtomic -Path (Join-Path $Context.RunPath 'analysis.json') -InputObject $analysis -Depth 40
    return $analysis
}

Export-ModuleMember -Function @('Invoke-WudAnalysis', 'Get-WudPhaseOperation', 'Get-WudCodesFromText', 'ConvertTo-WudLogTimestamp', 'New-WudFindingObject')
