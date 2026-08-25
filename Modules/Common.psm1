Set-StrictMode -Version 2.0

function Test-WudIsWindows {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Test-WudAdministrator {
    if (-not (Test-WudIsWindows)) { return $false }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-WudInteractiveUser {
    if (-not [Environment]::UserInteractive) { return $false }
    if (-not (Test-WudIsWindows)) { return $true }
    try {
        return ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18')
    }
    catch { return $false }
}

function Get-WudCurrentUserSid {
    if (-not (Test-WudIsWindows)) { return $null }
    try { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    catch { return $null }
}

function New-WudDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
    return (Get-Item -LiteralPath $Path).FullName
}

function Read-WudJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json)
}

function Write-WudJsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$InputObject,
        [int]$Depth = 30
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { $null = New-WudDirectory -Path $parent }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $json = $InputObject | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-WudText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Text,
        [ValidateSet('Utf8', 'Ascii')][string]$Encoding = 'Utf8'
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { $null = New-WudDirectory -Path $parent }
    $encoder = if ($Encoding -eq 'Ascii') { [Text.Encoding]::ASCII } else { New-Object Text.UTF8Encoding($false) }
    [IO.File]::WriteAllText($Path, $Text, $encoder)
}

function Get-WudTargetDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$ToolRoot,
        [Parameter(Mandatory = $true)][string]$TargetVersion
    )
    $catalog = Read-WudJson -Path (Join-Path $ToolRoot 'Data/targets.json')
    $target = @($catalog.targets | Where-Object { $_.displayVersion -eq $TargetVersion }) | Select-Object -First 1
    if (-not $target) { throw "Target version '$TargetVersion' is not defined in Data\targets.json." }
    return $target
}

function New-WudRunContext {
    param(
        [Parameter(Mandatory = $true)][string]$ToolRoot,
        [Parameter(Mandatory = $true)][string]$ToolVersion,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$RunPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$PhaseLabel,
        [Parameter(Mandatory = $true)][string]$TargetVersion,
        [string]$CopyTo,
        [string]$MediaPath,
        [bool]$AcceptWindowsEula,
        [bool]$IncludeLargeDumps,
        [bool]$NoInternet,
        [bool]$NoSetupHooks,
        [int]$ArmDays
    )
    $settings = Read-WudJson -Path (Join-Path $ToolRoot 'Data/settings.json')
    $target = Get-WudTargetDefinition -ToolRoot $ToolRoot -TargetVersion $TargetVersion
    $null = New-WudDirectory -Path $RunPath
    $evidencePath = New-WudDirectory -Path (Join-Path $RunPath 'Evidence')
    $snapshotPath = New-WudDirectory -Path (Join-Path $evidencePath $PhaseLabel)
    $null = New-WudDirectory -Path $OutputPath

    return [pscustomobject][ordered]@{
        SchemaVersion       = 1
        ToolVersion        = $ToolVersion
        ToolRoot           = $ToolRoot
        RunId              = $RunId
        RunPath            = $RunPath
        EvidencePath       = $evidencePath
        SnapshotPath       = $snapshotPath
        OutputPath         = $OutputPath
        Mode               = $Mode
        PhaseLabel         = $PhaseLabel
        TargetVersion      = $TargetVersion
        Target             = $target
        Settings           = $settings
        CopyTo             = $CopyTo
        MediaPath          = $MediaPath
        AcceptWindowsEula  = $AcceptWindowsEula
        IncludeLargeDumps  = $IncludeLargeDumps
        NoInternet         = $NoInternet
        NoSetupHooks       = $NoSetupHooks
        ArmDays            = $ArmDays
        StartedUtc         = [DateTime]::UtcNow.ToString('o')
        CompletedUtc       = $null
        LogPath            = (Join-Path $RunPath 'Collector.log')
        CollectorRecords   = New-Object Collections.ArrayList
        ProcessRecords     = New-Object Collections.ArrayList
        CollectionGaps     = New-Object Collections.ArrayList
        Findings           = New-Object Collections.ArrayList
        Timeline           = New-Object Collections.ArrayList
        Inventory          = [ordered]@{}
        Attempts           = New-Object Collections.ArrayList
        CollectionComplete = $true
        LastCopyResult     = $null
        Outcome            = 'Unknown'
        PrimaryFinding     = $null
        ExitCode           = 0
    }
}

