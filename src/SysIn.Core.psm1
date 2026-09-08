Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:SysInVersion = '1.1.0'
$script:Esc = [char]27
$script:AnsiEnabled = $false

if (-not ('SysIn.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace SysIn {
    [StructLayout(LayoutKind.Sequential)]
    public struct FILETIME {
        public uint dwLowDateTime;
        public uint dwHighDateTime;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public class MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
        public MEMORYSTATUSEX() { dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); }
    }

    public static class NativeMethods {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetSystemTimes(out FILETIME idleTime, out FILETIME kernelTime, out FILETIME userTime);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);
    }
}
'@
}

function Test-SysInWindows {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Convert-FileTimeToUInt64 {
    param($Value)
    return ([uint64]$Value.dwHighDateTime -shl 32) -bor [uint64]$Value.dwLowDateTime
}

function Get-CpuTimes {
    $idle = New-Object SysIn.FILETIME
    $kernel = New-Object SysIn.FILETIME
    $user = New-Object SysIn.FILETIME
    if (-not [SysIn.NativeMethods]::GetSystemTimes([ref]$idle,[ref]$kernel,[ref]$user)) { return $null }
    [pscustomobject]@{
        Idle = Convert-FileTimeToUInt64 $idle
        Kernel = Convert-FileTimeToUInt64 $kernel
        User = Convert-FileTimeToUInt64 $user
    }
}

function Get-CpuPercent {
    param($Previous, $Current)
    if ($null -eq $Previous -or $null -eq $Current) { return 0.0 }
    $idle = [double]($Current.Idle - $Previous.Idle)
    $kernel = [double]($Current.Kernel - $Previous.Kernel)
    $user = [double]($Current.User - $Previous.User)
    $total = $kernel + $user
    if ($total -le 0) { return 0.0 }
    return [math]::Round(([math]::Max(0,[math]::Min(1,($total-$idle)/$total))) * 100,1)
}

function Get-MemoryTelemetry {
    $m = New-Object SysIn.MEMORYSTATUSEX
    if (-not [SysIn.NativeMethods]::GlobalMemoryStatusEx($m)) {
        return [pscustomobject]@{ Total=0; Available=0; Used=0; Percent=0 }
    }
    $total = [double]$m.ullTotalPhys
    $avail = [double]$m.ullAvailPhys
    $used = [math]::Max(0,$total-$avail)
    $pct = if ($total -gt 0) { [math]::Round(($used/$total)*100,1) } else { 0 }
    [pscustomobject]@{ Total=$total; Available=$avail; Used=$used; Percent=$pct }
}

function Get-SysInSystemInfo {
    if (-not (Test-SysInWindows)) { throw 'SysIn V1.1 runtime telemetry requires Windows.' }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $cpu = @(Get-CimInstance Win32_Processor -ErrorAction Stop)[0]
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic Display' })
    $gpuNames = @($gpus | ForEach-Object { $_.Name })
    $systemDrive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Manufacturer = [string]$cs.Manufacturer
        Model = [string]$cs.Model
        OS = [string]$os.Caption
        OSVersion = [string]$os.Version
        Build = [string]$os.BuildNumber
        BootTime = $os.LastBootUpTime
        CpuName = ([string]$cpu.Name).Trim()
        CpuCores = [int]$cpu.NumberOfCores
        CpuLogical = [int]$cpu.NumberOfLogicalProcessors
        CpuMaxMHz = [int]$cpu.MaxClockSpeed
        GpuNames = $gpuNames
        GpuName = if ($gpuNames.Count -gt 0) { $gpuNames[0] } else { 'GPU not detected' }
        TotalMemory = [double]$cs.TotalPhysicalMemory
        SystemDrive = $systemDrive
    }
}

