$repoRoot = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $repoRoot 'install.ps1'
$uninstallScript = Join-Path $repoRoot 'uninstall.ps1'
$updateModule = Join-Path $repoRoot 'src\SysIn.Update.psm1'

foreach ($required in @($installScript,$uninstallScript,$updateModule)) {
    Assert-SysInTrue (Test-Path -LiteralPath $required -PathType Leaf) "required safety-reviewed file exists: $required"
}

$combined = ((Get-Content -LiteralPath $installScript -Raw) + "`n" + (Get-Content -LiteralPath $uninstallScript -Raw) + "`n" + (Get-Content -LiteralPath $updateModule -Raw))
foreach ($forbidden in @(
    'Set-ExecutionPolicy',
    'New-Service',
    'CreateService',
    'Register-ScheduledTask',
    'schtasks.exe',
    'EnvironmentVariableTarget]::Machine',
    "EnvironmentVariableTarget]::'Machine'",
    'setx /M',
    'HKLM:\\'
)) {
    Assert-SysInTrue ($combined -notmatch [regex]::Escape($forbidden)) "runtime does not contain forbidden operation: $forbidden"
}

$localApp = Join-Path ([IO.Path]::GetTempPath()) ('sysin-safety-localapp-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $localApp 'Programs\SysIn'
$oldLocalApp = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $localApp

try {
    & $installScript -InstallRoot $installRoot -SourceRoot $repoRoot -NoPathChange | Out-Null
    Assert-SysInEqual $LASTEXITCODE 0 'local repository install exits successfully'

    foreach ($relative in @('SysIn.cmd','src\SysIn.ps1','src\SysIn.Core.psm1','src\SysIn.Config.psm1','src\SysIn.Update.psm1','uninstall.ps1')) {
        Assert-SysInTrue (Test-Path -LiteralPath (Join-Path $installRoot $relative) -PathType Leaf) "installer places known runtime file $relative"
    }

    $unknown = Join-Path $installRoot 'keep-me.txt'
    [IO.File]::WriteAllText($unknown,'user file')
    [IO.File]::WriteAllText((Join-Path $installRoot 'src\SysIn.ps1'),'old modified runtime')

    & $installScript -InstallRoot $installRoot -SourceRoot $repoRoot -NoPathChange | Out-Null
    Assert-SysInEqual $LASTEXITCODE 0 'reinstall exits successfully'
    Assert-SysInTrue (Test-Path -LiteralPath $unknown) 'reinstall preserves unknown user file'
    Assert-SysInMatch ([IO.File]::ReadAllText((Join-Path $installRoot 'src\SysIn.ps1'))) 'SysInVersion.*1\.1\.0' 'reinstall refreshes known runtime file'

    & $uninstallScript -InstallRoot $installRoot -NoPathChange | Out-Null
    Assert-SysInEqual $LASTEXITCODE 0 'uninstall exits successfully'
    Assert-SysInTrue (Test-Path -LiteralPath $unknown -PathType Leaf) 'uninstall preserves unknown file'
    Assert-SysInTrue (Test-Path -LiteralPath $installRoot -PathType Container) 'uninstall preserves nonempty install directory'
    Assert-SysInTrue (-not (Test-Path -LiteralPath (Join-Path $installRoot 'SysIn.cmd'))) 'uninstall removes known launcher'
    Assert-SysInTrue (-not (Test-Path -LiteralPath (Join-Path $installRoot 'src\SysIn.Core.psm1'))) 'uninstall removes known core module'

    $configPath = Join-Path $localApp 'SysIn\config.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
    [IO.File]::WriteAllText($configPath,'{"fps":20,"updateChannel":"stable","updateCheck":"manual"}')
    & $uninstallScript -InstallRoot $installRoot -NoPathChange | Out-Null
    Assert-SysInTrue (Test-Path -LiteralPath $configPath -PathType Leaf) 'uninstall keeps per-user configuration by default'
} finally {
    $env:LOCALAPPDATA = $oldLocalApp
    Remove-Item -LiteralPath $localApp -Recurse -Force -ErrorAction SilentlyContinue
}
