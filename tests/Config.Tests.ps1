$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src\SysIn.Config.psm1'
Import-Module $modulePath -Force

$oldLocalAppData = $env:LOCALAPPDATA
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sysin-config-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$env:LOCALAPPDATA = $tempRoot

try {
    $expectedPath = Join-Path $tempRoot 'SysIn\config.json'
    Assert-SysInEqual (Get-SysInConfigPath) $expectedPath 'config path uses LOCALAPPDATA\SysIn\config.json'

    $config = Get-SysInConfig
    Assert-SysInEqual $config.fps 20 'default fps is 20'
    Assert-SysInEqual $config.updateChannel 'stable' 'default channel is stable'
    Assert-SysInEqual $config.updateCheck 'manual' 'default update check is manual'

    Set-SysInConfigValue -Key 'fps' -Value '12'
    $config = Get-SysInConfig
    Assert-SysInEqual $config.fps 12 'valid fps persists'

    Set-SysInConfigValue -Key 'updateCheck' -Value 'daily'
    $config = Get-SysInConfig
    Assert-SysInEqual $config.updateCheck 'daily' 'valid update check persists'

    Assert-SysInThrows { Set-SysInConfigValue -Key 'fps' -Value '0' } 'fps below 1 is rejected'
    Assert-SysInThrows { Set-SysInConfigValue -Key 'fps' -Value '21' } 'fps above 20 is rejected'
    Assert-SysInThrows { Set-SysInConfigValue -Key 'unknownKey' -Value 'x' } 'unknown config key is rejected'
    Assert-SysInThrows { Set-SysInConfigValue -Key 'updateChannel' -Value 'beta' } 'unsupported V1.1 channel is rejected'
    Assert-SysInThrows { Set-SysInConfigValue -Key 'updateCheck' -Value 'hourly' } 'unsupported update check mode is rejected'

    Reset-SysInConfig
    $config = Get-SysInConfig
    Assert-SysInEqual $config.fps 20 'reset restores fps'
    Assert-SysInEqual $config.updateChannel 'stable' 'reset restores stable channel'
    Assert-SysInEqual $config.updateCheck 'manual' 'reset restores manual update checks'

    $cli = Join-Path $repoRoot 'src\SysIn.ps1'
    $cliOut = & pwsh -NoLogo -NoProfile -File $cli config path 2>&1 | Out-String
    Assert-SysInEqual $LASTEXITCODE 0 'config path CLI exits 0'
    Assert-SysInMatch $cliOut ([regex]::Escape($expectedPath)) 'config path CLI prints the config path'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Module SysIn.Config -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
