Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:SysInVersion = '1.1.0'

if (-not ('SysIn.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace SysIn {
  [StructLayout(LayoutKind.Sequential)] public struct FILETIME { public uint Low; public uint High; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] public class MEMORYSTATUSEX {
    public uint dwLength; public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys;
    public ulong ullTotalPageFile; public ulong ullAvailPageFile; public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    public MEMORYSTATUSEX(){ dwLength=(uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); }
  }
  public static class NativeMethods {
    [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetSystemTimes(out FILETIME idle,out FILETIME kernel,out FILETIME user);
    [DllImport("kernel32.dll",CharSet=CharSet.Auto,SetLastError=true)] public static extern bool GlobalMemoryStatusEx([In,Out] MEMORYSTATUSEX value);
  }
}
'@
}

function Test-SysInWindows { [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT }
function Convert-FT([object]$x){ ([uint64]$x.High -shl 32) -bor [uint64]$x.Low }

function Get-CpuTimes {
    $i=New-Object SysIn.FILETIME; $k=New-Object SysIn.FILETIME; $u=New-Object SysIn.FILETIME
    if(-not [SysIn.NativeMethods]::GetSystemTimes([ref]$i,[ref]$k,[ref]$u)){return $null}
    [pscustomobject]@{Idle=Convert-FT $i;Kernel=Convert-FT $k;User=Convert-FT $u}
}
function Get-CpuPercent($a,$b){
    if($null -eq $a -or $null -eq $b){return 0.0}
    $idle=[double]($b.Idle-$a.Idle);$kernel=[double]($b.Kernel-$a.Kernel);$user=[double]($b.User-$a.User);$total=$kernel+$user
    if($total -le 0.0){return 0.0};$ratio=($total-$idle)/$total;$ratio=[math]::Max(0.0,[math]::Min(1.0,[double]$ratio));[math]::Round($ratio*100.0,1)
}
function Get-MemoryTelemetry {
    $m=New-Object SysIn.MEMORYSTATUSEX
    if(-not [SysIn.NativeMethods]::GlobalMemoryStatusEx($m)){return [pscustomobject]@{Total=0.0;Available=0.0;Used=0.0;Percent=0.0}}
    $total=[double]$m.ullTotalPhys;$avail=[double]$m.ullAvailPhys;$used=[math]::Max(0.0,[double]($total-$avail));$pct=if($total -gt 0.0){[math]::Round(($used/$total)*100.0,1)}else{0.0}
    [pscustomobject]@{Total=$total;Available=$avail;Used=$used;Percent=$pct}
}
function Format-Bytes([double]$v){if($v -ge 1TB){'{0:N2} TB'-f($v/1TB)}elseif($v -ge 1GB){'{0:N2} GB'-f($v/1GB)}elseif($v -ge 1MB){'{0:N1} MB'-f($v/1MB)}elseif($v -ge 1KB){'{0:N1} KB'-f($v/1KB)}else{'{0:N0} B'-f$v}}
function Format-Rate([double]$v){(Format-Bytes $v)+'/s'}
function Format-Uptime($bootTime){if($null-eq$bootTime){return 'N/A'};try{$span=(Get-Date)-[datetime]$bootTime;if($span.TotalSeconds-lt0){return 'N/A'};if($span.Days-gt0){return ('{0}d {1:00}h {2:00}m'-f$span.Days,$span.Hours,$span.Minutes)};return ('{0:00}h {1:00}m {2:00}s'-f[int]$span.TotalHours,$span.Minutes,$span.Seconds)}catch{return 'N/A'}}
function Get-Bar([double]$p,[int]$w=24){$p=[math]::Max(0.0,[math]::Min(100.0,$p));$n=[int][math]::Round(($p/100.0)*$w);'['+('#'*$n)+('-'*($w-$n))+']'}

function Get-SysInSystemInfo {
    if(-not(Test-SysInWindows)){throw 'SysIn V1.1 runtime telemetry requires Windows.'}
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop;$cs=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop;$cpu=@(Get-CimInstance Win32_Processor -ErrorAction Stop)[0]
    $gpus=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue|Where-Object{$_.Name -and $_.Name -notmatch 'Microsoft Basic Display'});$names=@($gpus|ForEach-Object{$_.Name});$sd=if($env:SystemDrive){$env:SystemDrive}else{'C:'}
    [pscustomobject]@{ComputerName=$env:COMPUTERNAME;Manufacturer=[string]$cs.Manufacturer;Model=[string]$cs.Model;OS=[string]$os.Caption;OSVersion=[string]$os.Version;Build=[string]$os.BuildNumber;BootTime=$os.LastBootUpTime;CpuName=([string]$cpu.Name).Trim();CpuCores=[int]$cpu.NumberOfCores;CpuLogical=[int]$cpu.NumberOfLogicalProcessors;CpuMaxMHz=[int]$cpu.MaxClockSpeed;GpuNames=$names;GpuName=if($names.Count){$names[0]}else{'GPU not detected'};TotalMemory=[double]$cs.TotalPhysicalMemory;SystemDrive=$sd}
}
function Get-NvidiaSmiPath {try{$c=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue;if($c -and $c.Source){return $c.Source}}catch{};if($env:ProgramFiles){$p=Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe';if(Test-Path -LiteralPath $p){return $p}};$null}
function Get-GpuTelemetry {
    param([string]$Nvidia)
    if($Nvidia){try{$line=&$Nvidia '--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,clocks.gr,fan.speed,driver_version' '--format=csv,noheader,nounits' 2>$null|Select-Object -First 1;if($line){$v=@($line-split','|ForEach-Object{$_.Trim()});if($v.Count-ge 9){return [pscustomobject]@{Name=$v[0];Utilization=[double]$v[1];VramUsedMB=[double]$v[2];VramTotalMB=[double]$v[3];TempC=[double]$v[4];PowerW=[double]$v[5];ClockMHz=[double]$v[6];FanPercent=[double]$v[7];Driver=$v[8];Provider='nvidia-smi'}}}}catch{}}
    $u=$null;try{$e=@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop|Where-Object{$_.Name-match'engtype_(3D|Graphics|Compute)'});if($e.Count){$sum=0.0;foreach($x in $e){$sum+=[double]$x.UtilizationPercentage};$u=[math]::Round([math]::Min(100.0,$sum),1)}}catch{}
    [pscustomobject]@{Name='Windows GPU';Utilization=$u;VramUsedMB=$null;VramTotalMB=$null;TempC=$null;PowerW=$null;ClockMHz=$null;FanPercent=$null;Driver=$null;Provider='Windows GPU counters'}
}
function Get-IoTelemetry([string]$drive){$dt=$null;$df=$null;try{$d=New-Object IO.DriveInfo($drive+'\');if($d.IsReady){$dt=[double]$d.TotalSize;$df=[double]$d.AvailableFreeSpace}}catch{};$r=0.0;$w=0.0;try{$x=Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop|Where-Object Name -eq '_Total'|Select-Object -First 1;if($x){$r=[double]$x.DiskReadBytesPersec;$w=[double]$x.DiskWriteBytesPersec}}catch{};$dn=0.0;$up=0.0;try{foreach($n in @(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop)){$dn+=[double]$n.BytesReceivedPersec;$up+=[double]$n.BytesSentPersec}}catch{};[pscustomobject]@{DriveTotal=$dt;DriveFree=$df;DiskRead=$r;DiskWrite=$w;NetDown=$dn;NetUp=$up}}
function Get-TopProcesses([int]$top=8){@(Get-Process -ErrorAction SilentlyContinue|Sort-Object WorkingSet64 -Descending|Select-Object -First $top|ForEach-Object{[pscustomobject]@{Name=$_.ProcessName;Id=$_.Id;Memory=[double]$_.WorkingSet64;CpuSeconds=if($null-eq$_.CPU){0.0}else{[double]$_.CPU}}})}
function Get-SysInCapabilities {if(-not(Test-SysInWindows)){throw 'SysIn V1.1 runtime telemetry requires Windows.'};$nv=[bool](Get-NvidiaSmiPath);$gc=$false;try{$null=Get-CimClass Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop;$gc=$true}catch{};$bat=$false;try{$bat=@(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count-gt 0}catch{};$tmp=$false;try{$tmp=@(Get-CimInstance -Namespace root/wmi MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue).Count-gt 0}catch{};[pscustomobject]@{CpuMemory=$true;WindowsGpuCounters=$gc;NvidiaSmi=$nv;CpuTemperature=$tmp;StorageNetwork=$true;Battery=$bat}}

function Get-State($static,$prev,$nv){Start-Sleep -Milliseconds 100;$now=Get-CpuTimes;[pscustomobject]@{Cpu=Get-CpuPercent $prev $now;CpuTimes=$now;Memory=Get-MemoryTelemetry;GPU=Get-GpuTelemetry $nv;IO=Get-IoTelemetry $static.SystemDrive;Processes=Get-TopProcesses 8;Time=Get-Date}}
function Write-Snapshot($page,$s,$x){
    switch($page){
      'CPU'{Write-Output "SysIn v$script:SysInVersion | CPU";Write-Output "CPU: $($s.CpuName)";Write-Output ('Usage: {0:N1}% {1}'-f$x.Cpu,(Get-Bar $x.Cpu 30));Write-Output "Cores: $($s.CpuCores) physical / $($s.CpuLogical) logical"}
      'GPU'{Write-Output "SysIn v$script:SysInVersion | GPU";Write-Output "GPU: $($s.GpuName)";Write-Output "Provider: $($x.GPU.Provider)";Write-Output ('Usage: '+$(if($null-eq$x.GPU.Utilization){'N/A'}else{"$($x.GPU.Utilization)%"}));Write-Output ('Temperature: '+$(if($null-eq$x.GPU.TempC){'N/A'}else{"$($x.GPU.TempC) C"}))}
      'Memory'{Write-Output "SysIn v$script:SysInVersion | MEMORY";Write-Output "Physical RAM: $(Format-Bytes $x.Memory.Used) used / $(Format-Bytes $x.Memory.Total) total ($($x.Memory.Percent)%)";Write-Output "Available: $(Format-Bytes $x.Memory.Available)"}
      'Processes'{Write-Output "SysIn v$script:SysInVersion | PROCESSES";Write-Output 'TOP PROCESSES BY MEMORY';foreach($p in $x.Processes){Write-Output ('{0,-25} PID {1,6} RAM {2}'-f$p.Name,$p.Id,(Format-Bytes $p.Memory))}}
      default{Write-Output "SysIn v$script:SysInVersion | OVERVIEW | $($x.Time.ToString('yyyy-MM-dd HH:mm:ss'))";Write-Output ('CPU {0} {1:N1}%'-f(Get-Bar $x.Cpu),$x.Cpu);$gu=if($null-eq$x.GPU.Utilization){0.0}else{[double]$x.GPU.Utilization};Write-Output ('GPU {0} {1}'-f(Get-Bar $gu),$(if($null-eq$x.GPU.Utilization){'N/A'}else{"$($x.GPU.Utilization)%"}));Write-Output "RAM $(Get-Bar $x.Memory.Percent) $($x.Memory.Percent)% $(Format-Bytes $x.Memory.Used)/$(Format-Bytes $x.Memory.Total)";Write-Output "DISK R $(Format-Rate $x.IO.DiskRead) W $(Format-Rate $x.IO.DiskWrite) | NET down $(Format-Rate $x.IO.NetDown) up $(Format-Rate $x.IO.NetUp)";Write-Output "UPTIME $(Format-Uptime $s.BootTime)"}
    }
}
function Invoke-SysIn {param([ValidateRange(1,20)][int]$FPS=20,[ValidateSet('Overview','CPU','GPU','Memory','Processes')][string]$InitialPage='Overview',[switch]$Compact,[switch]$Snapshot);if(-not(Test-SysInWindows)){throw 'SysIn V1.1 is a Windows dashboard and requires Windows PowerShell 5.1+ or PowerShell 7+ on Windows.'};$s=Get-SysInSystemInfo;$nv=Get-NvidiaSmiPath;$prev=Get-CpuTimes;if($Snapshot){Write-Snapshot $InitialPage $s (Get-State $s $prev $nv);return};$page=$InitialPage;$paused=$false;$state=$null;$last=[datetime]::MinValue;$minCpu=100.0;$peakCpu=0.0;$minRam=100.0;$peakRam=0.0;$cursor=$true;try{try{$cursor=[Console]::CursorVisible;[Console]::CursorVisible=$false;[Console]::Clear()}catch{};while($true){$start=Get-Date;if(-not$paused){$now=Get-Date;$ct=Get-CpuTimes;$cpu=Get-CpuPercent $prev $ct;$prev=$ct;$mem=Get-MemoryTelemetry;if($null-eq$state-or($now-$last).TotalMilliseconds-ge750){$gpu=Get-GpuTelemetry $nv;$io=Get-IoTelemetry $s.SystemDrive;$procs=Get-TopProcesses 8;$last=$now}else{$gpu=$state.GPU;$io=$state.IO;$procs=$state.Processes};$state=[pscustomobject]@{Cpu=$cpu;Memory=$mem;GPU=$gpu;IO=$io;Processes=$procs;Time=$now};$minCpu=[math]::Min($minCpu,[double]$cpu);$peakCpu=[math]::Max($peakCpu,[double]$cpu);$minRam=[math]::Min($minRam,[double]$mem.Percent);$peakRam=[math]::Max($peakRam,[double]$mem.Percent)};try{[Console]::SetCursorPosition(0,0)}catch{Clear-Host};$lines=New-Object Collections.Generic.List[string];$lines.Add("SysIn v$script:SysInVersion | $($page.ToUpperInvariant()) | LIVE $FPS FPS$(if($paused){' | PAUSED'}else{''})");$lines.Add('='*78);if($state){if($page-eq'Overview'){$lines.Add("CPU $(Get-Bar $state.Cpu 25) $($state.Cpu)% | min $minCpu peak $peakCpu");$gu=if($null-eq$state.GPU.Utilization){0.0}else{[double]$state.GPU.Utilization};$lines.Add("GPU $(Get-Bar $gu 25) $(if($null-eq$state.GPU.Utilization){'N/A'}else{"$($state.GPU.Utilization)%"}) | $($s.GpuName)");$lines.Add("RAM $(Get-Bar $state.Memory.Percent 25) $($state.Memory.Percent)% | $(Format-Bytes $state.Memory.Used)/$(Format-Bytes $state.Memory.Total)");$lines.Add("DISK R $(Format-Rate $state.IO.DiskRead) W $(Format-Rate $state.IO.DiskWrite) | NET D $(Format-Rate $state.IO.NetDown) U $(Format-Rate $state.IO.NetUp)");$lines.Add("UPTIME $(Format-Uptime $s.BootTime)")}elseif($page-eq'CPU'){$lines.Add("CPU $($s.CpuName)");$lines.Add("$(Get-Bar $state.Cpu 30) $($state.Cpu)% | min $minCpu peak $peakCpu");$lines.Add("$($s.CpuCores) cores / $($s.CpuLogical) logical | max $($s.CpuMaxMHz) MHz")}elseif($page-eq'GPU'){$gu=if($null-eq$state.GPU.Utilization){0.0}else{[double]$state.GPU.Utilization};$lines.Add("GPU $($s.GpuName) | $($state.GPU.Provider)");$lines.Add("$(Get-Bar $gu 30) $(if($null-eq$state.GPU.Utilization){'N/A'}else{"$($state.GPU.Utilization)%"})");$lines.Add("Temp $(if($null-eq$state.GPU.TempC){'N/A'}else{"$($state.GPU.TempC) C"}) | VRAM $(if($null-eq$state.GPU.VramUsedMB){'N/A'}else{"$($state.GPU.VramUsedMB)/$($state.GPU.VramTotalMB) MB"})")}elseif($page-eq'Memory'){$lines.Add('MEMORY');$lines.Add("$(Get-Bar $state.Memory.Percent 30) $($state.Memory.Percent)%");$lines.Add("Physical RAM $(Format-Bytes $state.Memory.Used) / $(Format-Bytes $state.Memory.Total)")}else{$lines.Add('TOP PROCESSES BY MEMORY');foreach($p in $state.Processes){$lines.Add(('{0,-25} PID {1,6} RAM {2}'-f$p.Name,$p.Id,(Format-Bytes $p.Memory)))}}};$lines.Add('='*78);$lines.Add('[1] Overview [2] CPU [3] GPU [4] Memory [5] Processes [F] FPS [P] Pause [R] Reset [Q] Quit');$width=[math]::Max(20,[Console]::WindowWidth-1);$height=[math]::Max(10,[Console]::WindowHeight-1);while($lines.Count-lt$height){$lines.Add('')};foreach($line in $lines){$o=if($line.Length-gt$width){$line.Substring(0,$width)}else{$line};Write-Host $o.PadRight($width)};while([Console]::KeyAvailable){$k=[Console]::ReadKey($true);switch($k.Key){'D1'{$page='Overview'};'NumPad1'{$page='Overview'};'D2'{$page='CPU'};'NumPad2'{$page='CPU'};'D3'{$page='GPU'};'NumPad3'{$page='GPU'};'D4'{$page='Memory'};'NumPad4'{$page='Memory'};'D5'{$page='Processes'};'NumPad5'{$page='Processes'};'F'{$FPS=switch($FPS){20{10};10{5};5{1};default{20}}};'P'{$paused=-not$paused};'R'{$minCpu=100.0;$peakCpu=0.0;$minRam=100.0;$peakRam=0.0};'Q'{return};'Escape'{return}}};$delay=[int][math]::Floor((1000.0/$FPS)-((Get-Date)-$start).TotalMilliseconds);if($delay-gt0){Start-Sleep -Milliseconds $delay}}}finally{try{[Console]::CursorVisible=$cursor}catch{};Write-Host ''}}

function Write-SystemView{$s=Get-SysInSystemInfo;Write-Output "SysIn v$script:SysInVersion | SYSTEM";Write-Output "Computer: $($s.ComputerName)";Write-Output "Model: $($s.Manufacturer) $($s.Model)";Write-Output "OS: $($s.OS) $($s.OSVersion) build $($s.Build)";Write-Output "CPU: $($s.CpuName) | $($s.CpuCores) cores / $($s.CpuLogical) logical";Write-Output "GPU: $($s.GpuNames-join'; ')";Write-Output "RAM: $(Format-Bytes $s.TotalMemory)";Write-Output "Uptime: $(Format-Uptime $s.BootTime)"}
function Write-StorageView{$s=Get-SysInSystemInfo;$i=Get-IoTelemetry $s.SystemDrive;Write-Output "SysIn v$script:SysInVersion | STORAGE";Write-Output "System drive: $($s.SystemDrive) | Capacity $(Format-Bytes $i.DriveTotal) | Free $(Format-Bytes $i.DriveFree)";Write-Output "Read $(Format-Rate $i.DiskRead) | Write $(Format-Rate $i.DiskWrite)"}
function Write-NetworkView{$s=Get-SysInSystemInfo;$i=Get-IoTelemetry $s.SystemDrive;Write-Output "SysIn v$script:SysInVersion | NETWORK";Write-Output "Download $(Format-Rate $i.NetDown) | Upload $(Format-Rate $i.NetUp)";try{foreach($n in @(Get-CimInstance Win32_NetworkAdapter -Filter 'NetEnabled=True' -ErrorAction SilentlyContinue)){Write-Output "Adapter: $($n.Name) | Speed $(Format-Rate ([double]$n.Speed))"}}catch{}}
function Write-SensorsView{$g=Get-GpuTelemetry (Get-NvidiaSmiPath);Write-Output "SysIn v$script:SysInVersion | SENSORS";Write-Output ('GPU temperature: '+$(if($null-eq$g.TempC){'N/A'}else{"$($g.TempC) C"}));Write-Output ('GPU power: '+$(if($null-eq$g.PowerW){'N/A'}else{"$($g.PowerW) W"}));Write-Output ('GPU fan: '+$(if($null-eq$g.FanPercent){'N/A'}else{"$($g.FanPercent)%"}));$t=$null;try{$z=Get-CimInstance -Namespace root/wmi MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue|Select-Object -First 1;if($z){$t=[math]::Round(([double]$z.CurrentTemperature/10.0)-273.15,1)}}catch{};Write-Output ('CPU/ACPI temperature: '+$(if($null-eq$t){'N/A'}else{"$t C"}))}
function Write-CapabilitiesView{$c=Get-SysInCapabilities;Write-Output "SysIn v$script:SysInVersion | CAPABILITIES";foreach($p in @('CpuMemory','WindowsGpuCounters','NvidiaSmi','CpuTemperature','StorageNetwork','Battery')){Write-Output ('{0,-22} {1}'-f$p,$c.$p)}}

function Normalize-SysInDoctorPath([string]$Path){if([string]::IsNullOrWhiteSpace($Path)){return ''};$Path.Trim().TrimEnd('\','/').ToLowerInvariant()}
function Invoke-SysInDoctor {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = (Split-Path -Parent $PSScriptRoot),
        [string]$UserPath
    )

    $checks = New-Object System.Collections.Generic.List[object]
    $checks.Add([pscustomobject]@{Name='Windows runtime';Status=$(if(Test-SysInWindows){'PASS'}else{'FAIL'});Detail=[Environment]::OSVersion.VersionString})
    $checks.Add([pscustomobject]@{Name='PowerShell version';Status=$(if($PSVersionTable.PSVersion -ge [version]'5.1'){'PASS'}else{'FAIL'});Detail=[string]$PSVersionTable.PSVersion})

    $required = @('SysIn.cmd','src\SysIn.ps1','src\SysIn.Core.psm1','src\SysIn.Config.psm1','src\SysIn.Update.psm1','uninstall.ps1')
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallRoot $_) -PathType Leaf) })
    $checks.Add([pscustomobject]@{Name='Runtime files';Status=$(if($missing.Count -eq 0){'PASS'}else{'FAIL'});Detail=$(if($missing.Count -eq 0){'all required files present'}else{'missing: '+($missing -join ', ')})})

    if($PSBoundParameters.ContainsKey('UserPath')){$pathValue=$UserPath}else{$pathValue=[Environment]::GetEnvironmentVariable('Path',[EnvironmentVariableTarget]::User)}
    $target=Normalize-SysInDoctorPath $InstallRoot;$pathRegistered=$false
    foreach($entry in @([string]$pathValue -split ';')){if((Normalize-SysInDoctorPath $entry)-eq$target){$pathRegistered=$true;break}}
    $checks.Add([pscustomobject]@{Name='User PATH';Status=$(if($pathRegistered){'PASS'}else{'PARTIAL'});Detail=$(if($pathRegistered){'install directory registered'}else{'install directory is not registered in current-user PATH'})})

    $configModule=Join-Path $PSScriptRoot 'SysIn.Config.psm1'
    try{Import-Module $configModule -Force -ErrorAction Stop;$null=Get-SysInConfig -ErrorAction Stop;$configStatus='PASS';$configDetail='configuration is valid (or defaults are active)'}catch{$configStatus='FAIL';$configDetail=$_.Exception.Message}
    $checks.Add([pscustomobject]@{Name='Configuration';Status=$configStatus;Detail=$configDetail})

    try{$c=Get-SysInCapabilities;$gpuAvailable=[bool]($c.NvidiaSmi -or $c.WindowsGpuCounters);$providerStatus=if($c.CpuMemory -and $c.StorageNetwork -and $gpuAvailable){'PASS'}elseif($c.CpuMemory -and $c.StorageNetwork){'PARTIAL'}else{'FAIL'};$providerDetail="CPU/RAM=$($c.CpuMemory); WindowsGPU=$($c.WindowsGpuCounters); NVIDIA=$($c.NvidiaSmi); CPUtemp=$($c.CpuTemperature); Storage/Network=$($c.StorageNetwork); Battery=$($c.Battery)"}catch{$providerStatus='FAIL';$providerDetail=$_.Exception.Message}
    $checks.Add([pscustomobject]@{Name='Providers';Status=$providerStatus;Detail=$providerDetail})

    $overall=if(@($checks|Where-Object Status -eq 'FAIL').Count -gt 0){'FAIL'}elseif(@($checks|Where-Object Status -eq 'PARTIAL').Count -gt 0){'PARTIAL'}else{'PASS'}
    [pscustomobject]@{OverallStatus=$overall;Checks=$checks.ToArray()}
}
function Write-DoctorView{$d=Invoke-SysInDoctor;Write-Output "SysIn v$script:SysInVersion | DOCTOR";foreach($check in @($d.Checks)){Write-Output ('{0,-28} {1,-7} {2}'-f$check.Name,$check.Status,$check.Detail)};Write-Output ('Overall                      '+$d.OverallStatus)}
function HasOpt([string[]]$a,[string[]]$n){foreach($x in $a){if($x.ToLowerInvariant()-in$n){return $true}};$false}
function Get-SysInDashboardFps([string[]]$Arguments){$configModule=Join-Path $PSScriptRoot 'SysIn.Config.psm1';if(-not(Test-Path -LiteralPath $configModule)){throw "SysIn runtime is incomplete: missing $configModule"};Import-Module $configModule -Force;Get-SysInEffectiveFps -Arguments $Arguments}
function Invoke-SysInCommand{param([Parameter(Mandatory=$true)][string]$Command,[string[]]$Arguments=@());$compact=HasOpt $Arguments @('-compact','--compact');$snap=HasOpt $Arguments @('-snapshot','--snapshot');switch($Command.ToLowerInvariant()){'overview'{$fps=Get-SysInDashboardFps $Arguments;Invoke-SysIn -FPS $fps -InitialPage Overview -Compact:$compact -Snapshot:$snap};'cpu'{$fps=Get-SysInDashboardFps $Arguments;Invoke-SysIn -FPS $fps -InitialPage CPU -Compact:$compact -Snapshot:$snap};'gpu'{$fps=Get-SysInDashboardFps $Arguments;Invoke-SysIn -FPS $fps -InitialPage GPU -Compact:$compact -Snapshot:$snap};'memory'{$fps=Get-SysInDashboardFps $Arguments;Invoke-SysIn -FPS $fps -InitialPage Memory -Compact:$compact -Snapshot:$snap};'processes'{$fps=Get-SysInDashboardFps $Arguments;Invoke-SysIn -FPS $fps -InitialPage Processes -Compact:$compact -Snapshot:$snap};'snapshot'{$fps=Get-SysInDashboardFps $Arguments;Invoke-SysIn -FPS $fps -Snapshot};'system'{Write-SystemView};'storage'{Write-StorageView};'network'{Write-NetworkView};'sensors'{Write-SensorsView};'capabilities'{Write-CapabilitiesView};'doctor'{Write-DoctorView};default{throw "Unknown SysIn command '$Command'. Run 'sysin help'."}}}

Export-ModuleMember -Function Invoke-SysIn,Invoke-SysInCommand,Get-SysInSystemInfo,Get-SysInCapabilities,Invoke-SysInDoctor
