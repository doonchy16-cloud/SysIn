$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'src\SysIn.ps1'
$core = Join-Path $repoRoot 'src\SysIn.Core.psm1'

Import-Module $core -Force

$commands = Get-Command -Module SysIn.Core | Select-Object -ExpandProperty Name
foreach ($required in @('Invoke-SysIn','Invoke-SysInCommand','Get-SysInSystemInfo','Get-SysInCapabilities')) {
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

function Invoke-CoreCliSnapshotTest {
    param([string[]]$Arguments, [string]$ExpectedPattern)
    $output = & pwsh -NoLogo -NoProfile -File $cli @Arguments 2>&1 | Out-String
    Assert-SysInEqual $LASTEXITCODE 0 ("CLI exits 0 for: " + ($Arguments -join ' '))
    Assert-SysInMatch $output $ExpectedPattern ("CLI output matches for: " + ($Arguments -join ' '))
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

Remove-Module SysIn.Core -Force -ErrorAction SilentlyContinue
