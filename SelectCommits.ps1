# ─────────────────────────────────────────────
# SelectCommits.ps1
# Interactively select a range of git commits
# Outputs CommitA (base) and CommitB (tip) for use with MendixDiff.ps1
# ─────────────────────────────────────────────

param(
    [string]$RepoPath   = "",
    [int]   $Count      = 30,
    [string]$OutputFile = ""   # Always pass this explicitly when calling from Diff.ps1
)

# ── Resolve output file path ────────────────────────────────────────────────
if (-not $OutputFile) {
    $OutputFile = Join-Path (Get-Location).Path "commits.selected.ps1"
    Write-Host "[WARN] -OutputFile not specified. Defaulting to: $OutputFile" -ForegroundColor Yellow
}

# ── Resolve repo path ───────────────────────────────────────────────────────
if (-not $RepoPath) {
    $userInput = Read-Host "[INPUT] Git repository path (leave blank for current directory)"
    $RepoPath = if ($userInput) { $userInput } else { (Get-Location).Path }
}

$RepoPath = [IO.Path]::GetFullPath($RepoPath)

if (-not (Test-Path $RepoPath)) {
    Write-Error "[ERROR] Path does not exist: $RepoPath"
    exit 1
}

# ── Verify git repository ───────────────────────────────────────────────────
Push-Location $RepoPath
$gitCheck = git rev-parse --is-inside-work-tree 2>&1
$gitCheckExit = $LASTEXITCODE
Pop-Location

if ($gitCheckExit -ne 0) {
    Write-Error "[ERROR] Not a git repository: $RepoPath"
    exit 1
}

Write-Host "[OK] Repository: $RepoPath"

# ── Shallow clone warning ───────────────────────────────────────────────────
Push-Location $RepoPath
$isShallow = git rev-parse --is-shallow-repository 2>&1
Pop-Location

if ($isShallow -eq "true") {
    Write-Host "[WARN] This is a shallow clone. Only limited commits may be visible."
    Write-Host "       For full history, point to a non-shallow clone of the repository."
}

# ── Fetch git log ───────────────────────────────────────────────────────────
Write-Host "[STEP] Fetching last $Count commits..."

Push-Location $RepoPath
$logLines = git log --pretty=format:"%H|%h|%ad|%an|%s" --date=short -n $Count 2>&1
$logExit = $LASTEXITCODE
Pop-Location

if ($logExit -ne 0) {
    Write-Error "[ERROR] git log failed"
    exit 1
}

if (-not $logLines) {
    Write-Error "[ERROR] No commits found in repository"
    exit 1
}

# ── Parse commits ───────────────────────────────────────────────────────────
$commits = @()
foreach ($line in $logLines) {
    $parts = $line -split '\|', 5
    if ($parts.Count -ge 5) {
        $commits += [PSCustomObject]@{
            FullHash  = $parts[0].Trim()
            ShortHash = $parts[1].Trim()
            Date      = $parts[2].Trim()
            Author    = $parts[3].Trim()
            Subject   = $parts[4].Trim()
        }
    }
}

if ($commits.Count -eq 0) {
    Write-Error "[ERROR] Could not parse any commits from git log output"
    exit 1
}

Write-Host "[OK] Loaded $($commits.Count) commits"
Write-Host ""

# ── Helper: truncate string ─────────────────────────────────────────────────
function Truncate([string]$s, [int]$len) {
    if ($s.Length -le $len) { return $s.PadRight($len) }
    return $s.Substring(0, $len - 3) + "..."
}

