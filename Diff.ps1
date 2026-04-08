# ==============================================================================
# Diff.ps1 -- Mendix Code Review Tool -- Review management
# Run this script from the review root (the folder containing v1, v2, diff).
# ==============================================================================

$ReviewRoot = (Get-Location).Path
$script:CredentialName = "MendixReview_PAT"
$script:ScriptVersion  = "1.1"

# -- Dot-source StorePat.ps1 ---------------------------------------------------
$storePatScript = Join-Path $PSScriptRoot "StorePat.ps1"
if (-not (Test-Path $storePatScript)) {
    Write-Host ""
    Write-Host "ERROR: StorePat.ps1 was not found next to Diff.ps1." -ForegroundColor Red
    Write-Host "       Expected at: $storePatScript" -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Copy StorePat.ps1 from the MendixDiff tool folder to:" -ForegroundColor Yellow
    Write-Host "    $PSScriptRoot" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
. $storePatScript


# ==============================================================================
# Helper functions
# ==============================================================================

function Invoke-GitWithPAT {
    <#
    .SYNOPSIS
        Run a git command with PAT credentials injected via GIT_ASKPASS,
        keeping the token out of the process command line.
    .PARAMETER GitArgs
        All arguments to pass to git (as an array).
    .PARAMETER PAT
        The Personal Access Token as a plain string (in memory only).
    #>
    param(
        [string[]]$GitArgs,
        [string]$PAT
    )
    # Write a minimal ASKPASS helper to a temp .cmd file.
    # The PAT is passed via an environment variable — not embedded in the file —
    # so that CMD special characters in the token do not corrupt the echo output.
    # git calls this script when it needs a password; powershell reads the env var and outputs it.
    # The file and the env var are removed immediately after the git call completes.
    $cmdPath = Join-Path $env:TEMP "mendix_askpass_$PID.cmd"
    $cmdContent = '@echo off' + "`r`n" + 'powershell.exe -NoProfile -NonInteractive -Command "Write-Host $env:MENDIX_REVIEW_PAT"'
    Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII
    $env:MENDIX_REVIEW_PAT = $PAT
    $prev = $env:GIT_ASKPASS
    $env:GIT_ASKPASS = $cmdPath
    try {
        git -c credential.username=pat @GitArgs
        return $LASTEXITCODE
    } finally {
        $env:GIT_ASKPASS = $prev
        $env:MENDIX_REVIEW_PAT = $null
        Remove-Item -Path $cmdPath -ErrorAction SilentlyContinue
    }
}

function Exit-Script {
    param([int]$Code = 0)
    try { Stop-Transcript | Out-Null } catch { }
    exit $Code
}

function Open-StudioPro {
    $mprFile = @(Get-ChildItem -Path "$ReviewRoot\diff" -Filter "*.mpr" -File)
    if ($mprFile.Count -ne 1) {
        Write-Host ""
        Write-Host "ERROR: Could not find a .mpr file in the diff\ folder." -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  The diff\ folder must contain exactly one .mpr file." -ForegroundColor Yellow
        Write-Host "  Re-run Setup.ps1 to recreate the review workspace." -ForegroundColor Yellow
        Write-Host ""
        return $false
    }

    $mprPath = $mprFile[0].FullName
    Write-Host "[OPEN] Opening: $mprPath"
    # Open via file association — Windows selects the correct Studio Pro version automatically.
    Start-Process -FilePath $mprPath
    Write-Host "[OK]   Studio Pro is starting."
    return $true
}

function Test-DiffProjectOpen {
    # Returns $true (and warns) if Studio Pro has the diff project open.
    # Mirrors the lock-file check in Setup.ps1 Step 2b: find the .mpr, then
    # check for the exact <name>.mpr.lock path rather than using a wildcard.
    $mpr = Get-ChildItem -Path "$ReviewRoot\diff" -Filter "*.mpr" -File -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($mpr -and (Test-Path ($mpr.FullName + ".lock"))) {
        Write-Host ""
        Write-Host "ERROR: Studio Pro still has the diff project open." -ForegroundColor Red
        Write-Host "         Close Studio Pro, then re-run this option." -ForegroundColor Red
        Write-Host ""
        return $true
    }
    return $false
}

function Remove-DiffGit {
    $gitPath = "$ReviewRoot\diff\.git"
    if (Test-Path $gitPath) {
        try {
            Remove-Item -Recurse -Force $gitPath -ErrorAction Stop
        } catch {
            Write-Host ""
            Write-Host "ERROR: Could not remove diff\.git" -ForegroundColor Red
            Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "HOW TO FIX:" -ForegroundColor Yellow
            Write-Host "  Make sure no processes have files open inside diff\.git." -ForegroundColor Yellow
            Write-Host "  Close Studio Pro or any git tools, then try again." -ForegroundColor Yellow
            Write-Host ""
            return $false
        }
    }
    return $true
}

function Copy-GitInto {
    param([string]$SourceGit, [string]$DestGit)

    # Guard: if DestGit already exists, Copy-Item would create a double-nested .git\.git.
    # Remove-DiffGit must always be called before this function.
    if (Test-Path $DestGit) {
        Write-Host ""
        Write-Host "ERROR: Destination .git already exists and was not removed before Copy-GitInto." -ForegroundColor Red
        Write-Host "       Destination: $DestGit" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Close Studio Pro and any git tools that may have open handles in diff\.git," -ForegroundColor Yellow
        Write-Host "  then try again." -ForegroundColor Yellow
        Write-Host ""
        return $false
    }

    robocopy $SourceGit $DestGit /E /NP /NDL /NFL | Out-Null
    if ($LASTEXITCODE -ge 8) {
        Write-Host ""
        Write-Host "ERROR: Could not copy .git folder." -ForegroundColor Red
        Write-Host "       From: $SourceGit" -ForegroundColor Red
        Write-Host "       To:   $DestGit" -ForegroundColor Red
        Write-Host "       robocopy exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Check available disk space and permissions on:" -ForegroundColor Yellow
        Write-Host "    $(Split-Path $DestGit -Parent)" -ForegroundColor Yellow
        Write-Host ""
        return $false
    }
    return $true
}


# ==============================================================================
# Startup validation
# ==============================================================================

# Must NOT be run from a project folder (no .mpr in current dir)
$rootMpr = @(Get-ChildItem -Path . -Filter "*.mpr" -File)
if ($rootMpr.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: Diff.ps1 must be run from the review root, not a Mendix project folder." -ForegroundColor Red
    Write-Host "       Found .mpr file(s) in the current directory." -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Navigate to your review root folder and run Diff.ps1 from there." -ForegroundColor Yellow
    Write-Host "  The review root is the folder that contains v1\, v2\, and diff\ subfolders." -ForegroundColor Yellow
    Write-Host "  Example:" -ForegroundColor Yellow
    Write-Host "    cd `"C:\Projects\MyApp-review`"" -ForegroundColor Yellow
    Write-Host "    .\Diff.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# v1, v2, diff must exist and each contain exactly one .mpr
foreach ($sub in @("v1", "v2", "diff")) {
    if (-not (Test-Path $sub)) {
        Write-Host ""
        Write-Host "ERROR: Required subfolder '$sub\' not found in current directory." -ForegroundColor Red
        Write-Host "       Current directory: $ReviewRoot" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  This script must be run from a review root created by Setup.ps1." -ForegroundColor Yellow
        Write-Host "  The review root must contain three subfolders: v1\, v2\, diff\" -ForegroundColor Yellow
        Write-Host "  If you have not run Setup.ps1 yet, navigate to your Mendix project folder and run it:" -ForegroundColor Yellow
        Write-Host "    cd `"C:\Projects\MyApp`"" -ForegroundColor Yellow
        Write-Host "    .\Setup.ps1" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
    $subMpr = @(Get-ChildItem -Path $sub -Filter "*.mpr" -File)
    if ($subMpr.Count -ne 1) {
        Write-Host ""
        Write-Host "ERROR: Subfolder '$sub\' must contain exactly one .mpr file." -ForegroundColor Red
        Write-Host "       Found: $($subMpr.Count)" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  The '$sub\' folder may be corrupted or incomplete." -ForegroundColor Yellow
        Write-Host "  Delete the review root and re-run Setup.ps1 to recreate it:" -ForegroundColor Yellow
        Write-Host "    Remove-Item -Recurse -Force `"$ReviewRoot`"" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    Mendix Code Review Tool  (v$($script:ScriptVersion))" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    Review root: $ReviewRoot"
Write-Host ""

# -- Verify git is available ---------------------------------------------------
$gitVersion = git --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: git was not found on your PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Install Git for Windows from https://git-scm.com/download/win" -ForegroundColor Yellow
    Write-Host "  After installation, close and reopen this PowerShell window, then re-run Diff.ps1." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# -- Start transcript logging --------------------------------------------------
$transcriptPath = Join-Path $ReviewRoot "review.log"
try {
    Start-Transcript -Path $transcriptPath -Append | Out-Null
    Write-Host "[LOG]  Session transcript: $transcriptPath"
    Write-Host ""
} catch {
    Write-Host "[WARN] Could not start transcript: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
}


function Show-WorkspaceState {
    Write-Host "----------------------------------------------------------------"

    # Check if Studio Pro still has the diff project open
    $diffLock = @(Get-ChildItem -Path "$ReviewRoot\diff" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*.mpr.lock" })
    if ($diffLock.Count -gt 0) {
        Write-Host "  ERROR: Studio Pro still has the diff project open." -ForegroundColor Red
        Write-Host "         Close Studio Pro before using any menu option." -ForegroundColor Red
        Write-Host "----------------------------------------------------------------"
        Write-Host ""
        return
    }

    $commitsFile = Join-Path $ReviewRoot "commits.selected.ps1"

    if (-not (Test-Path "$ReviewRoot\diff\.git")) {
        Write-Host "  Workspace:  UNKNOWN - diff\.git is missing" -ForegroundColor Yellow
        Write-Host "              Re-run Setup.ps1 or use option 1 to start a review."
        Write-Host ""
        return
    }

    if (-not (Test-Path $commitsFile)) {
        Write-Host "  Workspace:  Ready - no review started yet" -ForegroundColor Gray
        Write-Host "              Use option 1 to begin a review."
        Write-Host ""
        return
    }

    $CommitA = $null; $CommitB = $null
    . $commitsFile

    if (-not $CommitA -or -not $CommitB) {
        Write-Host "  Workspace:  UNKNOWN - could not read commit range" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $diffHead    = (git -C "$ReviewRoot\diff" rev-parse HEAD 2>&1).Trim()
    $diffChanges = @(git -C "$ReviewRoot\diff" status --porcelain 2>&1 | Where-Object { $_ }).Count

    if ($diffHead -eq $CommitA) {
        $v1Info = (git -C "$ReviewRoot\v1" log -1 --pretty=format:"%h  %ad  %s" --date=short HEAD 2>&1).Trim()
        $v2Info = (git -C "$ReviewRoot\v2" log -1 --pretty=format:"%h  %ad  %s" --date=short HEAD 2>&1).Trim()
        Write-Host "  Workspace:  REVIEWING" -ForegroundColor Cyan
        Write-Host "  Base (A):   $v1Info"
        Write-Host "  Tip  (B):   $v2Info"
        if ($diffChanges -gt 0) {
            Write-Host "  Changes:    $diffChanges file(s) modified in diff\" -ForegroundColor Yellow
        } else {
            Write-Host "  Changes:    none yet"
        }
    } elseif ($diffHead -eq $CommitB) {
        $v2Info = (git -C "$ReviewRoot\v2" log -1 --pretty=format:"%h  %ad  %s" --date=short HEAD 2>&1).Trim()
        Write-Host "  Workspace:  FINISH REVIEW - commit your fixes in Studio Pro" -ForegroundColor Yellow
        Write-Host "  On commit:  $v2Info"
        if ($diffChanges -gt 0) {
            Write-Host "  Fixes:      $diffChanges file(s) uncommitted in diff\" -ForegroundColor Green
        } else {
            Write-Host "  Fixes:      none yet - make changes in Studio Pro first"
        }
    } else {
        Write-Host "  Workspace:  UNKNOWN - diff\ is not at CommitA or CommitB" -ForegroundColor Yellow
        Write-Host "              Use option 1 (Start review) to reset the workspace."
    }

    Write-Host "----------------------------------------------------------------"
    Write-Host ""
}


# ==============================================================================
# Action functions
# ==============================================================================

function Invoke-StartReview {

    if (Test-DiffProjectOpen) { return }

    # Step 1: Check for uncommitted changes in diff\
    if (Test-Path "$ReviewRoot\diff\.git") {
        $gitStatus = git -C "$ReviewRoot\diff" status --porcelain 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARN] Could not check git status in diff\ (exit code $LASTEXITCODE). Proceeding anyway." -ForegroundColor Yellow
        } elseif ($gitStatus) {
            Write-Host ""
            Write-Host "WARNING: There are uncommitted changes in the diff\ folder." -ForegroundColor Yellow
            Write-Host "         Starting a new review will overwrite them permanently." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  To preserve them: use option 3 (Finish Review) first." -ForegroundColor Yellow
            Write-Host ""
            $confirm = (Read-Host "Proceed and discard uncommitted changes? [y/N]").Trim()
            if ($confirm -ne "y" -and $confirm -ne "Y") {
                Write-Host "[INFO] Cancelled. Returning to menu." -ForegroundColor Yellow
                return
            }
            Write-Host "[INFO] Proceeding. Uncommitted changes in diff\ will be overwritten."
            Write-Host ""
        }
    }

    # Step 2: PAT authentication and verification
    $PAT = Get-StoredPAT -CredentialName $script:CredentialName

    $originUrl = (git -C "$ReviewRoot\v1" remote get-url origin 2>&1).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $originUrl) {
        Write-Host ""
        Write-Host "ERROR: Could not read the git remote origin URL from v1\." -ForegroundColor Red
        Write-Host "       v1\ must be a git repository with a remote named 'origin'." -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Delete the review root and re-run Setup.ps1 from your Mendix project folder." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Resolve the remote default branch so v2 can be re-attached to a named branch
    # after checkout FETCH_HEAD (required for Studio Pro to allow commits after Finish Review).
    $defaultBranch = "main"   # fallback
    $symrefOutput = Invoke-GitWithPAT -GitArgs @("ls-remote", "--symref", $originUrl, "HEAD") -PAT $PAT 2>&1
    if ($LASTEXITCODE -eq 0 -and $symrefOutput) {
        $symrefLine = ($symrefOutput -split "`n" | Where-Object { $_ -match "^ref: refs/heads/" } | Select-Object -First 1)
        if ($symrefLine -match "^ref: refs/heads/([^\t]+)") {
            $defaultBranch = $Matches[1].Trim()
            Write-Host "[INFO] Default branch resolved: $defaultBranch"
        } else {
            Write-Host "[WARN] Could not parse branch from ls-remote output. Falling back to 'main'." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARN] ls-remote --symref failed. Falling back to default branch 'main'." -ForegroundColor Yellow
    }
    Write-Host ""

    # Step 3: Refresh recent history in v1\ so SelectCommits can show up-to-date commits.
    # After a previous review, v1\ is a shallow clone at a single commit. Fetching here
    # gives git log enough history to populate the selector.
    Write-Host "[FETCH] Refreshing commit history in v1\ ..."
    Invoke-GitWithPAT -GitArgs @("-C", "$ReviewRoot\v1", "fetch", "--depth", "50", $originUrl) -PAT $PAT | Out-Null
    git -C "$ReviewRoot\v1" checkout FETCH_HEAD --quiet 2>$null
    Write-Host "[OK]   History refreshed."
    Write-Host ""

    # Step 3b: Select commit range
    $selectScript = Join-Path $PSScriptRoot "SelectCommits.ps1"
    if (-not (Test-Path $selectScript)) {
        Write-Host ""
        Write-Host "ERROR: SelectCommits.ps1 was not found next to Diff.ps1." -ForegroundColor Red
        Write-Host "       Expected at: $selectScript" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Copy SelectCommits.ps1 from the MendixDiff tool folder to:" -ForegroundColor Yellow
        Write-Host "    $PSScriptRoot" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $commitsFile = Join-Path $ReviewRoot "commits.selected.ps1"
    & $selectScript -RepoPath "$ReviewRoot\v1" -OutputFile $commitsFile -Count 50
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[INFO] Commit selection was cancelled. Returning to menu." -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path $commitsFile)) {
        Write-Host ""
        Write-Host "ERROR: SelectCommits.ps1 did not produce an output file." -ForegroundColor Red
        Write-Host "       Expected: $commitsFile" -ForegroundColor Red
        Write-Host ""
        return
    }

    $CommitA = $null
    $CommitB = $null
    . $commitsFile

    if (-not $CommitA -or -not $CommitB) {
        Write-Host ""
        Write-Host "ERROR: Could not read CommitA or CommitB from the selection output." -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "[INFO] CommitA (base):  $CommitA"
    Write-Host "[INFO] CommitB (tip):   $CommitB"
    Write-Host ""

    # Step 4: Update v1\ to CommitA
    Write-Host "[FETCH] Fetching CommitA into v1\ ..."
    Invoke-GitWithPAT -GitArgs @("-C", "$ReviewRoot\v1", "fetch", "--depth", "1", $originUrl, $CommitA) -PAT $PAT
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: git fetch failed for CommitA in v1\." -ForegroundColor Red
        Write-Host "       Commit: $CommitA" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Verify the commit hash is valid and accessible on the remote." -ForegroundColor Yellow
        Write-Host "  Check your network connection and PAT (use option 4 to update PAT)." -ForegroundColor Yellow
        Write-Host ""
        return
    }
    git -C "$ReviewRoot\v1" checkout FETCH_HEAD --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: git checkout FETCH_HEAD failed in v1\." -ForegroundColor Red
        Write-Host ""
        return
    }
    Write-Host "[OK]   v1\ is at CommitA."

    # Step 5: Update v2\ to CommitB
    Write-Host "[FETCH] Fetching CommitB into v2\ ..."
    Invoke-GitWithPAT -GitArgs @("-C", "$ReviewRoot\v2", "fetch", "--depth", "1", $originUrl, $CommitB) -PAT $PAT
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: git fetch failed for CommitB in v2\." -ForegroundColor Red
        Write-Host "       Commit: $CommitB" -ForegroundColor Red
        Write-Host "       Note: v1\ has already been updated to CommitA." -ForegroundColor Red
        Write-Host "       The workspace is in a partially updated state." -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Verify the commit hash is valid and accessible on the remote." -ForegroundColor Yellow
        Write-Host "  Check your network connection and PAT (use option 4 to update PAT)." -ForegroundColor Yellow
        Write-Host "  Then run option 1 (Start Review) again." -ForegroundColor Yellow
        Write-Host ""
        return
    }
    git -C "$ReviewRoot\v2" checkout FETCH_HEAD --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: git checkout FETCH_HEAD failed in v2\." -ForegroundColor Red
        Write-Host ""
        return
    }

    # Re-attach v2 HEAD to a named branch. Without this, v2\.git has a detached HEAD
    # (raw SHA), which Invoke-FinishReview copies into diff\.git — blocking Studio Pro commits.
    git -C "$ReviewRoot\v2" checkout -B $defaultBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Could not create branch '$defaultBranch' in v2\." -ForegroundColor Red
        Write-Host "       Studio Pro will not be able to commit after Finish Review." -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Run manually: git -C `"$ReviewRoot\v2`" checkout -B main" -ForegroundColor Yellow
        Write-Host ""
        return
    }
    Write-Host "[INFO] v2\ HEAD attached to branch '$defaultBranch'."
    Write-Host "[OK]   v2\ is at CommitB."
    Write-Host ""

    # Step 6: Prepare diff\ folder
    Write-Host "[DIFF] Syncing v2\ files into diff\ ..."
    robocopy "$ReviewRoot\v2" "$ReviewRoot\diff" /E /IS /IT /PURGE /XD "deployment" ".git" ".mendix-cache" /NP /NDL /NFL
    if ($LASTEXITCODE -ge 8) {
        Write-Host ""
        Write-Host "ERROR: robocopy failed while syncing files into diff\." -ForegroundColor Red
        Write-Host "       robocopy exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Check available disk space and write permissions on: $ReviewRoot\diff" -ForegroundColor Yellow
        Write-Host ""
        return
    }
    Write-Host "[OK]   Files synced."

    Write-Host "[DIFF] Preparing .git for review (v1 state as baseline)..."
    if (-not (Remove-DiffGit)) { return }
    if (-not (Copy-GitInto -SourceGit "$ReviewRoot\v1\.git" -DestGit "$ReviewRoot\diff\.git")) { return }
    Write-Host "[OK]   diff\.git is ready."
    Write-Host ""

    # Step 7: Open Studio Pro
    $opened = Open-StudioPro
    if (-not $opened) { return }

    # Post-open prompt: focused 2-option menu while Studio Pro is running
    Write-Host ""
    while ($true) {
        Write-Host "  1. Continue later (return to menu)"
        Write-Host "  2. Finish review  (close Studio Pro first, then switch to final state)"
        Write-Host ""
        $postChoice = (Read-Host "Enter choice (1-2)").Trim()
        Write-Host ""
        switch ($postChoice) {
            "1" { return }
            "2" { Invoke-FinishReview; return }
            default { Write-Host "  Please enter 1 or 2." -ForegroundColor Yellow }
        }
    }
}

