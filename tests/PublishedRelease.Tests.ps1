$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'release\manifest.json'

Assert-SysInTrue (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'release manifest exists for published-byte verification'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('sysin-published-release-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

try {
    foreach ($entry in @($manifest.files)) {
        $relative = ([string]$entry.target).Replace('/','\')
        $destination = Join-Path $workRoot $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        Invoke-WebRequest -Uri ([string]$entry.url) -OutFile $destination -UseBasicParsing -ErrorAction Stop
        $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $expected = ([string]$entry.sha256).ToLowerInvariant()
        Write-Host ("PUBLISHED_HASH|{0}|{1}" -f $relative,$actual)
        Assert-SysInEqual $actual $expected "published SHA-256 matches manifest for: $relative"
    }
} finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}
