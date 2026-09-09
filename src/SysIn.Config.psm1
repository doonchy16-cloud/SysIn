Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:DefaultConfig = [ordered]@{
    fps = 20
    updateChannel = 'stable'
    updateCheck = 'manual'
}

function Get-SysInConfigPath {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not available; SysIn cannot determine the user configuration path.'
    }
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'SysIn') 'config.json')
}

function New-SysInDefaultConfig {
    return [pscustomobject]@{
        fps = [int]$script:DefaultConfig.fps
        updateChannel = [string]$script:DefaultConfig.updateChannel
        updateCheck = [string]$script:DefaultConfig.updateCheck
    }
}

function ConvertTo-SysInFps {
    param($Value)
    $parsed = 0
    if (-not [int]::TryParse([string]$Value, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 20) {
        throw "Invalid SysIn fps '$Value'. Expected an integer from 1 through 20."
    }
    return $parsed
}

function ConvertTo-SysInConfigValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)]$Value
    )

    switch ($Key.ToLowerInvariant()) {
        'fps' { return (ConvertTo-SysInFps $Value) }
        'updatechannel' {
            if ([string]$Value -cne 'stable') {
                throw "Invalid SysIn updateChannel '$Value'. V1.1 supports only 'stable'."
            }
            return 'stable'
        }
        'updatecheck' {
            $mode = ([string]$Value).ToLowerInvariant()
            if ($mode -notin @('manual','daily')) {
                throw "Invalid SysIn updateCheck '$Value'. Expected 'manual' or 'daily'."
            }
            return $mode
        }
        default { throw "Unknown SysIn configuration key '$Key'." }
    }
}

function Test-SysInConfigObject {
    param([Parameter(Mandatory=$true)]$Config)

    $allowed = @('fps','updateChannel','updateCheck')
    foreach ($property in @($Config.PSObject.Properties)) {
        if ($property.Name -notin $allowed) {
            throw "Unknown SysIn configuration key '$($property.Name)' in config file."
        }
    }

    foreach ($required in $allowed) {
        if ($null -eq $Config.PSObject.Properties[$required]) {
            throw "SysIn configuration is missing required key '$required'."
        }
    }

    [void](ConvertTo-SysInConfigValue -Key 'fps' -Value $Config.fps)
    [void](ConvertTo-SysInConfigValue -Key 'updateChannel' -Value $Config.updateChannel)
    [void](ConvertTo-SysInConfigValue -Key 'updateCheck' -Value $Config.updateCheck)
    return $true
}

function Save-SysInConfig {
    param([Parameter(Mandatory=$true)]$Config)

    [void](Test-SysInConfigObject -Config $Config)
    $path = Get-SysInConfigPath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $tempPath = "$path.tmp.$([guid]::NewGuid().ToString('N'))"
    try {
        $json = $Config | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText($tempPath, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tempPath -Destination $path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SysInConfig {
    $path = Get-SysInConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        return (New-SysInDefaultConfig)
    }

    try {
        $config = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "SysIn configuration is invalid JSON: $($_.Exception.Message)"
    }

    [void](Test-SysInConfigObject -Config $config)
    return [pscustomobject]@{
        fps = ConvertTo-SysInConfigValue -Key 'fps' -Value $config.fps
        updateChannel = ConvertTo-SysInConfigValue -Key 'updateChannel' -Value $config.updateChannel
        updateCheck = ConvertTo-SysInConfigValue -Key 'updateCheck' -Value $config.updateCheck
    }
}

function Get-SysInEffectiveFps {
    param([string[]]$Arguments = @())

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $token = ([string]$Arguments[$i]).ToLowerInvariant()
        if ($token -in @('-fps','--fps')) {
            if ($i + 1 -ge $Arguments.Count) {
                throw "Missing value for $($Arguments[$i])"
            }
            return (ConvertTo-SysInFps $Arguments[$i + 1])
        }
    }

    $config = Get-SysInConfig
    return [int]$config.fps
}

function Set-SysInConfigValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)]$Value
    )

    $canonicalKey = switch ($Key.ToLowerInvariant()) {
        'fps' { 'fps' }
        'updatechannel' { 'updateChannel' }
        'updatecheck' { 'updateCheck' }
        default { throw "Unknown SysIn configuration key '$Key'." }
    }

    $normalized = ConvertTo-SysInConfigValue -Key $canonicalKey -Value $Value
    $config = Get-SysInConfig
    $config.PSObject.Properties[$canonicalKey].Value = $normalized
    Save-SysInConfig -Config $config
    return $config
}

function Reset-SysInConfig {
    $config = New-SysInDefaultConfig
    Save-SysInConfig -Config $config
    return $config
}

Export-ModuleMember -Function Get-SysInConfigPath, Get-SysInConfig, Get-SysInEffectiveFps, Set-SysInConfigValue, Reset-SysInConfig
