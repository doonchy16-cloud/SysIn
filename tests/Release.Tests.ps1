$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'release\manifest.json'
$runtimeFiles = @(
    'SysIn.cmd',
    'src\SysIn.ps1',
    'src\SysIn.Core.psm1',
    'src\SysIn.Config.psm1',
    'src\SysIn.Update.psm1',
    'uninstall.ps1'
)

$actualHashes = @{}
foreach ($relative in $runtimeFiles) {
    $path = Join-Path $repoRoot $relative
    Assert-SysInTrue (Test-Path -LiteralPath $path -PathType Leaf) "release runtime file exists: $relative"
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $actualHashes[$relative.ToLowerInvariant()] = $hash
    Write-Host ("RELEASE_HASH|{0}|{1}" -f $relative,$hash)
}

Assert-SysInTrue (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'release/manifest.json exists'

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "release/manifest.json must contain valid JSON: $($_.Exception.Message)"
}

Assert-SysInEqual ([string]$manifest.product) 'SysIn' 'release manifest product is SysIn'
Assert-SysInEqual ([string]$manifest.version) '1.1.0' 'release manifest version is 1.1.0'
Assert-SysInEqual ([string]$manifest.channel) 'stable' 'release manifest channel is stable'
Assert-SysInEqual ([string]$manifest.minimumPowerShell) '5.1' 'release manifest minimum PowerShell is 5.1'

$entries = @($manifest.files)
Assert-SysInEqual $entries.Count $runtimeFiles.Count 'release manifest contains exactly the known V1.1 runtime files'

$entryByTarget = @{}
foreach ($entry in $entries) {
    $target = ([string]$entry.target).Replace('/','\')
    Assert-SysInTrue (-not [string]::IsNullOrWhiteSpace($target)) 'release manifest target is non-empty'
    $key = $target.ToLowerInvariant()
    Assert-SysInTrue (-not $entryByTarget.ContainsKey($key)) "release manifest target is unique: $target"
    $entryByTarget[$key] = $entry
}

foreach ($relative in $runtimeFiles) {
    $key = $relative.ToLowerInvariant()
    Assert-SysInTrue $entryByTarget.ContainsKey($key) "release manifest contains runtime target: $relative"
    $entry = $entryByTarget[$key]
    $urlPath = $relative.Replace('\','/')
    $expectedUrl = "https://raw.githubusercontent.com/doonchy16-cloud/SysIn/main/$urlPath"
    Assert-SysInEqual ([string]$entry.url) $expectedUrl "release URL points to canonical main runtime file: $relative"
    Assert-SysInEqual ([string]$entry.sha256).ToLowerInvariant() $actualHashes[$key] "release SHA-256 matches runtime file: $relative"
}
