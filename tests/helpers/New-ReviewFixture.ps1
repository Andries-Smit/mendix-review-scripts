function New-ReviewFixture {
    param([string]$BasePath = $env:TEMP)
    $dest = Join-Path $BasePath "MendixReviewTest_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    robocopy "C:\GitHub\mendix-review-scripts\TestReviewApp-main-review" $dest /E /NP /NFL /NDL | Out-Null
    return $dest
}