# ── Helper: draw the commit list ────────────────────────────────────────────
function Draw-CommitList {
    param(
        [int]   $CursorPos,
        [int]   $RangeStart,   # -1 = not set
        [int]   $RangeEnd,
        [int]   $Phase,        # 1 or 2
        [array] $Commits
    )

    $header  = "  #   Hash      Date        Author              Subject"
    $divider = "  --- --------  ----------  ------------------  " + ("-" * 38)

    Write-Host $header
    Write-Host $divider

    for ($i = 0; $i -lt $Commits.Count; $i++) {
        $c       = $Commits[$i]
        $num     = ($i + 1).ToString().PadLeft(3)
        $author  = Truncate $c.Author  18
        $subject = Truncate $c.Subject 38

        $inRange   = ($Phase -eq 2) -and ($i -ge $RangeStart) -and ($i -le $RangeEnd)
        $isStart   = ($Phase -eq 2) -and ($i -eq $RangeStart)
        $isCursor  = ($i -eq $CursorPos)
        $isEnd     = ($Phase -eq 2) -and ($i -eq $RangeEnd)

        # Build prefix (5 chars wide)
        if ($Phase -eq 1) {
            $prefix = if ($isCursor) { "> " } else { "  " }
        } else {
            if ($isStart -and $isEnd) {
                $prefix = if ($isCursor) { ">=" } else { "==" }
            } elseif ($isStart) {
                $prefix = "  "     # top of range
            } elseif ($inRange -and $isEnd) {
                $prefix = if ($isCursor) { "> " } else { "  " }
            } elseif ($inRange) {
                $prefix = "  "
            } else {
                $prefix = if ($isCursor) { "> " } else { "  " }
            }
        }

        # Build range bracket character
        if ($Phase -eq 2) {
            if ($isStart -and $isEnd) {
                $bracket = "[=]"
            } elseif ($isStart) {
                $bracket = "[+"
            } elseif ($inRange -and $isEnd) {
                $bracket = "+]"
            } elseif ($inRange) {
                $bracket = " | "
            } else {
                $bracket = "   "
            }
        } else {
            $bracket = "   "
        }

        $line = "$prefix $num $bracket $($c.ShortHash)  $($c.Date)  $author  $subject"

        if ($isCursor -and $Phase -eq 1) {
            Write-Host $line -ForegroundColor Cyan
        } elseif ($inRange) {
            Write-Host $line -ForegroundColor Yellow
        } elseif ($isCursor) {
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host $line
        }
    }

    Write-Host ""

    # Status line
    if ($Phase -eq 1) {
        Write-Host "  [Phase 1] Navigate with UP/DOWN. Press ENTER to set range start. Q/ESC to quit." -ForegroundColor DarkGray
        Write-Host "                                                                                    " # blank line to clear stale Phase 2 text
    } else {
        $startNum = $RangeStart + 1
        $endNum   = $RangeEnd   + 1

        # CommitB = newest selected (index RangeStart in 0-based = commits[RangeStart])
        # CommitA = parent of oldest selected (index RangeEnd+1 in 0-based = commits[RangeEnd+1])
        $shortB = $Commits[$RangeStart].ShortHash
        $shortA = if (($RangeEnd + 1) -lt $Commits.Count) { $Commits[$RangeEnd + 1].ShortHash } else { "??" }

        Write-Host "  [Phase 2] Navigate DOWN to extend range end. ENTER to confirm. ESC to reset.    " -ForegroundColor DarkGray
        Write-Host "  Range: $startNum-$endNum  |  CommitB (tip): $shortB  |  CommitA (base): $shortA  " -ForegroundColor Green
    }
}

# ── Interactive selection loop ──────────────────────────────────────────────
$cursorPos  = 0
$rangeStart = -1
$rangeEnd   = -1
$phase      = 1
$confirmed  = $false

[Console]::CursorVisible = $false

