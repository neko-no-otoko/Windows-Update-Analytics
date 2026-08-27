@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "WUD_PREP_ROOT=%~dp0"
set "WUD_PREP_MODE=%~1"
set "WUD_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if defined PROCESSOR_ARCHITEW6432 (
  set "WUD_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

if not exist "%WUD_PS%" (
  echo Windows PowerShell could not be found.
  exit /b 50
)

"%WUD_PS%" -NoProfile -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "try {" ^
  "  $root = [IO.Path]::GetFullPath($env:WUD_PREP_ROOT).TrimEnd('\');" ^
  "  $mode = [string]$env:WUD_PREP_MODE;" ^
  "  $manifest = Join-Path $root 'BundleManifest.sha256';" ^
  "  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'BundleManifest.sha256 is missing.' };" ^
  "  $rootPrefix = $root + '\';" ^
  "  $verified = 0;" ^
  "  foreach ($line in Get-Content -LiteralPath $manifest) {" ^
  "    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue };" ^
  "    $match = [regex]::Match($line, '^([A-Fa-f0-9]{64})\s+\*?(.+)$');" ^
  "    if (-not $match.Success) { throw ('Malformed bundle manifest line: ' + $line) };" ^
  "    $relative = $match.Groups[2].Value.Trim();" ^
  "    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw ('Unsafe bundle manifest path: ' + $relative) };" ^
  "    $candidate = [IO.Path]::GetFullPath((Join-Path $root $relative));" ^
  "    if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw ('Bundle manifest path leaves the package: ' + $relative) };" ^
  "    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw ('Bundle file is missing: ' + $relative) };" ^
  "    $expected = $match.Groups[1].Value.ToLowerInvariant();" ^
  "    $stream = [IO.File]::Open($candidate, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read);" ^
  "    try { $sha = [Security.Cryptography.SHA256]::Create(); try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() } } finally { $stream.Dispose() };" ^
  "    if ($actual -ne $expected) { throw ('Bundle integrity check failed for: ' + $relative) };" ^
  "    $verified++;" ^
  "  };" ^
  "  if ($verified -eq 0) { throw 'BundleManifest.sha256 contains no file entries.' };" ^
  "  Write-Host ('Bundle integrity verified: {0} files.' -f $verified) -ForegroundColor Green;" ^
  "  $policyRows = @(Get-ExecutionPolicy -List);" ^
  "  $policyMap = @{};" ^
  "  foreach ($row in $policyRows) { $policyMap[[string]$row.Scope] = [string]$row.ExecutionPolicy };" ^
  "  $groupPolicyScope = $null;" ^
  "  $groupPolicyValue = $null;" ^
  "  foreach ($scope in @('MachinePolicy', 'UserPolicy')) {" ^
  "    if ($policyMap.ContainsKey($scope) -and $policyMap[$scope] -ne 'Undefined') { $groupPolicyScope = $scope; $groupPolicyValue = $policyMap[$scope]; break };" ^
  "  };" ^
  "  if ($groupPolicyValue -in @('AllSigned', 'Restricted')) {" ^
  "    Write-Host ('PowerShell {0} enforces {1}.' -f $groupPolicyScope, $groupPolicyValue) -ForegroundColor Red;" ^
  "    if ($groupPolicyValue -eq 'AllSigned') { Write-Host 'This unsigned bundle requires an enterprise code-signing certificate trusted by the device. Removing a download marker cannot satisfy AllSigned.' -ForegroundColor Red }" ^
  "    else { Write-Host 'This policy does not permit PowerShell script files. Use an organization-approved deployment or policy path.' -ForegroundColor Red };" ^
  "    Write-Host 'No execution policy was changed.' -ForegroundColor Yellow;" ^
  "    exit 50;" ^
  "  };" ^
  "  $blocked = New-Object Collections.Generic.List[object];" ^
  "  foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop)) {" ^
  "    if (@(Get-Item -LiteralPath $file.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue).Count -gt 0) { $blocked.Add($file) };" ^
  "  };" ^
  "  if ($blocked.Count -eq 0) {" ^
  "    Write-Host 'No Internet-zone download markers were found in the bundle.';" ^
  "    exit 0;" ^
  "  };" ^
  "  if ($mode -ieq '-Check') {" ^
  "    Write-Host ('Internet-zone download markers detected on {0} bundle files.' -f $blocked.Count) -ForegroundColor Yellow;" ^
  "    exit 10;" ^
  "  };" ^
  "  Write-Host '';" ^
  "  Write-Host ('This verified bundle contains {0} files marked as downloaded from the Internet.' -f $blocked.Count) -ForegroundColor Yellow;" ^
  "  Write-Host 'Preparation removes only the Zone.Identifier stream from files inside this bundle.';" ^
  "  Write-Host 'It does not change PowerShell execution policy, Group Policy, AppLocker, WDAC, or Defender settings.';" ^
  "  if ($mode -ine '-Apply') {" ^
  "    $confirmation = Read-Host 'After confirming the ZIP came from your approved source, type UNBLOCK to continue';" ^
  "    if ($confirmation -cne 'UNBLOCK') { Write-Host 'Bundle preparation was cancelled. No file markers were changed.' -ForegroundColor Yellow; exit 50 };" ^
  "  };" ^
  "  foreach ($file in $blocked) { Unblock-File -LiteralPath $file.FullName -ErrorAction Stop };" ^
  "  $remaining = New-Object Collections.Generic.List[string];" ^
  "  foreach ($file in $blocked) {" ^
  "    if (@(Get-Item -LiteralPath $file.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue).Count -gt 0) { $remaining.Add($file.FullName) };" ^
  "  };" ^
  "  if ($remaining.Count -gt 0) { throw ('Download markers remain on {0} files.' -f $remaining.Count) };" ^
  "  Write-Host ('Prepared bundle: removed Internet-zone markers from {0} files.' -f $blocked.Count) -ForegroundColor Green;" ^
  "  Write-Host 'No execution policy was changed.';" ^
  "  exit 0;" ^
  "}" ^
  "catch {" ^
  "  Write-Host ('Bundle preparation failed: ' + $_.Exception.Message) -ForegroundColor Red;" ^
  "  Write-Host 'No execution policy was changed.' -ForegroundColor Yellow;" ^
  "  exit 40;" ^
  "}"

exit /b %ERRORLEVEL%
