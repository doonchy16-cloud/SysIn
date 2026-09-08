$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

$testFiles = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File |
    Where-Object { $_.Name -notin @('Parse.Tests.ps1','Run.Tests.ps1') } |
    Sort-Object Name

if ($testFiles.Count -eq 0) { throw 'No behavior tests were found.' }

foreach ($file in $testFiles) {
    Write-Host "=== $($file.Name) ==="
    . $file.FullName
}

Write-Host "Behavior tests complete. Assertions: $script:SysInAssertions"
