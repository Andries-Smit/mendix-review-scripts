BeforeAll {
    Set-Location "C:\GitHub\mendix-review-scripts\TestReviewApp-main-review"
    . "$PSScriptRoot\..\Diff.ps1"
}

Describe "Show-WorkspaceState filesystem checks" {
    It "reports UNKNOWN when diff\.git is missing" {
        Mock Test-Path { $false } -ParameterFilter { $Path -like "*diff\.git*" }
        Mock Get-ChildItem { @() } -ParameterFilter { $Path -like "*diff*" }
        $output = Show-WorkspaceState 6>&1 | Out-String
        $output | Should -Match "UNKNOWN"
    }

    It "reports Ready when commits.selected.ps1 is absent" {
        Mock Test-Path { $true }  -ParameterFilter { $Path -like "*diff\.git*" }
        Mock Test-Path { $false } -ParameterFilter { $Path -like "*commits.selected.ps1*" }
        Mock Get-ChildItem { @() } -ParameterFilter { $Path -like "*diff*" }
        $output = Show-WorkspaceState 6>&1 | Out-String
        $output | Should -Match "Ready"
    }
}

Describe "Copy-GitInto" {
    It "returns false without calling robocopy when DestGit already exists" {
        Mock Test-Path { $true }
        Mock robocopy {}
        Mock Write-Host {}
        Mock Write-Log {}
        $result = Copy-GitInto -SourceGit "fake\src\.git" -DestGit "fake\dest\.git"
        $result | Should -Be $false
        Should -Invoke robocopy -Times 0
    }
}