function Write-WudLog {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )
    $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $Level, $Message
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN' { 'Yellow' }
        'DEBUG' { 'DarkGray' }
        default { 'Gray' }
    }
    try { Write-Host $line -ForegroundColor $color }
    catch { Write-Output $line }
    try {
        $parent = Split-Path -Parent $Context.LogPath
        if ($parent) { $null = New-WudDirectory -Path $parent }
        [IO.File]::AppendAllText($Context.LogPath, $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    }
    catch { }
}

function ConvertTo-WudCommandLineArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function ConvertTo-WudCsvCell {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -isnot [string]) { return $Value }
    # Excel and similar spreadsheet applications can execute formula-like CSV
    # fields. Preserve the visible value while forcing text interpretation.
    if ($Value -match '^[\t\r\n ]*[=+\-@]') { return "'$Value" }
    return $Value
}

function Add-WudCollectionGap {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Collector,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Detail,
        [ValidateSet('Optional', 'Material')][string]$Impact = 'Optional'
    )
    $gap = [pscustomobject][ordered]@{
        Collector  = $Collector
        Source     = $Source
        Status     = $Status
        Detail     = $Detail
        Impact     = $Impact
        RecordedUtc = [DateTime]::UtcNow.ToString('o')
    }
    if ($Context.PSObject.Properties['CollectionGaps']) { $null = $Context.CollectionGaps.Add($gap) }
    if ($Impact -eq 'Material') { $Context.CollectionComplete = $false }
    return $gap
}

function Invoke-WudProcess {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TimeoutSeconds = 600,
        [int[]]$SuccessExitCodes = @(0),
        [string]$WorkingDirectory
    )
    $commandPath = New-WudDirectory -Path (Join-Path $Context.SnapshotPath 'Commands')
    $safeName = ($Name -replace '[^A-Za-z0-9._-]', '_')
    $stdoutPath = Join-Path $commandPath ($safeName + '.stdout.txt')
    $stderrPath = Join-Path $commandPath ($safeName + '.stderr.txt')
    $argumentLine = (($ArgumentList | ForEach-Object { ConvertTo-WudCommandLineArgument -Value ([string]$_) }) -join ' ')
    $started = [DateTime]::UtcNow
    Write-WudLog -Context $Context -Level INFO -Message ("Running {0}" -f $Name)
    $process = $null
    $timedOut = $false
    $errorMessage = $null
    $exitCode = $null
    try {
        $parameters = @{
            FilePath               = $FilePath
            ArgumentList           = $argumentLine
            PassThru               = $true
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError  = $stderrPath
        }
        if ($WorkingDirectory) { $parameters.WorkingDirectory = $WorkingDirectory }
        $process = Start-Process @parameters
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.HasExited) {
            if ([DateTime]::UtcNow -ge $deadline) {
                $timedOut = $true
                try { Stop-Process -Id $process.Id -Force -ErrorAction Stop }
                catch { }
                break
            }
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }
        try { $process.WaitForExit() } catch { }
        if (-not $timedOut) { $exitCode = $process.ExitCode }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-WudText -Path $stderrPath -Text $errorMessage
    }
    $ended = [DateTime]::UtcNow
    $succeeded = (-not $timedOut) -and ($null -ne $exitCode) -and ($SuccessExitCodes -contains [int]$exitCode)
    $result = [pscustomobject][ordered]@{
        Name          = $Name
        FilePath      = $FilePath
        Arguments     = $ArgumentList
        StartedUtc    = $started.ToString('o')
        EndedUtc      = $ended.ToString('o')
        DurationMs    = [int]($ended - $started).TotalMilliseconds
        ExitCode      = $exitCode
        ExitCodeHex   = if ($null -ne $exitCode) { '0x{0:X8}' -f ([long]$exitCode -band 0xFFFFFFFFL) } else { $null }
        TimedOut      = $timedOut
        Succeeded     = $succeeded
        StandardOut  = $stdoutPath
        StandardError = $stderrPath
        Error         = $errorMessage
    }
    Write-WudJsonAtomic -Path (Join-Path $commandPath ($safeName + '.result.json')) -InputObject $result
    if ($Context.PSObject.Properties['ProcessRecords']) { $null = $Context.ProcessRecords.Add($result) }
    if ($timedOut) { Write-WudLog -Context $Context -Level WARN -Message "$Name exceeded its $TimeoutSeconds second limit and was stopped." }
    elseif ($errorMessage) { Write-WudLog -Context $Context -Level WARN -Message "$Name could not start: $errorMessage" }
    elseif (-not $succeeded) { Write-WudLog -Context $Context -Level WARN -Message "$Name returned $exitCode ($($result.ExitCodeHex))." }
    return $result
}

