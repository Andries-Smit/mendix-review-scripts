# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A set of PowerShell scripts that automate the Mendix visual code review process. Reviewers copy these scripts into a Mendix project folder and use them to create a review workspace where Studio Pro shows a git diff as local modifications.

## Scripts overview

| Script | Purpose | Run from |
|--------|---------|----------|
| `scripts/Setup.ps1` | One-time workspace initialisation | Inside the Mendix project folder (next to `.mpr`) |
| `scripts/Review.ps1` | Ongoing review management (main entry point) | Review root (`<project>-review/`) — copied to root by Setup |
| `scripts/StorePat.ps1` | PAT storage helper — dot-sourced by `Review.ps1` | Not run directly — copied to root by Setup |
| `scripts/SelectCommits.ps1` | Interactive TUI for selecting a commit range — dot-sourced by `Review.ps1` | Can run standalone — copied to root by Setup |

## How the diff trick works

`Setup.ps1` creates three copies of the Mendix project:
- `v1/` — checked out to CommitA (the "before" state)
- `v2/` — checked out to CommitB (the "after" state)
- `diff/` — contains v2's files but v1's `.git` folder

Because `diff/` holds v2 files with v1's git history, Studio Pro sees all changes between the two commits as uncommitted local modifications — enabling visual review with Studio Pro's built-in diff tools.

## Key design conventions

**Error messages** always follow the pattern established in `StorePat.ps1`:
```powershell
Write-Host "ERROR: <description>" -ForegroundColor Red
Write-Host ""
Write-Host "HOW TO FIX:" -ForegroundColor Yellow
Write-Host "  <remediation steps>" -ForegroundColor Yellow
exit 1
```

**Exit codes**: `exit 1` for errors, `exit 0` for clean exits.

**`$LASTEXITCODE` checks**: Always check after `git` and `robocopy` calls. For robocopy, exit codes 0–7 are non-error; 8+ indicate failure.

**robocopy over Copy-Item**: `Setup.ps1` uses `robocopy /E /XD deployment` instead of `Copy-Item` because Mendix projects contain deep `node_modules` trees that exceed the Windows MAX_PATH limit.

**PAT storage**: The credential name is `"MendixReview_PAT"` in Windows Credential Manager. `StorePat.ps1` exposes `Get-StoredPAT` — dot-source this file before calling it. PAT is embedded in the git remote URL as `https://pat:<PAT>@...` for `git fetch` calls.

**Studio Pro launch**: Opened via `Start-Process -FilePath <path-to-.mpr>` (Windows file association), not by looking up `studiopro.exe`. This automatically uses the correct installed version.

**SelectCommits.ps1 output**: Writes a dot-sourceable `commits.selected.ps1` file that sets `$CommitA` and `$CommitB`. `Review.ps1` dot-sources this file to read the selected commits.

## Testing

A test Mendix project is checked in for local testing without needing a real project:

| Path | Purpose |
|------|---------|
| `TestReviewApp-main/` | Source Mendix project (contains `TestReviewApp.mpr`) — run `scripts/Setup.ps1` from here |
| `TestReviewApp-main-review/` | Pre-created review workspace — run `Review.ps1` from here |

To test `Review.ps1` changes:
```powershell
cd C:\GitHub\mendix-review-scripts\TestReviewApp-main-review
.\Review.ps1
```

To test `Setup.ps1` changes, sync the source script into the test project first, then run it. Delete the existing review root first:
```powershell
Remove-Item -Recurse -Force C:\GitHub\mendix-review-scripts\TestReviewApp-main-review
Copy-Item C:\GitHub\mendix-review-scripts\scripts\Setup.ps1 C:\GitHub\mendix-review-scripts\TestReviewApp-main\scripts\Setup.ps1
& "C:\GitHub\mendix-review-scripts\TestReviewApp-main\scripts\Setup.ps1"
```

Note: `Setup.ps1` determines the project root from its own location (`$PSScriptRoot\..`), so it must be run from inside the Mendix project's `scripts\` folder — not from the repo root.

`TestReviewApp-main/` contains a live `.mpr.lock` file (Studio Pro may have it open). The `TestReviewApp-main-review/` workspace has `commits.selected.ps1` and `v1/`, `v2/`, `diff/` already populated.

`TestReviewApp-main-review/` is **not** a permanent fixture — it can be deleted when testing `Setup.ps1`. It is not in `.gitignore` so it may or may not be present. Always check before assuming the review workspace exists.

## Workflow sequence (Start Review)

1. Check for uncommitted changes in `diff/`
2. Verify PAT with `git ls-remote`
3. Run `SelectCommits.ps1` interactively (2-phase keyboard UI: pick start commit, then extend range)
4. `git fetch --depth 1 <authUrl> <CommitA>` + `git checkout FETCH_HEAD` in `v1/`
5. Same for CommitB in `v2/`
6. `robocopy v2/ diff/ /E /IS /IT /XD deployment .git`
7. Delete `diff/.git`, copy `v1/.git` → `diff/.git`
8. Open Studio Pro
