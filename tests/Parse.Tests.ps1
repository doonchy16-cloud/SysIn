$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object {
        $_.Extension -in @('.ps1', '.psm1') -and
        $_.FullName -notmatch '[\\/]\.git[\\/]'
    }

$allErrors = @()
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )

    foreach ($error in @($errors)) {
        $allErrors += [pscustomobject]@{
            File = $file.FullName
            Message = $error.Message
            StartLine = $error.Extent.StartLineNumber
            StartColumn = $error.Extent.StartColumnNumber
        }
    }
}

if ($allErrors.Count -gt 0) {
    $allErrors | Format-Table -AutoSize | Out-String | Write-Host
    throw "PowerShell parser found $($allErrors.Count) error(s)."
}

Write-Host "Parsed $($files.Count) PowerShell file(s) with 0 syntax errors."