function Invoke-WudCollector {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [bool]$Required = $false
    )
    $started = [DateTime]::UtcNow
    $processRecordStart = if ($Context.PSObject.Properties['ProcessRecords']) { @($Context.ProcessRecords).Count } else { 0 }
    $status = 'Succeeded'
    $detail = $null
    Write-WudLog -Context $Context -Level INFO -Message ("Collector {0}: {1}" -f $Id, $Description)
    try {
        & $ScriptBlock
    }
    catch {
        $status = 'Failed'
        $detail = $_.Exception.Message
        if ($Required) { $Context.CollectionComplete = $false }
        Write-WudLog -Context $Context -Level WARN -Message ("Collector {0} failed: {1}" -f $Id, $detail)
    }
    if ($status -eq 'Succeeded' -and $Context.PSObject.Properties['ProcessRecords']) {
        $newProcessRecords = @($Context.ProcessRecords | Select-Object -Skip $processRecordStart)
        $timedOut = @($newProcessRecords | Where-Object TimedOut)
        $unsuccessful = @($newProcessRecords | Where-Object { -not $_.Succeeded -and -not $_.TimedOut })
        if (@($timedOut).Count -gt 0) {
            $status = 'TimedOut'
            $detail = 'Timed out: ' + (@($timedOut | ForEach-Object Name) -join ', ')
            if ($Required) { $Context.CollectionComplete = $false }
            $null = Add-WudCollectionGap -Context $Context -Collector $Id -Source (@($timedOut | ForEach-Object FilePath) -join '; ') -Status 'TimedOut' -Detail $detail -Impact $(if ($Required) { 'Material' } else { 'Optional' })
        }
        elseif (@($unsuccessful).Count -gt 0) {
            $status = 'CompletedWithWarnings'
            $detail = 'Non-success process result: ' + (@($unsuccessful | ForEach-Object { '{0} ({1})' -f $_.Name, $_.ExitCodeHex }) -join ', ')
        }
    }
    $ended = [DateTime]::UtcNow
    $record = [pscustomobject][ordered]@{
        Id          = $Id
        Version     = $Context.ToolVersion
        Description = $Description
        Required    = $Required
        Status      = $status
        Detail      = $detail
        StartedUtc  = $started.ToString('o')
        EndedUtc    = $ended.ToString('o')
        DurationMs  = [int]($ended - $started).TotalMilliseconds
    }
    $null = $Context.CollectorRecords.Add($record)
    return $record
}

function Add-WudFinding {
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Finding)
    $existing = @($Context.Findings | Where-Object { $_.Id -eq $Finding.Id -and $_.InstanceKey -eq $Finding.InstanceKey }) | Select-Object -First 1
    if ($existing) {
        foreach ($evidence in @($Finding.Evidence)) {
            if (-not (@($existing.Evidence | Where-Object { $_.Reference -eq $evidence.Reference }).Count)) {
                $null = $existing.Evidence.Add($evidence)
            }
        }
        return $existing
    }
    if (-not $Finding.PSObject.Properties['Evidence']) {
        $Finding | Add-Member -NotePropertyName Evidence -NotePropertyValue (New-Object Collections.ArrayList)
    }
    $null = $Context.Findings.Add($Finding)
    return $Finding
}

function Add-WudTimelineEvent {
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Event)
    $null = $Context.Timeline.Add($Event)
}

function Get-WudRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )
    try {
        $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $pathFull = [IO.Path]::GetFullPath($Path)
        $baseUri = New-Object Uri($baseFull)
        $pathUri = New-Object Uri($pathFull)
        return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', [IO.Path]::DirectorySeparatorChar)
    }
    catch { return $Path }
}

