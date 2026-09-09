$repoRoot = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $repoRoot 'SysIn.cmd'
$cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'

Assert-SysInTrue (Test-Path -LiteralPath $launcher -PathType Leaf) 'SysIn.cmd exists'
Assert-SysInTrue (Test-Path -LiteralPath $cmd -PathType Leaf) 'cmd.exe exists at the canonical Windows path'

$originalPath = $env:Path
try {
    $env:Path = 'C:\SysIn-Path-Intentionally-Missing-System-Tools'
    $output = & $cmd /d /c ('"' + $launcher + '" version') 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
} finally {
    $env:Path = $originalPath
}

Assert-SysInEqual $exitCode 0 "launcher works when PATH omits PowerShell and system tool directories`nCaptured output:`n$output"
Assert-SysInMatch $output 'SysIn 1\.1\.0' 'launcher reports SysIn version when PATH is degraded'
