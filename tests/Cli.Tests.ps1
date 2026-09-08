BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Cli = Join-Path $script:RepoRoot 'src\SysIn.ps1'

    function Invoke-SysInCliTest {
        param([string[]]$Arguments)
        $output = & pwsh -NoLogo -NoProfile -File $script:Cli @Arguments 2>&1 | Out-String
        [pscustomobject]@{
            Output = $output.Trim()
            ExitCode = $LASTEXITCODE
        }
    }
}

Describe 'SysIn V1.1 CLI metadata' {
    It 'reports 1.1.0 for canonical version command' {
        $result = Invoke-SysInCliTest @('version')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'SysIn 1\.1\.0'
        $result.Output | Should -Match 'stable'
    }

    It 'supports --version' {
        $result = Invoke-SysInCliTest @('--version')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'SysIn 1\.1\.0'
    }

    It 'supports -v' {
        $result = Invoke-SysInCliTest @('-v')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'SysIn 1\.1\.0'
    }

    It 'supports legacy -Version' {
        $result = Invoke-SysInCliTest @('-Version')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'SysIn 1\.1\.0'
    }

    It 'lists the complete V1.1 command surface in help' {
        $result = Invoke-SysInCliTest @('help')
        $result.ExitCode | Should -Be 0
        foreach ($command in @(
            'overview','cpu','gpu','memory','storage','network','processes','sensors',
            'system','snapshot','doctor','capabilities','version','check-update','update',
            'config','help','about'
        )) {
            $result.Output | Should -Match ([regex]::Escape($command))
        }
    }

    It 'shows the public repository in about' {
        $result = Invoke-SysInCliTest @('about')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'doonchy16-cloud/SysIn'
        $result.Output | Should -Match 'Windows System Intelligence'
    }
}
