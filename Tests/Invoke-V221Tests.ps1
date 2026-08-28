[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$toolRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Assert-WudV221 {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$version = (Get-Content -LiteralPath (Join-Path $toolRoot 'VERSION') -Raw).Trim()
$entrySource = Get-Content -LiteralPath (Join-Path $toolRoot 'Invoke-Win11UpgradeDiag.ps1') -Raw
$programSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Gui/Program.cs') -Raw
$collectorSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Collectors.psm1') -Raw
$analysisSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Analysis.psm1') -Raw
$reviewSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Review.psm1') -Raw
$reportSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Report.psm1') -Raw

Assert-WudV221 ($version -eq '2.2.1' -and $entrySource -match '\$toolVersion\s*=\s*''2\.2\.1''' -and $programSource -match 'AppVersion\s*=\s*"2\.2\.1"') 'Tool, backend, and GUI versions identify v2.2.1'
Assert-WudV221 ($programSource -match 'Automatic post-reboot finalization is already running' -and $programSource -match 'Automatic finalization running') 'GUI describes a held run as automatic post-reboot finalization instead of a report result'
Assert-WudV221 ($programSource -match 'Path\.Combine\(RunPath, "State", "run\.lock"\)' -and $programSource -match 'FileShare\.None' -and $programSource -match 'catch \(IOException\) \{ return RunLockStatus\.Held; \}') 'GUI detects actual exclusive run-lock ownership rather than treating the lock file itself as activity'
Assert-WudV221 ($programSource -match 'Path\.Combine\(RunPath, "Collector\.log"\)' -and $programSource -match 'FileShare\.ReadWrite \| FileShare\.Delete' -and $programSource -match 'LastOrDefault\(CollectorLogStatus\.IsStructured\)' -and $programSource -match 'Last Collector\.log status') 'GUI safely tails the actively written Collector.log and displays its newest structured status message'
Assert-WudV221 ($programSource -match '_stateTimer\.Interval = 5000' -and $programSource -match '_finalize\.Enabled = !_busy && runLockStatus == RunLockStatus\.NotHeld') 'GUI refreshes status every five seconds and blocks duplicate finalization while a run is owned'
Assert-WudV221 ($programSource -match 'RunLockCollision' -and $programSource -match 'backend\.RunLockCollision' -and $programSource -match 'Collection finished without a report') 'GUI handles a lock race and never labels a no-report backend exit as Report created'
Assert-WudV221 ($entrySource -match 'Wait for the active pass to finish; do not delete State\\run\.lock') 'Backend lock collision message gives safe operator guidance'

Assert-WudV221 ($collectorSource -notmatch 'Invoke-WudCollector \$Context ''software''' -and $collectorSource -notmatch 'Invoke-WudSoftwareCollector' -and $collectorSource -notmatch 'Get-AppxPackage -AllUsers') 'Broad installed-software collector is removed from the collection path'
Assert-WudV221 ($collectorSource -match "CollectionStatus\s*=\s*'DisabledByDesign'" -and $collectorSource -match 'Compatibility Appraiser evidence can still identify source-reported application blocks') 'Inventory records explicitly disclose that broad software collection is disabled'
Assert-WudV221 ($analysisSource -match 'Test-WudSoftwareInventoryCollected' -and $analysisSource -match 'Broad installed-software inventory is disabled by design') 'Pre/post analysis cannot misreport every application as removed across the v2.2.1 boundary'
Assert-WudV221 ($reviewSource -match 'SoftwareCollection' -and $reviewSource -match 'disabled by design' -and $reportSource -match 'Software inventory</div><div class="metric-value">Not collected') 'Normalized review and HTML report disclose unavailable software inventory instead of reporting zero applications'

Write-Host 'All v2.2.1 regression tests passed.' -ForegroundColor Cyan
