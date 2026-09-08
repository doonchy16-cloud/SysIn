Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:SysInVersion = '1.1.0'
$script:SysInChannel = 'stable'
$script:SysInRepository = 'doonchy16-cloud/SysIn'

function Write-SysInVersion {
    Write-Output "SysIn $script:SysInVersion ($script:SysInChannel)"
}

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

    if ($null -eq $Tokens -or $Tokens.Count -eq 0) { return 'overview' }
    $first = [string]$Tokens[0]
    switch -Regex ($first.ToLowerInvariant()) {
        '^(-version|--version|-v|version)$' { return 'version' }
        '^(-help|--help|-h|help)$' { return 'help' }
        '^(-cpu|cpu)$' { return 'cpu' }
        '^(-gpu|gpu)$' { return 'gpu' }
        '^(-memory|-ram|memory|ram)$' { return 'memory' }
        '^(-storage|-disk|storage|disk)$' { return 'storage' }
        '^(-network|-net|network|net)$' { return 'network' }
        '^(-processes|processes)$' { return 'processes' }
        '^(-sensors|-temps|sensors|temps)$' { return 'sensors' }
        '^(-system|system)$' { return 'system' }
        '^(-snapshot|snapshot)$' { return 'snapshot' }
        '^(-checkupdate|check-update)$' { return 'check-update' }
        '^(-update|update)$' { return 'update' }
        '^config$' { return 'config' }
        '^doctor$' { return 'doctor' }
        '^capabilities$' { return 'capabilities' }
        '^about$' { return 'about' }
        '^overview$' { return 'overview' }
        default { return $first.ToLowerInvariant() }
    }
}

$tokens = @($args)
$command = Resolve-SysInCommand -Tokens $tokens

try {
    switch ($command) {
        'version' { Write-SysInVersion; exit 0 }
        'help' { Write-SysInHelp; exit 0 }
        'about' { Write-SysInAbout; exit 0 }
        default {
            $modulePath = Join-Path $PSScriptRoot 'SysIn.Core.psm1'
            if (-not (Test-Path -LiteralPath $modulePath)) {
                Write-Error "SysIn runtime is incomplete: missing $modulePath"
                exit 64
            }
            Import-Module $modulePath -Force
            if (Get-Command Invoke-SysInCommand -ErrorAction SilentlyContinue) {
                Invoke-SysInCommand -Command $command -Arguments $tokens
                exit 0
            }
            Write-Error "Command is not implemented in this SysIn build: $command"
            exit 64
        }
    }
} catch {
    Write-Error $_
    exit 1
}
