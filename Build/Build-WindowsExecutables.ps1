[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string[]]$RuntimeIdentifiers = @('win-x64', 'win-arm64'),
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$RuntimeIdentifiers = @($RuntimeIdentifiers | ForEach-Object { @([string]$_ -split ',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$toolRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $toolRoot 'dist' }
$version = (Get-Content -LiteralPath (Join-Path $toolRoot 'VERSION') -Raw).Trim()
& (Join-Path $PSScriptRoot 'Update-BundleManifest.ps1') -Verify
if ($LASTEXITCODE -ne 0) { throw 'Bundle manifest verification failed.' }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw '.NET SDK 8 or later is required to build the GUI executable.' }
$null = New-Item -ItemType Directory -Path $OutputPath -Force

$records = New-Object Collections.ArrayList
foreach ($runtime in $RuntimeIdentifiers) {
    $publishPath = Join-Path $OutputPath ("publish-{0}" -f $runtime)
    if (Test-Path -LiteralPath $publishPath) { Remove-Item -LiteralPath $publishPath -Recurse -Force }
    & dotnet publish (Join-Path $toolRoot 'Gui\WindowsUpdateAnalytics.Gui.csproj') --configuration $Configuration --runtime $runtime --self-contained true -p:PublishSingleFile=true -p:DebugType=None -p:DebugSymbols=false --output $publishPath
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed for $runtime." }
    $source = Join-Path $publishPath 'WUPA.exe'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Published executable was not found for $runtime." }
    $destination = Join-Path $OutputPath ("WUPA-{0}-{1}.exe" -f $version, $runtime)
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $item = Get-Item -LiteralPath $destination
    $null = $records.Add([pscustomobject][ordered]@{
        Name = $item.Name
        Runtime = $runtime
        Version = $version
        Length = $item.Length
        Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    })
    Remove-Item -LiteralPath $publishPath -Recurse -Force
}
$records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputPath 'WUPA-build.json') -Encoding UTF8
@($records | ForEach-Object { '{0}  {1}' -f $_.Sha256, $_.Name }) | Set-Content -LiteralPath (Join-Path $OutputPath 'Checksums.sha256') -Encoding Ascii
$records | Format-Table -AutoSize
