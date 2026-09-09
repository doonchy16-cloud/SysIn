$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'src\SysIn.ps1'
$testHost = if ([string]::IsNullOrWhiteSpace($env:SYSIN_TEST_HOST)) { 'pwsh' } else { $env:SYSIN_TEST_HOST }

function Invoke-SysInCliTest {
    param([string[]]$Arguments)
    $output = & $testHost -NoLogo -NoProfile -File $cli @Arguments 2>&1 | Out-String
    [pscustomobject]@{
        Output = $output.Trim()
        ExitCode = $LASTEXITCODE
    }
}

$result = Invoke-SysInCliTest @('version')
Assert-SysInEqual $result.ExitCode 0 "canonical version command exits 0`nCaptured output:`n$($result.Output)"
Assert-SysInMatch $result.Output 'SysIn 1\.1\.0' 'canonical version reports 1.1.0'
Assert-SysInMatch $result.Output 'stable' 'canonical version reports stable channel'

foreach ($alias in @('--version','-v','-Version')) {
    $result = Invoke-SysInCliTest @($alias)
    Assert-SysInEqual $result.ExitCode 0 "$alias exits 0`nCaptured output:`n$($result.Output)"
    Assert-SysInMatch $result.Output 'SysIn 1\.1\.0' "$alias reports 1.1.0"
}

$result = Invoke-SysInCliTest @('help')
Assert-SysInEqual $result.ExitCode 0 "help exits 0`nCaptured output:`n$($result.Output)"
foreach ($command in @(
    'overview','cpu','gpu','memory','storage','network','processes','sensors',
    'system','snapshot','doctor','capabilities','version','check-update','update',
    'config','help','about'
)) {
    Assert-SysInMatch $result.Output ([regex]::Escape($command)) "help lists $command"
}

$result = Invoke-SysInCliTest @('about')
Assert-SysInEqual $result.ExitCode 0 "about exits 0`nCaptured output:`n$($result.Output)"
Assert-SysInMatch $result.Output 'doonchy16-cloud/SysIn' 'about shows repository'
Assert-SysInMatch $result.Output 'Windows System Intelligence' 'about describes the product'