function Get-NvidiaSmiPath {
    try {
        $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
    } catch {}
    if ($env:ProgramFiles) {
        $candidate = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Invoke-NvidiaQuery {
    param([string]$Path)
    if (-not $Path) { return $null }
    try {
        $line = & $Path '--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,clocks.gr,fan.speed,driver_version' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if (-not $line) { return $null }
        $v = @($line -split ',' | ForEach-Object { $_.Trim() })
        if ($v.Count -lt 9) { return $null }
        [pscustomobject]@{
            Name=$v[0]; Utilization=[double]$v[1]; VramUsedMB=[double]$v[2]; VramTotalMB=[double]$v[3]
            TempC=[double]$v[4]; PowerW=[double]$v[5]; ClockMHz=[double]$v[6]; FanPercent=[double]$v[7]; Driver=$v[8]
            Provider='nvidia-smi'
        }
    } catch { return $null }
}

function Get-WindowsGpuUsage {
    try {
        $samples = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop |
            Where-Object { $_.Name -match 'engtype_(3D|Graphics|Compute)' })
        if ($samples.Count -eq 0) { return $null }
        $sum = 0.0
        foreach ($s in $samples) { $sum += [double]$s.UtilizationPercentage }
        return [math]::Round([math]::Min(100,$sum),1)
    } catch { return $null }
}

function Get-GpuTelemetry {
    param([string]$NvidiaPath)
    $nvidia = Invoke-NvidiaQuery $NvidiaPath
    if ($nvidia) { return $nvidia }
    $usage = Get-WindowsGpuUsage
    [pscustomobject]@{
        Name='Windows GPU'; Utilization=$usage; VramUsedMB=$null; VramTotalMB=$null; TempC=$null; PowerW=$null
        ClockMHz=$null; FanPercent=$null; Driver=$null; Provider='Windows GPU counters'
    }
}

function Get-StorageNetworkTelemetry {
    param([string]$SystemDrive)
    $driveTotal=$null; $driveFree=$null
    try {
        $d = New-Object IO.DriveInfo($SystemDrive + '\')
        if ($d.IsReady) { $driveTotal=[double]$d.TotalSize; $driveFree=[double]$d.AvailableFreeSpace }
    } catch {}
    $diskRead=0.0; $diskWrite=0.0
    try {
        $disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop | Where-Object Name -eq '_Total' | Select-Object -First 1
        if ($disk) { $diskRead=[double]$disk.DiskReadBytesPersec; $diskWrite=[double]$disk.DiskWriteBytesPersec }
    } catch {}
    $netDown=0.0; $netUp=0.0
    try {
        foreach ($nic in @(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop)) {
            $netDown += [double]$nic.BytesReceivedPersec; $netUp += [double]$nic.BytesSentPersec
        }
    } catch {}
    [pscustomobject]@{ DriveTotal=$driveTotal; DriveFree=$driveFree; DiskRead=$diskRead; DiskWrite=$diskWrite; NetDown=$netDown; NetUp=$netUp }
}

function Get-TopProcesses {
    param([int]$Top=8)
    @(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First $Top | ForEach-Object {
        [pscustomobject]@{ Name=$_.ProcessName; Id=$_.Id; Memory=[double]$_.WorkingSet64; CpuSeconds=[double]$_.CPU }
    })
}

function Get-SysInCapabilities {
    if (-not (Test-SysInWindows)) { throw 'SysIn V1.1 runtime telemetry requires Windows.' }
    $nvidia = [bool](Get-NvidiaSmiPath)
    $gpuCounters = $false
    try { $null = Get-CimClass Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop; $gpuCounters=$true } catch {}
    $battery = $false
    try { $battery = @((Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)).Count -gt 0 } catch {}
    $thermal = $false
    try { $thermal = @((Get-CimInstance -Namespace root/wmi MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue)).Count -gt 0 } catch {}
    [pscustomobject]@{
        CpuMemory = $true
        WindowsGpuCounters = $gpuCounters
        NvidiaSmi = $nvidia
        CpuTemperature = $thermal
        StorageNetwork = $true
        Battery = $battery
    }
}

function Format-Bytes {
    param([double]$Value)
    if ($null -eq $Value) { return 'N/A' }
    if ($Value -ge 1TB) { return ('{0:N2} TB' -f ($Value/1TB)) }
    if ($Value -ge 1GB) { return ('{0:N2} GB' -f ($Value/1GB)) }
    if ($Value -ge 1MB) { return ('{0:N1} MB' -f ($Value/1MB)) }
    if ($Value -ge 1KB) { return ('{0:N1} KB' -f ($Value/1KB)) }
    return ('{0:N0} B' -f $Value)
}

function Format-Rate {
    param([double]$Value)
    return ((Format-Bytes $Value) + '/s')
}

function Get-Bar {
    param([double]$Percent,[int]$Width=24)
    $p=[math]::Max(0,[math]::Min(100,$Percent)); $filled=[int][math]::Round(($p/100)*$Width)
    return ('[' + ('#' * $filled) + ('-' * ($Width-$filled)) + ']')
}

function Get-SysInSnapshotState {
    param($Static,$CpuPrevious,[string]$NvidiaPath)
    Start-Sleep -Milliseconds 100
    $cpuNow=Get-CpuTimes
    $cpu=Get-CpuPercent $CpuPrevious $cpuNow
    $mem=Get-MemoryTelemetry
    $gpu=Get-GpuTelemetry $NvidiaPath
    $io=Get-StorageNetworkTelemetry $Static.SystemDrive
    $procs=Get-TopProcesses 8
    [pscustomobject]@{ Cpu=$cpu; CpuTimes=$cpuNow; Memory=$mem; GPU=$gpu; IO=$io; Processes=$procs; Time=Get-Date }
}

function Write-OverviewSnapshot {
    param($Static,$State)
    Write-Output "SysIn v$script:SysInVersion | OVERVIEW | $($State.Time.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Output ("CPU  {0} {1,5:N1}%  {2}" -f (Get-Bar $State.Cpu),$State.Cpu,$Static.CpuName)
    Write-Output ("GPU  {0} {1,5}%  {2}" -f (Get-Bar $(if($null -eq $State.GPU.Utilization){0}else{$State.GPU.Utilization})),$(if($null -eq $State.GPU.Utilization){'N/A'}else{('{0:N1}%' -f $State.GPU.Utilization)}),$Static.GpuName)
    Write-Output ("RAM  {0} {1,5:N1}%  {2} / {3}" -f (Get-Bar $State.Memory.Percent),$State.Memory.Percent,(Format-Bytes $State.Memory.Used),(Format-Bytes $State.Memory.Total))
    Write-Output ("DISK Read {0}  Write {1}  Free {2}" -f (Format-Rate $State.IO.DiskRead),(Format-Rate $State.IO.DiskWrite),(Format-Bytes $State.IO.DriveFree))
    Write-Output ("NET  Down {0}  Up {1}" -f (Format-Rate $State.IO.NetDown),(Format-Rate $State.IO.NetUp))
}

function Write-PageSnapshot {
    param([string]$Page,$Static,$State)
    switch ($Page) {
        'CPU' {
            Write-Output "SysIn v$script:SysInVersion | CPU"
            Write-Output "CPU: $($Static.CpuName)"
            Write-Output ("Usage: {0:N1}% {1}" -f $State.Cpu,(Get-Bar $State.Cpu 30))
            Write-Output "Cores: $($Static.CpuCores) physical / $($Static.CpuLogical) logical"
            Write-Output "Max clock: $($Static.CpuMaxMHz) MHz"
        }
        'GPU' {
            Write-Output "SysIn v$script:SysInVersion | GPU"
            Write-Output "GPU: $($Static.GpuName)"
            Write-Output "Provider: $($State.GPU.Provider)"
            Write-Output ("Usage: {0}" -f $(if($null -eq $State.GPU.Utilization){'N/A'}else{('{0:N1}%' -f $State.GPU.Utilization)}))
            Write-Output ("Temperature: {0}" -f $(if($null -eq $State.GPU.TempC){'N/A'}else{"$($State.GPU.TempC) C"}))
            Write-Output ("VRAM: {0} / {1}" -f $(if($null -eq $State.GPU.VramUsedMB){'N/A'}else{"$($State.GPU.VramUsedMB) MB"}),$(if($null -eq $State.GPU.VramTotalMB){'N/A'}else{"$($State.GPU.VramTotalMB) MB"}))
        }
        'Memory' {
            Write-Output "SysIn v$script:SysInVersion | MEMORY"
            Write-Output ("Physical RAM: {0} used / {1} total ({2:N1}%)" -f (Format-Bytes $State.Memory.Used),(Format-Bytes $State.Memory.Total),$State.Memory.Percent)
            Write-Output ("Available: {0}" -f (Format-Bytes $State.Memory.Available))
        }
        'Processes' {
            Write-Output "SysIn v$script:SysInVersion | PROCESSES"
            Write-Output 'TOP PROCESSES BY MEMORY'
            foreach ($p in $State.Processes) { Write-Output ('{0,-28} PID {1,6}  RAM {2,10}' -f $p.Name,$p.Id,(Format-Bytes $p.Memory)) }
        }
        default { Write-OverviewSnapshot $Static $State }
    }
}

function Invoke-SysIn {
    [CmdletBinding()]
    param(
        [ValidateRange(1,20)][int]$FPS=20,
        [ValidateSet('Overview','CPU','GPU','Memory','Processes')][string]$InitialPage='Overview',
        [switch]$Compact,
        [switch]$Snapshot
    )
    if (-not (Test-SysInWindows)) { throw 'SysIn V1.1 is a Windows dashboard and requires Windows PowerShell 5.1+ or PowerShell 7+ on Windows.' }
    $static=Get-SysInSystemInfo
    $nvidia=Get-NvidiaSmiPath
    $cpuPrev=Get-CpuTimes

    if ($Snapshot) {
        $s=Get-SysInSnapshotState $static $cpuPrev $nvidia
        Write-PageSnapshot $InitialPage $static $s
        return
    }

    $page=$InitialPage; $paused=$false; $state=$null; $lastSlow=[datetime]::MinValue
    $minCpu=100.0; $peakCpu=0.0; $minRam=100.0; $peakRam=0.0; $minGpu=$null; $peakGpu=0.0
    $oldCursor=$true
    try {
        try { $oldCursor=[Console]::CursorVisible; [Console]::CursorVisible=$false } catch {}
        try { [Console]::Clear() } catch {}
        while ($true) {
            $frameStart=Get-Date
            if (-not $paused) {
                $now=Get-Date
                $cpuNow=Get-CpuTimes
                $cpu=Get-CpuPercent $cpuPrev $cpuNow; $cpuPrev=$cpuNow
                $mem=Get-MemoryTelemetry
                if ($null -eq $state -or ($now-$lastSlow).TotalMilliseconds -ge 750) {
                    $gpu=Get-GpuTelemetry $nvidia
                    $io=Get-StorageNetworkTelemetry $static.SystemDrive
                    $procs=Get-TopProcesses 8
                    $lastSlow=$now
                } else { $gpu=$state.GPU; $io=$state.IO; $procs=$state.Processes }
                $state=[pscustomobject]@{Cpu=$cpu;Memory=$mem;GPU=$gpu;IO=$io;Processes=$procs;Time=$now}
                $minCpu=[math]::Min($minCpu,$cpu); $peakCpu=[math]::Max($peakCpu,$cpu)
                $minRam=[math]::Min($minRam,$mem.Percent); $peakRam=[math]::Max($peakRam,$mem.Percent)
                if ($null -ne $gpu.Utilization) { if ($null -eq $minGpu){$minGpu=$gpu.Utilization}else{$minGpu=[math]::Min($minGpu,$gpu.Utilization)}; $peakGpu=[math]::Max($peakGpu,$gpu.Utilization) }
            }
            try { [Console]::SetCursorPosition(0,0) } catch { Clear-Host }
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add("SysIn v$script:SysInVersion | $($page.ToUpperInvariant()) | LIVE $FPS FPS$(if($paused){' | PAUSED'}else{''})")
            $lines.Add(('=' * 78))
            if ($state) {
                switch ($page) {
                    'CPU' { $lines.Add("CPU  $($static.CpuName)"); $lines.Add(("{0} {1:N1}%   min {2:N1}%   peak {3:N1}%" -f (Get-Bar $state.Cpu 30),$state.Cpu,$minCpu,$peakCpu)); $lines.Add("Cores $($static.CpuCores) physical / $($static.CpuLogical) logical | Max $($static.CpuMaxMHz) MHz") }
                    'GPU' { $g=$state.GPU; $gp=if($null -eq $g.Utilization){0}else{$g.Utilization}; $lines.Add("GPU  $($static.GpuName) | $($g.Provider)"); $lines.Add(("{0} {1}" -f (Get-Bar $gp 30),$(if($null -eq $g.Utilization){'N/A'}else{('{0:N1}%' -f $g.Utilization)}))); $lines.Add(("Temp {0} | VRAM {1}/{2} MB | Power {3}" -f $(if($null -eq $g.TempC){'N/A'}else{$g.TempC}),$(if($null -eq $g.VramUsedMB){'N/A'}else{$g.VramUsedMB}),$(if($null -eq $g.VramTotalMB){'N/A'}else{$g.VramTotalMB}),$(if($null -eq $g.PowerW){'N/A'}else{"$($g.PowerW) W"}))) }
                    'Memory' { $m=$state.Memory; $lines.Add('MEMORY'); $lines.Add(("{0} {1:N1}%" -f (Get-Bar $m.Percent 30),$m.Percent)); $lines.Add(("Physical RAM {0} used / {1} total | {2} available" -f (Format-Bytes $m.Used),(Format-Bytes $m.Total),(Format-Bytes $m.Available))) }
                    'Processes' { $lines.Add('TOP PROCESSES BY MEMORY'); foreach($p in $state.Processes){$lines.Add(('{0,-28} PID {1,6} RAM {2,10}' -f $p.Name,$p.Id,(Format-Bytes $p.Memory)))} }
                    default { $lines.Add(("CPU {0} {1,5:N1}%  min {2:N1} peak {3:N1}" -f (Get-Bar $state.Cpu 26),$state.Cpu,$minCpu,$peakCpu)); $lines.Add(("GPU {0} {1}" -f (Get-Bar $(if($null -eq $state.GPU.Utilization){0}else{$state.GPU.Utilization}) 26),$(if($null -eq $state.GPU.Utilization){'N/A'}else{('{0:N1}%' -f $state.GPU.Utilization)}))); $lines.Add(("RAM {0} {1:N1}%  {2}/{3}" -f (Get-Bar $state.Memory.Percent 26),$state.Memory.Percent,(Format-Bytes $state.Memory.Used),(Format-Bytes $state.Memory.Total))); $lines.Add(("DISK R {0} W {1} | NET down {2} up {3}" -f (Format-Rate $state.IO.DiskRead),(Format-Rate $state.IO.DiskWrite),(Format-Rate $state.IO.NetDown),(Format-Rate $state.IO.NetUp))) }
                }
            }
            $lines.Add(('=' * 78)); $lines.Add('[1] Overview [2] CPU [3] GPU [4] Memory [5] Processes  [F] FPS [P] Pause [R] Reset [Q] Quit')
            $height=[math]::Max(12,[Console]::WindowHeight-1)
            while($lines.Count -lt $height){$lines.Add('')}
            foreach($line in $lines){ $out=if($line.Length -gt [Console]::WindowWidth-1){$line.Substring(0,[math]::Max(1,[Console]::WindowWidth-1))}else{$line}; Write-Host ($out.PadRight([math]::Max(1,[Console]::WindowWidth-1))) }

            while ([Console]::KeyAvailable) {
                $key=[Console]::ReadKey($true)
                switch ($key.Key) {
                    'D1' {$page='Overview'}; 'NumPad1' {$page='Overview'}; 'D2' {$page='CPU'}; 'NumPad2' {$page='CPU'}; 'D3' {$page='GPU'}; 'NumPad3' {$page='GPU'}; 'D4' {$page='Memory'}; 'NumPad4' {$page='Memory'}; 'D5' {$page='Processes'}; 'NumPad5' {$page='Processes'}
                    'F' { $FPS = switch($FPS){20{10};10{5};5{1};default{20}} }
                    'P' {$paused=-not $paused}
                    'R' {$minCpu=100.0;$peakCpu=0.0;$minRam=100.0;$peakRam=0.0;$minGpu=$null;$peakGpu=0.0}
                    'Q' {return}; 'Escape' {return}
                }
            }
            $elapsed=((Get-Date)-$frameStart).TotalMilliseconds; $target=1000.0/$FPS; $sleep=[int][math]::Floor($target-$elapsed); if($sleep -gt 0){Start-Sleep -Milliseconds $sleep}
        }
    } finally { try{[Console]::CursorVisible=$oldCursor}catch{}; Write-Host '' }
}

function Write-SysInSystemView {
    $s=Get-SysInSystemInfo
    Write-Output "SysIn v$script:SysInVersion | SYSTEM"
    Write-Output "Computer: $($s.ComputerName)"
    Write-Output "Model: $($s.Manufacturer) $($s.Model)"
    Write-Output "OS: $($s.OS) $($s.OSVersion) build $($s.Build)"
    Write-Output "CPU: $($s.CpuName) | $($s.CpuCores) cores / $($s.CpuLogical) logical"
    Write-Output "GPU: $($s.GpuNames -join '; ')"
    Write-Output "RAM: $(Format-Bytes $s.TotalMemory)"
}

function Write-SysInStorageView {
    $s=Get-SysInSystemInfo; $io=Get-StorageNetworkTelemetry $s.SystemDrive
    Write-Output "SysIn v$script:SysInVersion | STORAGE"
    Write-Output "System drive: $($s.SystemDrive)"
    Write-Output "Capacity: $(Format-Bytes $io.DriveTotal) | Free: $(Format-Bytes $io.DriveFree)"
    Write-Output "Read: $(Format-Rate $io.DiskRead) | Write: $(Format-Rate $io.DiskWrite)"
    try { foreach($d in @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)){ Write-Output "Disk: $($d.Model) | $([math]::Round([double]$d.Size/1GB,1)) GB | $($d.InterfaceType)" } } catch {}
}

function Write-SysInNetworkView {
    $s=Get-SysInSystemInfo; $io=Get-StorageNetworkTelemetry $s.SystemDrive
    Write-Output "SysIn v$script:SysInVersion | NETWORK"
    Write-Output "Download: $(Format-Rate $io.NetDown) | Upload: $(Format-Rate $io.NetUp)"
    try { foreach($n in @(Get-CimInstance Win32_NetworkAdapter -Filter 'NetEnabled=True' -ErrorAction SilentlyContinue)){ Write-Output "Adapter: $($n.Name) | MAC $($n.MACAddress) | Speed $(Format-Rate ([double]$n.Speed))" } } catch {}
}

function Write-SysInSensorsView {
    $nvidia=Invoke-NvidiaQuery (Get-NvidiaSmiPath)
    Write-Output "SysIn v$script:SysInVersion | SENSORS"
    if($nvidia){ Write-Output "GPU temperature: $($nvidia.TempC) C"; Write-Output "GPU power: $($nvidia.PowerW) W"; Write-Output "GPU fan: $($nvidia.FanPercent)%"; Write-Output "GPU clock: $($nvidia.ClockMHz) MHz" } else { Write-Output 'GPU temperature: N/A'; Write-Output 'GPU power: N/A'; Write-Output 'GPU fan: N/A' }
    $temp=$null
    try { $zone=Get-CimInstance -Namespace root/wmi MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object -First 1; if($zone){$temp=[math]::Round(([double]$zone.CurrentTemperature/10)-273.15,1)} } catch {}
    Write-Output ("CPU/ACPI temperature: " + $(if($null -eq $temp){'N/A'}else{"$temp C"}))
}

function Write-SysInCapabilitiesView {
    $c=Get-SysInCapabilities
    Write-Output "SysIn v$script:SysInVersion | CAPABILITIES"
    foreach($p in @('CpuMemory','WindowsGpuCounters','NvidiaSmi','CpuTemperature','StorageNetwork','Battery')){ Write-Output ("{0,-22} {1}" -f $p,$c.$p) }
}

function Write-SysInDoctorView {
    Write-Output "SysIn v$script:SysInVersion | DOCTOR"
    $checks=New-Object System.Collections.Generic.List[object]
    $checks.Add([pscustomobject]@{Name='Windows runtime';State=$(if(Test-SysInWindows){'PASS'}else{'FAIL'})})
    $checks.Add([pscustomobject]@{Name='PowerShell';State=$(if($PSVersionTable.PSVersion.Major -ge 5){'PASS'}else{'FAIL'})})
    foreach($name in @('SysIn.ps1','SysIn.Core.psm1','SysIn.Config.psm1')){ $checks.Add([pscustomobject]@{Name=$name;State=$(if(Test-Path -LiteralPath (Join-Path $PSScriptRoot $name)){'PASS'}else{'FAIL'})}) }
    try { $c=Get-SysInCapabilities; $checks.Add([pscustomobject]@{Name='CPU/memory provider';State=$(if($c.CpuMemory){'PASS'}else{'FAIL'})}); $checks.Add([pscustomobject]@{Name='GPU provider';State=$(if($c.NvidiaSmi -or $c.WindowsGpuCounters){'PASS'}else{'PARTIAL'})}) } catch { $checks.Add([pscustomobject]@{Name='Telemetry providers';State='FAIL'}) }
    foreach($x in $checks){Write-Output ('{0,-28} {1}' -f $x.Name,$x.State)}
}

function Get-OptionInt {
    param([string[]]$Arguments,[string[]]$Names,[int]$Default)
    for($i=0;$i -lt $Arguments.Count;$i++){ if($Arguments[$i].ToLowerInvariant() -in $Names){ if($i+1 -ge $Arguments.Count){throw "Missing value for $($Arguments[$i])"}; $v=0; if(-not [int]::TryParse($Arguments[$i+1],[ref]$v)){throw "Invalid integer '$($Arguments[$i+1])'"}; return $v } }
    return $Default
}

function Test-Option {
    param([string[]]$Arguments,[string[]]$Names)
    foreach($a in $Arguments){if($a.ToLowerInvariant() -in $Names){return $true}}; return $false
}

function Invoke-SysInCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Command,[string[]]$Arguments=@())
    $fps=Get-OptionInt $Arguments @('-fps','--fps') 20
    if($fps -lt 1 -or $fps -gt 20){throw 'FPS must be from 1 through 20.'}
    $compact=Test-Option $Arguments @('-compact','--compact')
    $snap=Test-Option $Arguments @('-snapshot','--snapshot')
    switch($Command.ToLowerInvariant()){
        'overview' {Invoke-SysIn -FPS $fps -InitialPage Overview -Compact:$compact -Snapshot:$snap}
        'cpu' {Invoke-SysIn -FPS $fps -InitialPage CPU -Compact:$compact -Snapshot:$snap}
        'gpu' {Invoke-SysIn -FPS $fps -InitialPage GPU -Compact:$compact -Snapshot:$snap}
        'memory' {Invoke-SysIn -FPS $fps -InitialPage Memory -Compact:$compact -Snapshot:$snap}
        'processes' {Invoke-SysIn -FPS $fps -InitialPage Processes -Compact:$compact -Snapshot:$snap}
        'snapshot' {Invoke-SysIn -FPS $fps -InitialPage Overview -Compact:$compact -Snapshot}
        'system' {Write-SysInSystemView}
        'storage' {Write-SysInStorageView}
        'network' {Write-SysInNetworkView}
        'sensors' {Write-SysInSensorsView}
        'capabilities' {Write-SysInCapabilitiesView}
        'doctor' {Write-SysInDoctorView}
        default {throw "Unknown SysIn command '$Command'. Run 'sysin help'."}
    }
}

Export-ModuleMember -Function Invoke-SysIn, Invoke-SysInCommand, Get-SysInSystemInfo, Get-SysInCapabilities
