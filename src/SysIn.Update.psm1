Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:DefaultManifestUri = 'https://raw.githubusercontent.com/doonchy16-cloud/SysIn/main/release/manifest.json'

function ConvertTo-SysInVersion {
    param([Parameter(Mandatory=$true)][string]$Value)
    try { return [version]$Value }
    catch { throw "Invalid SysIn version '$Value'. Expected a numeric semantic version such as 1.1.0." }
}

function Compare-SysInVersion {
    param(
        [Parameter(Mandatory=$true)][string]$Local,
        [Parameter(Mandatory=$true)][string]$Remote
    )
    $a = ConvertTo-SysInVersion $Local
    $b = ConvertTo-SysInVersion $Remote
    return [math]::Sign($a.CompareTo($b))
}

function Test-SysInTargetPath {
    param([Parameter(Mandatory=$true)][string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { throw 'Manifest file target cannot be empty.' }
    $normalized = $Target.Replace('\','/')
    if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:') { throw "Manifest target must be relative: '$Target'." }
    $segments = @($normalized -split '/')
    if ($segments.Count -eq 0 -or $segments -contains '..' -or $segments -contains '.' -or $segments -contains '') {
        throw "Manifest target contains an unsafe path segment: '$Target'."
    }
    return $true
}

function Test-SysInManifest {
    param([Parameter(Mandatory=$true)]$Manifest)

    foreach ($name in @('product','version','channel','minimumPowerShell','files')) {
        if ($null -eq $Manifest.PSObject.Properties[$name]) { throw "SysIn manifest is missing required field '$name'." }
    }
    if ([string]$Manifest.product -cne 'SysIn') { throw "Manifest product must be 'SysIn'." }
    if ([string]$Manifest.channel -cne 'stable') { throw "SysIn V1.1 supports only the stable update channel." }
    [void](ConvertTo-SysInVersion ([string]$Manifest.version))
    [void](ConvertTo-SysInVersion ([string]$Manifest.minimumPowerShell))

    $files = @($Manifest.files)
    if ($files.Count -eq 0) { throw 'SysIn manifest contains no runtime files.' }
    $targets = @{}
    foreach ($file in $files) {
        foreach ($field in @('target','url','sha256')) {
            if ($null -eq $file.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$file.$field)) {
                throw "SysIn manifest file entry is missing '$field'."
            }
        }
        $target = [string]$file.target
        [void](Test-SysInTargetPath $target)
        $key = $target.Replace('\','/').ToLowerInvariant()
        if ($targets.ContainsKey($key)) { throw "SysIn manifest contains duplicate target '$target'." }
        $targets[$key] = $true

        $uri = $null
        if (-not [uri]::TryCreate([string]$file.url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https') {
            throw "Manifest runtime URL must use HTTPS: '$($file.url)'."
        }
        if ([string]$file.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Manifest SHA-256 for '$target' is invalid."
        }
    }
    return $true
}

function Get-SysInRemoteManifest {
    param([string]$ManifestUri = $script:DefaultManifestUri)
    $uri = $null
    if (-not [uri]::TryCreate($ManifestUri,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https') {
        throw 'SysIn manifest URI must use HTTPS.'
    }
    try { $manifest = Invoke-RestMethod -Uri $uri.AbsoluteUri -Method Get -ErrorAction Stop }
    catch { throw "Unable to retrieve SysIn update manifest: $($_.Exception.Message)" }
    [void](Test-SysInManifest $manifest)
    return $manifest
}

function Invoke-SysInCheckUpdate {
    param(
        [string]$CurrentVersion = '1.1.0',
        [string]$ManifestUri = $script:DefaultManifestUri,
        $ManifestObject
    )
    $manifest = if ($null -ne $ManifestObject) { $ManifestObject } else { Get-SysInRemoteManifest -ManifestUri $ManifestUri }
    [void](Test-SysInManifest $manifest)
    $comparison = Compare-SysInVersion $CurrentVersion ([string]$manifest.version)
    $status = if ($comparison -lt 0) { 'UpdateAvailable' } elseif ($comparison -eq 0) { 'UpToDate' } else { 'LocalNewer' }
    [pscustomobject]@{
        Status = $status
        CurrentVersion = $CurrentVersion
        LatestVersion = [string]$manifest.version
        Channel = [string]$manifest.channel
        Manifest = $manifest
    }
}

function Invoke-DefaultSysInDownload {
    param([string]$Url,[string]$Destination)
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
}

function Invoke-DefaultSysInReplace {
    param([string]$Source,[string]$Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
}

function Invoke-SysInUpdate {
    [CmdletBinding()]
    param(
        [string]$CurrentVersion = '1.1.0',
        [string]$InstallRoot = (Split-Path -Parent $PSScriptRoot),
        [string]$ManifestUri = $script:DefaultManifestUri,
        $ManifestObject,
        [scriptblock]$Downloader,
        [scriptblock]$Replacer
    )

    if ([string]::IsNullOrWhiteSpace($InstallRoot)) { throw 'SysIn install root cannot be empty.' }
    $manifest = if ($null -ne $ManifestObject) { $ManifestObject } else { Get-SysInRemoteManifest -ManifestUri $ManifestUri }
    [void](Test-SysInManifest $manifest)

    $comparison = Compare-SysInVersion $CurrentVersion ([string]$manifest.version)
    if ($comparison -eq 0) {
        return [pscustomobject]@{ Status='UpToDate'; PreviousVersion=$CurrentVersion; Version=$CurrentVersion }
    }
    if ($comparison -gt 0) {
        return [pscustomobject]@{ Status='LocalNewer'; PreviousVersion=$CurrentVersion; Version=$CurrentVersion }
    }

    $minimum = ConvertTo-SysInVersion ([string]$manifest.minimumPowerShell)
    if ($PSVersionTable.PSVersion -lt $minimum) {
        throw "SysIn $($manifest.version) requires PowerShell $minimum or newer."
    }

    if ($null -eq $Downloader) { $Downloader = ${function:Invoke-DefaultSysInDownload} }
    if ($null -eq $Replacer) { $Replacer = ${function:Invoke-DefaultSysInReplace} }

    $workRoot = Join-Path ([IO.Path]::GetTempPath()) ('SysIn-update-' + [guid]::NewGuid().ToString('N'))
    $stageRoot = Join-Path $workRoot 'stage'
    $backupRoot = Join-Path $workRoot 'backup'
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $records = New-Object System.Collections.Generic.List[object]
    try {
        # Phase 1: download and verify every file before the installed copy is touched.
        foreach ($file in @($manifest.files)) {
            $relative = ([string]$file.target).Replace('/',[IO.Path]::DirectorySeparatorChar)
            $stage = Join-Path $stageRoot $relative
            $stageParent = Split-Path -Parent $stage
            if (-not (Test-Path -LiteralPath $stageParent)) { New-Item -ItemType Directory -Path $stageParent -Force | Out-Null }
            & $Downloader ([string]$file.url) $stage
            if (-not (Test-Path -LiteralPath $stage -PathType Leaf)) { throw "Updater did not receive '$relative'." }
            $actual = (Get-FileHash -LiteralPath $stage -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            $expected = ([string]$file.sha256).ToLowerInvariant()
            if ($actual -ne $expected) { throw "SHA-256 verification failed for '$relative'. Expected $expected, received $actual." }

            $destination = Join-Path $InstallRoot $relative
            $backup = Join-Path $backupRoot $relative
            $records.Add([pscustomobject]@{ Relative=$relative; Stage=$stage; Destination=$destination; Backup=$backup; Existed=(Test-Path -LiteralPath $destination -PathType Leaf); Replaced=$false })
        }

        # Phase 2: back up the exact known targets.
        foreach ($record in $records) {
            if ($record.Existed) {
                $parent = Split-Path -Parent $record.Backup
                if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $record.Destination -Destination $record.Backup -Force -ErrorAction Stop
            }
        }

        # Phase 3: replace only manifest-declared files.
        try {
            foreach ($record in $records) {
                $parent = Split-Path -Parent $record.Destination
                if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                & $Replacer $record.Stage $record.Destination
                $record.Replaced = $true
            }
        } catch {
            $replaceError = $_
            foreach ($record in $records) {
                if ($record.Existed -and (Test-Path -LiteralPath $record.Backup -PathType Leaf)) {
                    Copy-Item -LiteralPath $record.Backup -Destination $record.Destination -Force -ErrorAction SilentlyContinue
                } elseif (-not $record.Existed -and (Test-Path -LiteralPath $record.Destination)) {
                    Remove-Item -LiteralPath $record.Destination -Force -ErrorAction SilentlyContinue
                }
            }
            throw "SysIn update replacement failed and rollback was attempted: $($replaceError.Exception.Message)"
        }

        return [pscustomobject]@{ Status='Updated'; PreviousVersion=$CurrentVersion; Version=[string]$manifest.version }
    } finally {
        if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Export-ModuleMember -Function Compare-SysInVersion, Test-SysInManifest, Get-SysInRemoteManifest, Invoke-SysInCheckUpdate, Invoke-SysInUpdate