function Invoke-ContinueReview {
    if (Test-DiffProjectOpen) { return }

    $commitsFile = Join-Path $ReviewRoot "commits.selected.ps1"
    if (-not (Test-Path $commitsFile)) {
        Write-Host ""
        Write-Host "ERROR: No review has been started yet." -ForegroundColor Red
        Write-Host "       commits.selected.ps1 was not found in: $ReviewRoot" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Use option 1 (Start review) to select commits and begin a review first." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host "[CONTINUE] Preparing diff\ for continued review..."

    if (-not (Remove-DiffGit)) { return }
    if (-not (Copy-GitInto -SourceGit "$ReviewRoot\v1\.git" -DestGit "$ReviewRoot\diff\.git")) { return }
    Write-Host "[OK]   diff\.git restored to v1 baseline."
    Write-Host ""

    Open-StudioPro | Out-Null
}

function Invoke-FinishReview {
    if (Test-DiffProjectOpen) { return }

    Write-Host "[FINISH] Preparing diff\ for finish review..."

    if (-not (Remove-DiffGit)) { return }
    if (-not (Copy-GitInto -SourceGit "$ReviewRoot\v2\.git" -DestGit "$ReviewRoot\diff\.git")) { return }
    Write-Host "[OK]   diff\.git set to v2 tip state."
    Write-Host ""

    Open-StudioPro | Out-Null
}

function Invoke-ChangePAT {
    Write-Host "[PAT] Removing stored PAT credential..."
    Remove-StoredPAT
    Write-Host ""
    Write-Host "[PAT] You will now be prompted to enter a new PAT."
    Get-StoredPAT -CredentialName $script:CredentialName | Out-Null
    Write-Host "[OK]  New PAT saved."
}

function Show-Help {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "    Mendix Code Review Tool -- Help" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "MENU OPTIONS"
    Write-Host "------------"
    Write-Host ""
    Write-Host "  1. Start review"
    Write-Host "     Select two commits from the git log. The tool fetches both commits,"
    Write-Host "     sets up the diff workspace, and opens Studio Pro in diff mode."
    Write-Host "     Use this to begin reviewing a new set of changes."
    Write-Host ""
    Write-Host "  2. Continue review"
    Write-Host "     Reopens the current review in Studio Pro without changing the selected"
    Write-Host "     commits. Use this if you closed Studio Pro mid-review."
    Write-Host ""
    Write-Host "  3. Finish review"
    Write-Host "     Switches the diff workspace to show the final (v2) state of the project"
    Write-Host "     and reopens Studio Pro. Use this when you have finished reviewing all"
    Write-Host "     changes and want to confirm the end state of the project."
    Write-Host ""
    Write-Host "  4. Change PAT"
    Write-Host "     Updates your stored Personal Access Token. Use this if your PAT has"
    Write-Host "     expired or been revoked, or if you see authentication errors."
    Write-Host ""
    Write-Host "  5. Help"
    Write-Host "     Shows this help text."
    Write-Host ""
    Write-Host "FOLDER STRUCTURE"
    Write-Host "----------------"
    Write-Host ""
    Write-Host "  Review root: $ReviewRoot"
    Write-Host ""
    Write-Host "  v1\    -- Project at CommitA (the base state, before the changes under review)."
    Write-Host "            Studio Pro compares diff\ against this to generate the diff view."
    Write-Host ""
    Write-Host "  v2\    -- Project at CommitB (the tip state, after the changes under review)."
    Write-Host "            The actual changed files are copied from here into diff\."
    Write-Host ""
    Write-Host "  diff\  -- The workspace opened in Studio Pro. Contains v2 files with"
    Write-Host "            v1's .git folder so Studio Pro sees all changes as modifications."
    Write-Host ""
    Write-Host "REGENERATING FROM SCRATCH"
    Write-Host "-------------------------"
    Write-Host ""
    Write-Host "  If you want to start completely fresh (e.g. the workspace is broken):"
    Write-Host "    1. Delete this review root:"
    Write-Host "         Remove-Item -Recurse -Force `"$ReviewRoot`""
    Write-Host "    2. Navigate to your Mendix project folder and re-run Setup.ps1:"
    Write-Host "         cd `"<your-project-folder>`""
    Write-Host "         .\Setup.ps1"
    Write-Host ""
}


# ==============================================================================
# Main menu loop
# ==============================================================================

while ($true) {
    Show-WorkspaceState
    Write-Host "What would you like to do?"
    Write-Host "  1. Start review"
    Write-Host "  2. Continue review"
    Write-Host "  3. Finish review"
    Write-Host "  4. Change PAT"
    Write-Host "  5. Help"
    Write-Host "  Q. Quit"
    Write-Host ""

    $choice = (Read-Host "Enter choice (1-5), or Q to quit").Trim()

    Write-Host ""

    switch ($choice) {
        "1" { Invoke-StartReview }
        "2" { Invoke-ContinueReview }
        "3" { Invoke-FinishReview }
        "4" { Invoke-ChangePAT }
        "5" { Show-Help }
        { $_ -eq "Q" -or $_ -eq "q" } { Write-Host "Goodbye."; Exit-Script 0 }
        default { Write-Host "  Please enter a number between 1 and 5, or Q to quit." -ForegroundColor Yellow }
    }

    Write-Host ""
}
