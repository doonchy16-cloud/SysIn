[CmdletBinding()]
param(
    [string]$InstallRoot = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\SysIn' } else { throw 'LOCALAPPDATA is not available.' }),
    [string]$SourceRoot,
    [string]$ManifestUri = 'https://raw.githubusercontent.com/doonchy16-cloud/SysIn/main/release/manifest.json',
    [switch]$NoPathChange
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

function Add-SysInUserPathEntry {
    param([Parameter(Mandatory=$true)][string]$PathToAdd)

    $current = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    if ($null -eq $current) { $current = '' }
    $target = Normalize-SysInPathEntry $PathToAdd
    $entries = New-Object System.Collections.Generic.List[string]
    $found = $false

    foreach ($entry in @($current -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ((Normalize-SysInPathEntry $entry) -eq $target) { $found = $true }
        $entries.Add($entry)
    }
    if (-not $found) { $entries.Add($PathToAdd) }
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), [EnvironmentVariableTarget]::User)

    $processFound = $false
    foreach ($entry in @($env:Path -split ';')) {
        if ((Normalize-SysInPathEntry $entry) -eq $target) { $processFound = $true; break }
    }
    if (-not $processFound) {
        if ([string]::IsNullOrWhiteSpace($env:Path)) { $env:Path = $PathToAdd }
        else { $env:Path = $env:Path.TrimEnd(';') + ';' + $PathToAdd }
    }
}

function Test-SysInHttpsUri {
    param([Parameter(Mandatory=$true)][string]$Value,[string]$Label='URI')
    $uri = $null
    if (-not [uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https') {
        throw "$Label must use HTTPS."
    }
    return $uri
}

function Get-SysInBootstrapManifest {
    param([Parameter(Mandatory=$true)][string]$Uri)
    $validated = Test-SysInHttpsUri -Value $Uri -Label 'SysIn manifest URI'
    try { $manifest = Invoke-RestMethod -Uri $validated.AbsoluteUri -Method Get -ErrorAction Stop }
    catch { throw "Unable to retrieve SysIn manifest: $($_.Exception.Message)" }

    foreach ($field in @('product','version','channel','minimumPowerShell','files')) {
        if ($null -eq $manifest.PSObject.Properties[$field]) { throw "SysIn manifest is missing required field '$field'." }
    }
    if ([string]$manifest.product -cne 'SysIn') { throw "Manifest product must be 'SysIn'." }
    if ([string]$manifest.channel -cne 'stable') { throw 'Installer accepts only the stable SysIn channel.' }
    try { $minimum = [version]([string]$manifest.minimumPowerShell) }
    catch { throw 'Manifest minimumPowerShell must be a numeric version.' }
    if ($PSVersionTable.PSVersion -lt $minimum) { throw "SysIn requires PowerShell $minimum or newer." }

    $entries = @($manifest.files)
    $byTarget = @{}
    foreach ($entry in $entries) {
        foreach ($field in @('target','url','sha256')) {
            if ($null -eq $entry.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$entry.$field)) {
                throw "SysIn manifest file entry is missing '$field'."
            }
        }
        $target = ([string]$entry.target).Replace('/','\')
        if ($knownFiles -notcontains $target) { throw "Manifest contains unsupported runtime target '$target'." }
        if ($byTarget.ContainsKey($target.ToLowerInvariant())) { throw "Manifest contains duplicate runtime target '$target'." }
        [void](Test-SysInHttpsUri -Value ([string]$entry.url) -Label "Runtime URL for '$target'")
        if ([string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "Manifest SHA-256 for '$target' is invalid." }
        $byTarget[$target.ToLowerInvariant()] = $entry
    }
    foreach ($relative in $knownFiles) {
        if (-not $byTarget.ContainsKey($relative.ToLowerInvariant())) { throw "Manifest is missing required runtime target '$relative'." }
    }
    return $manifest
}

function Stage-SysInRuntimeFromSource {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$StageRoot)
    foreach ($relative in $knownFiles) {
        $source = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Local SysIn source is missing '$relative'." }
        $destination = Join-Path $StageRoot $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
    }
}

function Stage-SysInRuntimeFromManifest {
    param([Parameter(Mandatory=$true)]$Manifest,[Parameter(Mandatory=$true)][string]$StageRoot)
    $byTarget = @{}
    foreach ($entry in @($Manifest.files)) { $byTarget[([string]$entry.target).Replace('/','\').ToLowerInvariant()] = $entry }

    foreach ($relative in $knownFiles) {
        $entry = $byTarget[$relative.ToLowerInvariant()]
        $destination = Join-Path $StageRoot $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Invoke-WebRequest -Uri ([string]$entry.url) -OutFile $destination -UseBasicParsing -ErrorAction Stop
        $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $expected = ([string]$entry.sha256).ToLowerInvariant()
        if ($actual -ne $expected) { throw "SHA-256 verification failed for '$relative'. Expected $expected, received $actual." }
    }
}

if ([string]::IsNullOrWhiteSpace($InstallRoot)) { throw 'SysIn install root cannot be empty.' }
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'SysIn V1.1 can only be installed on Windows.' }

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('SysIn-install-' + [guid]::NewGuid().ToString('N'))
$stageRoot = Join-Path $workRoot 'stage'
$backupRoot = Join-Path $workRoot 'backup'
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

$records = New-Object System.Collections.Generic.List[object]
try {
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $resolvedSource = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
        Stage-SysInRuntimeFromSource -Root $resolvedSource -StageRoot $stageRoot
    } else {
        $manifest = Get-SysInBootstrapManifest -Uri $ManifestUri
        Stage-SysInRuntimeFromManifest -Manifest $manifest -StageRoot $stageRoot
    }

    foreach ($relative in $knownFiles) {
        $destination = Join-Path $InstallRoot $relative
        $backup = Join-Path $backupRoot $relative
        $existed = Test-Path -LiteralPath $destination -PathType Leaf
        if ($existed) {
            $backupParent = Split-Path -Parent $backup
            if (-not (Test-Path -LiteralPath $backupParent)) { New-Item -ItemType Directory -Path $backupParent -Force | Out-Null }
            Copy-Item -LiteralPath $destination -Destination $backup -Force -ErrorAction Stop
        }
        $records.Add([pscustomobject]@{ Relative=$relative; Destination=$destination; Backup=$backup; Existed=$existed; Replaced=$false })
    }

    try {
        foreach ($record in $records) {
            $source = Join-Path $stageRoot $record.Relative
            $parent = Split-Path -Parent $record.Destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $source -Destination $record.Destination -Force -ErrorAction Stop
            $record.Replaced = $true
        }
    } catch {
        $installError = $_
        foreach ($record in $records) {
            if ($record.Existed -and (Test-Path -LiteralPath $record.Backup -PathType Leaf)) {
                Copy-Item -LiteralPath $record.Backup -Destination $record.Destination -Force -ErrorAction SilentlyContinue
            } elseif (-not $record.Existed -and (Test-Path -LiteralPath $record.Destination -PathType Leaf)) {
                Remove-Item -LiteralPath $record.Destination -Force -ErrorAction SilentlyContinue
            }
        }
        throw "SysIn installation failed and rollback was attempted: $($installError.Exception.Message)"
    }

    if (-not $NoPathChange) { Add-SysInUserPathEntry -PathToAdd $InstallRoot }

    Write-Output "SysIn installed to: $InstallRoot"
    if (-not $NoPathChange) { Write-Output 'The current-user PATH includes the SysIn install directory.' }
    Write-Output 'Run: sysin version'
} finally {
    if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
