$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src\SysIn.Update.psm1'
Import-Module $modulePath -Force

Assert-SysInEqual (Compare-SysInVersion '1.1.0' '1.2.0') -1 'older local version compares lower'
Assert-SysInEqual (Compare-SysInVersion '1.1.0' '1.1.0') 0 'equal semantic versions compare equal'
Assert-SysInEqual (Compare-SysInVersion '2.0.0' '1.9.9') 1 'newer local version compares higher'
Assert-SysInThrows { Compare-SysInVersion 'banana' '1.1.0' } 'invalid semantic version is rejected'

$validManifest = [pscustomobject]@{
    product = 'SysIn'
    version = '1.2.0'
    channel = 'stable'
    minimumPowerShell = '5.1'
    files = @(
        [pscustomobject]@{
            target = 'src/SysIn.ps1'
            url = 'https://raw.githubusercontent.com/doonchy16-cloud/SysIn/main/src/SysIn.ps1'
            sha256 = ('a' * 64)
        }
    )
}
Assert-SysInTrue (Test-SysInManifest $validManifest) 'well-formed stable manifest is accepted'

$badHash = $validManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$badHash.files[0].sha256 = 'abc'
Assert-SysInThrows { Test-SysInManifest $badHash } 'invalid SHA-256 is rejected'

$httpManifest = $validManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$httpManifest.files[0].url = 'http://example.com/SysIn.ps1'
Assert-SysInThrows { Test-SysInManifest $httpManifest } 'non-HTTPS runtime URL is rejected'

$traversalManifest = $validManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$traversalManifest.files[0].target = '../escape.ps1'
Assert-SysInThrows { Test-SysInManifest $traversalManifest } 'path traversal target is rejected'

$wrongProduct = $validManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$wrongProduct.product = 'NotSysIn'
Assert-SysInThrows { Test-SysInManifest $wrongProduct } 'wrong product manifest is rejected'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sysin-update-test-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $tempRoot 'install'
$payloadRoot = Join-Path $tempRoot 'payload'
New-Item -ItemType Directory -Path (Join-Path $installRoot 'src') -Force | Out-Null
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

try {
    $installedFile = Join-Path $installRoot 'src\SysIn.ps1'
    $payloadFile = Join-Path $payloadRoot 'SysIn.ps1'
    [IO.File]::WriteAllText($installedFile, 'old-version')
    [IO.File]::WriteAllText($payloadFile, 'new-version')
    $payloadHash = (Get-FileHash -LiteralPath $payloadFile -Algorithm SHA256).Hash.ToLowerInvariant()

    $manifest = [pscustomobject]@{
        product='SysIn'; version='1.2.0'; channel='stable'; minimumPowerShell='5.1'
        files=@([pscustomobject]@{ target='src/SysIn.ps1'; url='https://example.invalid/SysIn.ps1'; sha256=$payloadHash })
    }
    $downloader = { param($Url,$Destination) Copy-Item -LiteralPath $payloadFile -Destination $Destination -Force }

    $same = Invoke-SysInUpdate -CurrentVersion '1.2.0' -InstallRoot $installRoot -ManifestObject $manifest -Downloader $downloader
    Assert-SysInEqual $same.Status 'UpToDate' 'equal version is a no-op'
    Assert-SysInEqual ([IO.File]::ReadAllText($installedFile)) 'old-version' 'no-op does not replace files'

    $badManifest = $manifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $badManifest.files[0].sha256 = ('b' * 64)
    Assert-SysInThrows { Invoke-SysInUpdate -CurrentVersion '1.1.0' -InstallRoot $installRoot -ManifestObject $badManifest -Downloader $downloader } 'hash mismatch aborts update'
    Assert-SysInEqual ([IO.File]::ReadAllText($installedFile)) 'old-version' 'hash mismatch leaves install untouched'

    $ok = Invoke-SysInUpdate -CurrentVersion '1.1.0' -InstallRoot $installRoot -ManifestObject $manifest -Downloader $downloader
    Assert-SysInEqual $ok.Status 'Updated' 'verified newer payload updates successfully'
    Assert-SysInEqual ([IO.File]::ReadAllText($installedFile)) 'new-version' 'verified file replaces installed file'

    [IO.File]::WriteAllText($installedFile, 'old-again')
    $twoPayload = Join-Path $payloadRoot 'Second.psm1'
    [IO.File]::WriteAllText($twoPayload, 'second-new')
    $secondHash = (Get-FileHash -LiteralPath $twoPayload -Algorithm SHA256).Hash.ToLowerInvariant()
    $rollbackManifest = [pscustomobject]@{
        product='SysIn'; version='1.3.0'; channel='stable'; minimumPowerShell='5.1'
        files=@(
            [pscustomobject]@{ target='src/SysIn.ps1'; url='https://example.invalid/SysIn.ps1'; sha256=$payloadHash },
            [pscustomobject]@{ target='src/Second.psm1'; url='https://example.invalid/Second.psm1'; sha256=$secondHash }
        )
    }
    $rollbackDownloader = {
        param($Url,$Destination)
        if ($Url -like '*Second.psm1') { Copy-Item -LiteralPath $twoPayload -Destination $Destination -Force }
        else { Copy-Item -LiteralPath $payloadFile -Destination $Destination -Force }
    }
    $replaceCount = 0
    $failingReplacer = {
        param($Source,$Destination)
        $script:replaceCount++
        if ($script:replaceCount -eq 2) { throw 'simulated replacement failure' }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
    Assert-SysInThrows { Invoke-SysInUpdate -CurrentVersion '1.2.0' -InstallRoot $installRoot -ManifestObject $rollbackManifest -Downloader $rollbackDownloader -Replacer $failingReplacer } 'replacement failure is surfaced'
    Assert-SysInEqual ([IO.File]::ReadAllText($installedFile)) 'old-again' 'failed multi-file update restores already-replaced file'
    Assert-SysInTrue (-not (Test-Path -LiteralPath (Join-Path $installRoot 'src\Second.psm1'))) 'failed update removes newly-created target'
} finally {
    Remove-Module SysIn.Update -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