try {
    # Initial draw — save the top row
    $startRow = [Console]::CursorTop
    Draw-CommitList -CursorPos $cursorPos -RangeStart $rangeStart -RangeEnd $rangeEnd -Phase $phase -Commits $commits

    while ($true) {
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow" {
                if ($phase -eq 1) {
                    $cursorPos = [Math]::Max(0, $cursorPos - 1)
                } else {
                    if ($cursorPos -le $rangeStart) {
                        # Moving above range start — reset to Phase 1
                        $phase      = 1
                        $rangeStart = -1
                        $rangeEnd   = -1
                        $cursorPos  = [Math]::Max(0, $cursorPos - 1)
                    } else {
                        $cursorPos--
                        $rangeEnd = $cursorPos
                    }
                }
            }
            "DownArrow" {
                $cursorPos = [Math]::Min($commits.Count - 1, $cursorPos + 1)
                if ($phase -eq 2) {
                    $rangeEnd = $cursorPos
                }
            }
            "Enter" {
                if ($phase -eq 1) {
                    $rangeStart = $cursorPos
                    $rangeEnd   = $cursorPos
                    $phase      = 2
                } else {
                    # Confirm selection
                    $confirmed = $true
                    break
                }
            }
            { $_ -eq "Escape" -or ($key.KeyChar -eq 'q') -or ($key.KeyChar -eq 'Q') } {
                if ($phase -eq 2) {
                    # Reset to phase 1
                    $phase      = 1
                    $rangeStart = -1
                    $rangeEnd   = -1
                } else {
                    # Quit
                    [Console]::SetCursorPosition(0, $startRow)
                    Write-Host ""
                    Write-Host "[INFO] Cancelled. No output written." -ForegroundColor Yellow
                    [Console]::CursorVisible = $true
                    exit 0
                }
            }
        }

        if ($confirmed) { break }

        [Console]::SetCursorPosition(0, $startRow)
        Draw-CommitList -CursorPos $cursorPos -RangeStart $rangeStart -RangeEnd $rangeEnd -Phase $phase -Commits $commits
    }
}
finally {
    [Console]::CursorVisible = $true
}

Write-Host ""

# ── Validate selection ──────────────────────────────────────────────────────
# rangeStart and rangeEnd are 0-based
# CommitB = commits[rangeStart]  (newest selected)
# CommitA = commits[rangeEnd + 1] (parent of oldest selected)

if (($rangeEnd + 1) -ge $commits.Count) {
    Write-Error "[ERROR] The selected range extends to the oldest fetched commit."
    Write-Host "        Cannot determine CommitA (no parent visible)."
    Write-Host "        Re-run with a larger -Count value, e.g.: .\SelectCommits.ps1 -Count 50"
    exit 1
}

$firstIdx = $rangeStart + 1   # 1-based
$lastIdx  = $rangeEnd   + 1   # 1-based

$CommitB = $commits[$rangeStart].FullHash
$CommitA = $commits[$rangeEnd + 1].FullHash

# ── Display confirmation ────────────────────────────────────────────────────
Write-Host "[OK] Selection confirmed: index $firstIdx to $lastIdx"
Write-Host ""
Write-Host "  Commits in range:"
for ($i = $rangeStart; $i -le $rangeEnd; $i++) {
    $c = $commits[$i]
    Write-Host ("    [{0}] {1}  {2}  {3}" -f ($i + 1), $c.ShortHash, $c.Date, (Truncate $c.Subject 50))
}
Write-Host ""
Write-Host ("  CommitB (tip, newest selected):    {0}" -f $CommitB)
Write-Host ("    {0}  {1}" -f $commits[$rangeStart].Date, $commits[$rangeStart].Subject)
Write-Host ""
Write-Host ("  CommitA (base, before range):      {0}" -f $CommitA)
Write-Host ("    {0}  {1}" -f $commits[$rangeEnd + 1].Date, $commits[$rangeEnd + 1].Subject)
Write-Host ""
Write-Host "  MendixDiff will show all changes introduced by commit(s) $firstIdx through $lastIdx"

# ── Write output file ───────────────────────────────────────────────────────
$outputPath = [IO.Path]::GetFullPath($OutputFile)

$content = @"
# ── Auto-generated by SelectCommits.ps1 ──────────────────────────────────
# Repository : $RepoPath
# Selected   : index $firstIdx to $lastIdx ($($rangeEnd - $rangeStart + 1) commit(s))
# CommitB    : tip — newest selected commit (new state for MendixDiff)
# CommitA    : base — parent of oldest selected commit (old state for MendixDiff)
# Generated  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ─────────────────────────────────────────────────────────────────────────

`$CommitA = "$CommitA"
`$CommitB = "$CommitB"
"@

Set-Content -Path $outputPath -Value $content -Encoding UTF8

Write-Host ""
Write-Host "[OUT] Written to: $outputPath"
Write-Host ""
