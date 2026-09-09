$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'src\SysIn.ps1'
$core = Join-Path $repoRoot 'src\SysIn.Core.psm1'
$testHost = if ([string]::IsNullOrWhiteSpace($env:SYSIN_TEST_HOST)) { 'pwsh' } else { $env:SYSIN_TEST_HOST }

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
    try {
        $doctor = Invoke-SysInDoctor -InstallRoot $repoRoot -UserPath $repoRoot
    } catch {
        Write-Host '=== DOCTOR EXCEPTION DIAGNOSTICS ==='
        Write-Host ('Type: ' + $_.Exception.GetType().FullName)
        Write-Host ('Message: ' + $_.Exception.Message)
        Write-Host ('ScriptStackTrace: ' + $_.ScriptStackTrace)
        Write-Host ('Position: ' + $_.InvocationInfo.PositionMessage)
        if ($_.Exception.InnerException) {
            Write-Host ('InnerType: ' + $_.Exception.InnerException.GetType().FullName)
            Write-Host ('InnerMessage: ' + $_.Exception.InnerException.Message)
        }
        throw
    }
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
    $output = & $testHost -NoLogo -NoProfile -File $cli @Arguments 2>&1 | Out-String
    Assert-SysInEqual $LASTEXITCODE 0 (("CLI exits 0 for: " + ($Arguments -join ' ')) + "`nCaptured output:`n$output")
    Assert-SysInMatch $output $ExpectedPattern (("CLI output matches for: " + ($Arguments -join ' ')) + "`nCaptured output:`n$output")
}

Invoke-CoreCliSnapshotTest @('-CPU','-Snapshot') 'CPU'
Invoke-CoreCliSnapshotTest @('-GPU','-Snapshot') 'GPU'
Invoke-CoreCliSnapshotTest @('-Memory','-Snapshot') 'MEMORY|Physical RAM'
Invoke-CoreCliSnapshotTest @('-Processes','-Snapshot') 'PROCESSES|TOP PROCESSES'
Invoke-CoreCliSnapshotTest @('snapshot') '(?s)SysIn v1\.1\.0.*UPTIME'
Invoke-CoreCliSnapshotTest @('system') 'SYSTEM'
Invoke-CoreCliSnapshotTest @('storage') 'STORAGE'
Invoke-CoreCliSnapshotTest @('network') 'NETWORK'
Invoke-CoreCliSnapshotTest @('sensors') 'SENSORS'
Invoke-CoreCliSnapshotTest @('capabilities') 'CAPABILITIES'
Invoke-CoreCliSnapshotTest @('doctor') '(?s)DOCTOR.*Runtime files.*User PATH.*Configuration.*Providers'

$fpsLocalApp = Join-Path ([IO.Path]::GetTempPath()) ('sysin-core-fps-' + [guid]::NewGuid().ToString('N'))
$oldFpsLocalApp = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $fpsLocalApp
    $configModule = Join-Path $repoRoot 'src\SysIn.Config.psm1'
    Import-Module $configModule -Force
    [void](Set-SysInConfigValue -Key 'fps' -Value '12')

    $coreModule = Get-Module SysIn.Core
    $capturedFps = & $coreModule {
        $script:CapturedDashboardFps = $null
        function Invoke-SysIn {
            param(
                [int]$FPS = 20,
                [string]$InitialPage = 'Overview',
                [switch]$Compact,
                [switch]$Snapshot
            )
            $script:CapturedDashboardFps = $FPS
        }

        Invoke-SysInCommand -Command 'overview' -Arguments @()
        $configured = $script:CapturedDashboardFps

        $script:CapturedDashboardFps = $null
        Invoke-SysInCommand -Command 'overview' -Arguments @('-FPS','7')
        $override = $script:CapturedDashboardFps

        [pscustomobject]@{Configured=$configured;Override=$override}
    }
    Assert-SysInEqual $capturedFps.Configured 12 'dashboard dispatcher uses persisted FPS when CLI override is absent'
    Assert-SysInEqual $capturedFps.Override 7 'dashboard dispatcher gives explicit FPS precedence over persisted configuration'
} finally {
    $env:LOCALAPPDATA = $oldFpsLocalApp
    Remove-Module SysIn.Config -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fpsLocalApp -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-Module SysIn.Core -Force -ErrorAction SilentlyContinue
