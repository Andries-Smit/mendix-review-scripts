BeforeAll {
    . "$PSScriptRoot\helpers\New-ReviewFixture.ps1"
    $script:fixture = New-ReviewFixture
    Set-Location $script:fixture
    . "$PSScriptRoot\..\scripts\Review.ps1"
    Mock Open-StudioPro { return $true }
}

AfterAll {
    Set-Location $PSScriptRoot
    Remove-Item -Recurse -Force $script:fixture -ErrorAction SilentlyContinue
}

Describe "Show-WorkspaceState with real git" {
    BeforeAll {
        # Ensure diff is at CommitA (REVIEWING state) before these tests
        Invoke-ContinueReview | Out-Null
    }

    It "reports REVIEWING when diff is at CommitA" {
        $output = Show-WorkspaceState 6>&1 | Out-String
        $output | Should -Match "REVIEWING"
    }
}

Describe "Invoke-FinishReview" {
    It "puts diff\.git at CommitB (v2 tip)" {
        Invoke-FinishReview
        $head = (git -C "$script:fixture\diff" rev-parse HEAD 2>&1).Trim()
        $CommitA = $null; $CommitB = $null
        . "$script:fixture\commits.selected.ps1"
        $head | Should -Be $CommitB
    }

    It "reports FINISH REVIEW after switching to CommitB" {
        $output = Show-WorkspaceState 6>&1 | Out-String
        $output | Should -Match "FINISH REVIEW"
    }
}

Describe "Invoke-ContinueReview" {
    It "puts diff\.git back at CommitA (v1 baseline)" {
        Invoke-ContinueReview
        $head = (git -C "$script:fixture\diff" rev-parse HEAD 2>&1).Trim()
        $CommitA = $null; $CommitB = $null
        . "$script:fixture\commits.selected.ps1"
        $head | Should -Be $CommitA
    }

    It "reports REVIEWING after restoring to CommitA" {
        $output = Show-WorkspaceState 6>&1 | Out-String
        $output | Should -Match "REVIEWING"
    }
}