function Get-WudFileHashSafe {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
    catch { return $null }
}

function Get-WudFileInventory {
    param([Parameter(Mandatory = $true)][string]$RootPath)
    $items = New-Object Collections.ArrayList
    if (-not (Test-Path -LiteralPath $RootPath)) { return @() }
    foreach ($file in Get-ChildItem -LiteralPath $RootPath -File -Recurse -Force -ErrorAction SilentlyContinue) {
        $item = [pscustomobject][ordered]@{
            RelativePath = Get-WudRelativePath -BasePath $RootPath -Path $file.FullName
            StagedPath   = $file.FullName
            Length       = $file.Length
            LastWriteUtc = $file.LastWriteTimeUtc.ToString('o')
            Sha256       = Get-WudFileHashSafe -Path $file.FullName
        }
        $null = $items.Add($item)
    }
    return @($items)
}

function Export-WudRegistryTree {
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [int]$MaximumDepth = 8
    )
    $records = New-Object Collections.ArrayList
    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        Write-WudJsonAtomic -Path $OutputPath -InputObject @()
        return @()
    }
    $rootDepth = ($RegistryPath -split '[\\/]').Count
    $keys = @((Get-Item -LiteralPath $RegistryPath -ErrorAction Stop)) + @(Get-ChildItem -LiteralPath $RegistryPath -Recurse -ErrorAction SilentlyContinue)
    foreach ($key in $keys) {
        $depth = (($key.PSPath -split '[\\/]').Count - $rootDepth)
        if ($depth -gt $MaximumDepth) { continue }
        $values = [ordered]@{}
        try {
            $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            foreach ($property in $properties.PSObject.Properties) {
                if ($property.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$') {
                    $value = $property.Value
                    if ($value -is [byte[]]) { $value = [Convert]::ToBase64String($value) }
                    $values[$property.Name] = $value
                }
            }
        }
        catch { }
        $null = $records.Add([pscustomobject][ordered]@{ Path = $key.Name; Values = $values })
    }
    Write-WudJsonAtomic -Path $OutputPath -InputObject @($records)
    return @($records)
}

function ConvertTo-WudByteSize {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-WudSeverityRank {
    param([string]$Severity)
    switch ($Severity) {
        'Blocker' { return 4 }
        'Error' { return 3 }
        'Warning' { return 2 }
        default { return 1 }
    }
}

function Get-WudConfidenceRank {
    param([string]$Confidence)
    switch ($Confidence) {
        'High' { return 3 }
        'Medium' { return 2 }
        default { return 1 }
    }
}

function Resolve-WudExitCode {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not $Context.CollectionComplete) { return 30 }
    if (@($Context.Findings | Where-Object { $_.Status -ne 'Historical' -and $_.Severity -in @('Blocker', 'Error') }).Count -gt 0 -or $Context.Outcome -in @('Blocked', 'Rolled Back', 'Failed')) { return 20 }
    if (@($Context.Findings | Where-Object { $_.Status -ne 'Historical' -and $_.Severity -eq 'Warning' }).Count -gt 0 -or $Context.Outcome -eq 'Attention Required') { return 10 }
    return 0
}

Export-ModuleMember -Function @(
    'Test-WudIsWindows', 'Test-WudAdministrator', 'Test-WudInteractiveUser', 'Get-WudCurrentUserSid',
    'New-WudDirectory', 'Read-WudJson', 'Write-WudJsonAtomic', 'Write-WudText', 'Get-WudTargetDefinition',
    'New-WudRunContext', 'Write-WudLog', 'Invoke-WudProcess', 'Invoke-WudCollector', 'Add-WudFinding',
    'Add-WudTimelineEvent', 'Get-WudRelativePath', 'Get-WudFileHashSafe', 'Get-WudFileInventory',
    'Export-WudRegistryTree', 'ConvertTo-WudByteSize', 'Get-WudSeverityRank', 'Get-WudConfidenceRank',
    'Resolve-WudExitCode', 'ConvertTo-WudCommandLineArgument', 'ConvertTo-WudCsvCell', 'Add-WudCollectionGap'
)
