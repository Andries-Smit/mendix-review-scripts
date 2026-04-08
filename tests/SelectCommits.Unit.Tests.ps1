BeforeAll {
    . "$PSScriptRoot\..\SelectCommits.ps1"
}

Describe "Truncate" {
    It "pads short strings to len" {
        Truncate "hi" 5 | Should -Be "hi   "
    }
    It "returns exact-length string unchanged (padded)" {
        Truncate "hello" 5 | Should -Be "hello"
    }
    It "truncates long strings and appends '...'" {
        Truncate "hello world" 8 | Should -Be "hello..."
    }
    It "handles empty string" {
        Truncate "" 4 | Should -Be "    "
    }
}

Describe "ConvertFrom-GitLogLine" {
    It "parses a valid 5-part pipe-delimited line" {
        $result = ConvertFrom-GitLogLine @("abc123def456|abc123|2024-01-15|Alice Smith|Fix login bug")
        $result.Count | Should -Be 1
        $result[0].FullHash  | Should -Be "abc123def456"
        $result[0].ShortHash | Should -Be "abc123"
        $result[0].Date      | Should -Be "2024-01-15"
        $result[0].Author    | Should -Be "Alice Smith"
        $result[0].Subject   | Should -Be "Fix login bug"
    }
    It "skips lines with fewer than 5 parts" {
        $result = ConvertFrom-GitLogLine @("bad|line|only|three")
        $result.Count | Should -Be 0
    }
    It "handles subject containing pipes (splits on first 5 fields only)" {
        $result = ConvertFrom-GitLogLine @("hash|short|date|author|subject|with|extra|pipes")
        $result[0].Subject | Should -Be "subject|with|extra|pipes"
    }
    It "handles empty input" {
        $result = ConvertFrom-GitLogLine @()
        $result.Count | Should -Be 0
    }
    It "parses multiple valid lines" {
        $lines = @(
            "aaa|a1|2024-01-01|Alice|Commit one",
            "bbb|b2|2024-01-02|Bob|Commit two"
        )
        $result = ConvertFrom-GitLogLine $lines
        $result.Count | Should -Be 2
        $result[0].Subject | Should -Be "Commit one"
        $result[1].Subject | Should -Be "Commit two"
    }
    It "skips invalid lines but parses valid ones in mixed input" {
        $lines = @(
            "aaa|a1|2024-01-01|Alice|Good commit",
            "bad|line",
            "bbb|b2|2024-01-02|Bob|Another good one"
        )
        $result = ConvertFrom-GitLogLine $lines
        $result.Count | Should -Be 2
    }
}

Describe "Test-CommitRangeValid" {
    It "returns true when a parent commit exists after the range" {
        Test-CommitRangeValid -RangeEnd 3 -CommitCount 5 | Should -Be $true
    }
    It "returns false when rangeEnd+1 equals CommitCount (no parent visible)" {
        Test-CommitRangeValid -RangeEnd 4 -CommitCount 5 | Should -Be $false
    }
    It "returns false when rangeEnd is the last index" {
        Test-CommitRangeValid -RangeEnd 9 -CommitCount 10 | Should -Be $false
    }
    It "returns true for single commit range with parent" {
        Test-CommitRangeValid -RangeEnd 0 -CommitCount 2 | Should -Be $true
    }
    It "returns false for single commit range with no parent" {
        Test-CommitRangeValid -RangeEnd 0 -CommitCount 1 | Should -Be $false
    }
}
