$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'src\SysIn.ps1'
$core = Join-Path $repoRoot 'src\SysIn.Core.psm1'

Import-Module $core -Force

$commands = Get-Command -Module SysIn.Core | Select-Object -ExpandProperty Name
foreach ($required in @('Invoke-SysIn','Invoke-SysInCommand','Get-SysInSystemInfo','Get-SysInCapabilities','Invoke-SysInDoctor')) {
    Assert-SysInTrue ($required -in $commands) "core exports $required"
}

$system = Get-SysInSystemInfo
Assert-SysInTrue (-not [string]::IsNullOrWhiteSpace([string]$system.OS)) 'system info exposes OS'
Assert-SysInTrue (-not [string]::IsNullOrWhiteSpace([string]$system.CpuName)) 'system info exposes CPU'
Assert-SysInTrue ([int]$system.CpuLogical -gt 0) 'system info exposes logical CPU count'

$cap = Get-SysInCapabilities
Assert-SysInTrue ($null -ne $cap.CpuMemory) 'capabilities exposes CPU/memory support state'
Assert-SysInTrue ($null -ne $cap.NvidiaSmi) 'capabilities exposes NVIDIA SMI state'
Assert-SysInTrue ($null -ne $cap.Battery) 'capabilities exposes battery state'

$doctorLocalApp = Join-Path ([IO.Path]::GetTempPath()) ('sysin-doctor-' + [guid]::NewGuid().ToString('N'))
$oldLocalApp = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $doctorLocalApp
    $doctor = Invoke-SysInDoctor -InstallRoot $repoRoot -UserPath $repoRoot
    $checks = @{}
    foreach ($check in @($doctor.Checks)) { $checks[[string]$check.Name] = [string]$check.Status }
    Assert-SysInEqual $checks['Windows runtime'] 'PASS' 'doctor verifies Windows runtime'
    Assert-SysInEqual $checks['PowerShell version'] 'PASS' 'doctor verifies PowerShell version'
    Assert-SysInEqual $checks['Runtime files'] 'PASS' 'doctor verifies complete required runtime set'
    Assert-SysInEqual $checks['User PATH'] 'PASS' 'doctor verifies current-user PATH registration'
    Assert-SysInEqual $checks['Configuration'] 'PASS' 'doctor treats absent config file as valid defaults'
    Assert-SysInTrue ($checks['Providers'] -in @('PASS','PARTIAL')) 'doctor reports provider availability without fabricating support'

    $configDir = Join-Path $doctorLocalApp 'SysIn'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $configDir 'config.json'),'{not-valid-json')
    $badDoctor = Invoke-SysInDoctor -InstallRoot $repoRoot -UserPath $repoRoot
    $badConfig = @($badDoctor.Checks | Where-Object Name -eq 'Configuration')[0]
    Assert-SysInEqual ([string]$badConfig.Status) 'FAIL' 'doctor reports invalid configuration as FAIL'
} finally {
    $env:LOCALAPPDATA = $oldLocalApp
    Remove-Item -LiteralPath $doctorLocalApp -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-CoreCliSnapshotTest {
    param([string[]]$Arguments, [string]$ExpectedPattern)
    $output = & pwsh -NoLogo -NoProfile -File $cli @Arguments 2>&1 | Out-String
    Assert-SysInEqual $LASTEXITCODE 0 (("CLI exits 0 for: " + ($Arguments -join ' ')) + "`nCaptured output:`n$output")
    Assert-SysInMatch $output $ExpectedPattern (("CLI output matches for: " + ($Arguments -join ' ')) + "`nCaptured output:`n$output")
}

Invoke-CoreCliSnapshotTest @('-CPU','-Snapshot') 'CPU'
Invoke-CoreCliSnapshotTest @('-GPU','-Snapshot') 'GPU'
Invoke-CoreCliSnapshotTest @('-Memory','-Snapshot') 'MEMORY|Physical RAM'
Invoke-CoreCliSnapshotTest @('-Processes','-Snapshot') 'PROCESSES|TOP PROCESSES'
Invoke-CoreCliSnapshotTest @('snapshot') 'SysIn v1\.1\.0'
Invoke-CoreCliSnapshotTest @('system') 'SYSTEM'
Invoke-CoreCliSnapshotTest @('storage') 'STORAGE'
Invoke-CoreCliSnapshotTest @('network') 'NETWORK'
Invoke-CoreCliSnapshotTest @('sensors') 'SENSORS'
Invoke-CoreCliSnapshotTest @('capabilities') 'CAPABILITIES'
Invoke-CoreCliSnapshotTest @('doctor') '(?s)DOCTOR.*Runtime files.*User PATH.*Configuration.*Providers'

Remove-Module SysIn.Core -Force -ErrorAction SilentlyContinue
