Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:SysInVersion = '1.1.0'
$script:SysInChannel = 'stable'
$script:SysInRepository = 'doonchy16-cloud/SysIn'

function Write-SysInVersion { Write-Output "SysIn $script:SysInVersion ($script:SysInChannel)" }
function Write-SysInAbout {
@"
SysIn $script:SysInVersion
Windows System Intelligence
Channel: $script:SysInChannel
Repository: $script:SysInRepository

SysIn is a read-only-by-default Windows system telemetry CLI and live terminal dashboard.
"@.Trim() | Write-Output
}
function Write-SysInHelp {
@"
SysIn $script:SysInVersion - Windows System Intelligence

USAGE
  sysin [command] [options]
  SysIn -CPU | -GPU | -Memory | -Version | -Update

COMMANDS
  overview       Live system overview dashboard
  cpu            CPU telemetry dashboard
  gpu            GPU telemetry dashboard
  memory         Memory telemetry dashboard
  storage        Storage telemetry
  network        Network telemetry
  processes      Process telemetry dashboard
  sensors        Available temperature/fan/power sensors
  system         Static Windows and hardware information
  snapshot       One non-interactive telemetry snapshot
  doctor         Validate SysIn installation and providers
  capabilities   Show available telemetry capabilities
  version        Show installed SysIn version
  check-update   Check for a newer stable version
  update         Download and install a verified update
  config         Show or change SysIn user configuration
  help           Show this help
  about          Show product information

CONFIG
  sysin config [show]
  sysin config get <key>
  sysin config set <key> <value>
  sysin config reset
  sysin config path

GLOBAL OPTIONS
  -FPS <1-20>    Dashboard render target (default 20)
  -Compact       Compact dashboard layout

ALIASES
  -CPU -GPU -Memory -Storage -Network -Processes -Sensors -System
  -Snapshot -Version -CheckUpdate -Update -Help
  --version -v --help -h
"@.Trim() | Write-Output
}
function Resolve-SysInCommand {
    param([string[]]$Tokens)
    if($null-eq$Tokens-or$Tokens.Count-eq0){return'overview'}
    $first=[string]$Tokens[0]
    switch -Regex($first.ToLowerInvariant()){
      '^(-version|--version|-v|version)$'{return'version'};'^(-help|--help|-h|help)$'{return'help'};'^(-cpu|cpu)$'{return'cpu'};'^(-gpu|gpu)$'{return'gpu'};'^(-memory|-ram|memory|ram)$'{return'memory'};'^(-storage|-disk|storage|disk)$'{return'storage'};'^(-network|-net|network|net)$'{return'network'};'^(-processes|processes)$'{return'processes'};'^(-sensors|-temps|sensors|temps)$'{return'sensors'};'^(-system|system)$'{return'system'};'^(-snapshot|snapshot)$'{return'snapshot'};'^(-checkupdate|check-update)$'{return'check-update'};'^(-update|update)$'{return'update'};'^config$'{return'config'};'^doctor$'{return'doctor'};'^capabilities$'{return'capabilities'};'^about$'{return'about'};'^overview$'{return'overview'};default{return$first.ToLowerInvariant()}
    }
}
function Invoke-SysInConfigCommand {
    param([string[]]$Tokens)
    $module=Join-Path $PSScriptRoot 'SysIn.Config.psm1';if(-not(Test-Path -LiteralPath $module)){throw"SysIn runtime is incomplete: missing $module"};Import-Module $module -Force
    $sub=if($Tokens.Count-ge2){([string]$Tokens[1]).ToLowerInvariant()}else{'show'}
    switch($sub){
      'show'{$c=Get-SysInConfig;Write-Output"fps=$($c.fps)";Write-Output"updateChannel=$($c.updateChannel)";Write-Output"updateCheck=$($c.updateCheck)"}
      'get'{if($Tokens.Count-lt3){throw'Usage: sysin config get <key>'};$key=[string]$Tokens[2];$c=Get-SysInConfig;$p=$c.PSObject.Properties|Where-Object{$_.Name-ieq$key}|Select-Object -First 1;if($null-eq$p){throw"Unknown SysIn configuration key '$key'."};Write-Output$p.Value}
      'set'{if($Tokens.Count-lt4){throw'Usage: sysin config set <key> <value>'};$c=Set-SysInConfigValue -Key([string]$Tokens[2])-Value $Tokens[3];$p=$c.PSObject.Properties|Where-Object{$_.Name-ieq([string]$Tokens[2])}|Select-Object -First 1;Write-Output"$($p.Name)=$($p.Value)"}
      'reset'{[void](Reset-SysInConfig);Write-Output'SysIn configuration reset to defaults.'};'path'{Write-Output(Get-SysInConfigPath)};default{throw"Unknown config command '$sub'. Use: show, get, set, reset, path."}
    }
}
function Invoke-SysInUpdateCli {
    param([ValidateSet('check-update','update')][string]$Mode)
    $module=Join-Path $PSScriptRoot 'SysIn.Update.psm1';if(-not(Test-Path -LiteralPath $module)){throw"SysIn runtime is incomplete: missing $module"};Import-Module $module -Force
    if($Mode-eq'check-update'){
        $r=Invoke-SysInCheckUpdate -CurrentVersion $script:SysInVersion
        Write-Output"Installed: $($r.CurrentVersion)";Write-Output"Latest:    $($r.LatestVersion)";Write-Output"Channel:   $($r.Channel)"
        if($r.Status-eq'UpdateAvailable'){Write-Output'Update available. Run: SysIn -Update'}elseif($r.Status-eq'UpToDate'){Write-Output'You are up to date.'}else{Write-Output'This installation is newer than the published stable manifest.'}
    }else{
        $installRoot=Split-Path -Parent $PSScriptRoot
        $r=Invoke-SysInUpdate -CurrentVersion $script:SysInVersion -InstallRoot $installRoot
        if($r.Status-eq'Updated'){Write-Output"SysIn updated: $($r.PreviousVersion) -> $($r.Version)"}elseif($r.Status-eq'UpToDate'){Write-Output"SysIn $($r.Version) is already up to date."}else{Write-Output"SysIn $($r.Version) is newer than the published stable manifest."}
    }
}
$tokens=@($args);$command=Resolve-SysInCommand -Tokens $tokens
try{
    switch($command){
      'version'{Write-SysInVersion;exit 0};'help'{Write-SysInHelp;exit 0};'about'{Write-SysInAbout;exit 0};'config'{Invoke-SysInConfigCommand -Tokens $tokens;exit 0};'check-update'{Invoke-SysInUpdateCli 'check-update';exit 0};'update'{Invoke-SysInUpdateCli 'update';exit 0};default{$module=Join-Path $PSScriptRoot 'SysIn.Core.psm1';if(-not(Test-Path -LiteralPath $module)){Write-Error"SysIn runtime is incomplete: missing $module";exit 64};Import-Module $module -Force;Invoke-SysInCommand -Command $command -Arguments $tokens;exit 0}
    }
}catch{Write-Error $_;exit 1}
