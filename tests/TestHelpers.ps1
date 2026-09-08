$script:SysInAssertions = 0

function Assert-SysInTrue {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $script:SysInAssertions++
    if (-not $Condition) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-SysInEqual {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $script:SysInAssertions++
    if ($Actual -ne $Expected) {
        throw "ASSERT EQUAL FAILED: $Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Assert-SysInMatch {
    param(
        [AllowNull()][string]$Actual,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $script:SysInAssertions++
    if ($null -eq $Actual -or $Actual -notmatch $Pattern) {
        throw "ASSERT MATCH FAILED: $Message`nPattern: $Pattern`nActual:  $Actual"
    }
}

function Assert-SysInThrows {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $script:SysInAssertions++
    $threw = $false
    try { & $ScriptBlock } catch { $threw = $true }
    if (-not $threw) { throw "ASSERT THROWS FAILED: $Message" }
}
