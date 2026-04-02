# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A set of PowerShell scripts that automate the Mendix visual code review process. Reviewers copy these scripts into a Mendix project folder and use them to create a review workspace where Studio Pro shows a git diff as local modifications.

## Scripts overview

| Script | Purpose | Run from |
|--------|---------|----------|
| `Setup.ps1` | One-time workspace initialisation | Inside the Mendix project folder (next to `.mpr`) |
| `Diff.ps1` | Ongoing review management (main entry point) | Review root (`<project>-review/`) |
| `StorePat.ps1` | PAT storage helper — dot-sourced by `Diff.ps1` | Not run directly |
| `SelectCommits.ps1` | Interactive TUI for selecting a commit range — dot-sourced by `Diff.ps1` | Can run standalone |

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

**SelectCommits.ps1 output**: Writes a dot-sourceable `commits.selected.ps1` file that sets `$CommitA` and `$CommitB`. `Diff.ps1` dot-sources this file to read the selected commits.

## Workflow sequence (Start Review)

1. Check for uncommitted changes in `diff/`
2. Verify PAT with `git ls-remote`
3. Run `SelectCommits.ps1` interactively (2-phase keyboard UI: pick start commit, then extend range)
4. `git fetch --depth 1 <authUrl> <CommitA>` + `git checkout FETCH_HEAD` in `v1/`
5. Same for CommitB in `v2/`
6. `robocopy v2/ diff/ /E /IS /IT /XD deployment .git`
7. Delete `diff/.git`, copy `v1/.git` → `diff/.git`
8. Open Studio Pro
