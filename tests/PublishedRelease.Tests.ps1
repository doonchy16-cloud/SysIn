$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'release\manifest.json'

Assert-SysInTrue (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'release manifest exists for published-byte verification'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('sysin-published-release-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$mismatches = New-Object System.Collections.Generic.List[string]

try {
    foreach ($entry in @($manifest.files)) {
        $relative = ([string]$entry.target).Replace('/','\')
        $destination = Join-Path $workRoot $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        $downloadUri = [string]$entry.url
        if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -and $env:GITHUB_REF_NAME -ne 'main') {
            $downloadUri = $downloadUri.Replace('/main/', "/$($env:GITHUB_SHA)/")
        }

        Invoke-WebRequest -Uri $downloadUri -OutFile $destination -UseBasicParsing -ErrorAction Stop
        $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $expected = ([string]$entry.sha256).ToLowerInvariant()
        Write-Host ("PUBLISHED_HASH|{0}|{1}|{2}" -f $relative,$actual,$downloadUri)
        if ($actual -ne $expected) {
            $mismatches.Add(("{0}: expected {1}, published {2}" -f $relative,$expected,$actual))
        }
    }

    Assert-SysInEqual $mismatches.Count 0 ("all published runtime SHA-256 values match the release manifest`n" + ($mismatches -join "`n"))
} finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}
