[CmdletBinding()]
param(
    [string]$InstallRoot = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\SysIn' } else { throw 'LOCALAPPDATA is not available.' }),
    [switch]$NoPathChange,
    [switch]$PurgeConfig
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$knownFiles = @(
    'SysIn.cmd',
    'src\SysIn.ps1',
    'src\SysIn.Core.psm1',
    'src\SysIn.Config.psm1',
    'src\SysIn.Update.psm1',
    'uninstall.ps1'
)

function Normalize-SysInPathEntry {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().TrimEnd('\','/').ToLowerInvariant()
}

function Remove-SysInUserPathEntry {
    param([Parameter(Mandatory=$true)][string]$PathToRemove)

    $current = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    if ($null -eq $current) { $current = '' }
    $target = Normalize-SysInPathEntry $PathToRemove
    $kept = New-Object System.Collections.Generic.List[string]

    foreach ($entry in @($current -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ((Normalize-SysInPathEntry $entry) -ne $target) { $kept.Add($entry) }
    }

    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), [EnvironmentVariableTarget]::User)

    $processKept = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($env:Path -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ((Normalize-SysInPathEntry $entry) -ne $target) { $processKept.Add($entry) }
    }
    $env:Path = $processKept -join ';'
}

if (-not $NoPathChange) {
    Remove-SysInUserPathEntry -PathToRemove $InstallRoot
}

foreach ($relative in $knownFiles) {
    $target = Join-Path $InstallRoot $relative
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
    }
}

$srcDir = Join-Path $InstallRoot 'src'
if (Test-Path -LiteralPath $srcDir -PathType Container) {
    if (@(Get-ChildItem -LiteralPath $srcDir -Force).Count -eq 0) {
        Remove-Item -LiteralPath $srcDir -Force
    }
}

if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
    if (@(Get-ChildItem -LiteralPath $InstallRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $InstallRoot -Force
    }
}

if ($PurgeConfig -and $env:LOCALAPPDATA) {
    $configDir = Join-Path $env:LOCALAPPDATA 'SysIn'
    $configPath = Join-Path $configDir 'config.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        Remove-Item -LiteralPath $configPath -Force
    }
    if (Test-Path -LiteralPath $configDir -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $configDir -Force).Count -eq 0) {
            Remove-Item -LiteralPath $configDir -Force
        }
    }
}

Write-Output "SysIn uninstalled from: $InstallRoot"
if (-not $PurgeConfig) {
    Write-Output 'User configuration was preserved.'
}
