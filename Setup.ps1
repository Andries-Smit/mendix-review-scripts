# ==============================================================================
# Setup.ps1 -- Mendix Code Review Tool -- One-time workspace initialisation
# Run this script from inside your Mendix source project folder.
# ==============================================================================

$script:ScriptVersion = "1.1"

# -- Step 1: Welcome message ---------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    Mendix Code Review Tool -- Setup  (v$($script:ScriptVersion))" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This tool creates a review workspace for comparing two Mendix"
Write-Host "commits side-by-side using Studio Pro's built-in diff view."
Write-Host ""
Write-Host "The workspace contains three folders:"
Write-Host "  v1\    -- the project checked out at CommitA (base/before state)"
Write-Host "  v2\    -- the project checked out at CommitB (tip/after state)"
Write-Host "  diff\  -- the diff workspace opened in Studio Pro for review"
Write-Host ""
Write-Host "This setup script runs ONCE to create the workspace."
Write-Host "Afterwards, use Diff.ps1 in the review root to manage reviews."
Write-Host ""

# -- Step 1b: Verify git is available ------------------------------------------
$gitVersion = git --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: git was not found on your PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Install Git for Windows from https://git-scm.com/download/win" -ForegroundColor Yellow
    Write-Host "  After installation, close and reopen this PowerShell window, then re-run Setup.ps1." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
Write-Host "[OK] git found: $gitVersion"
Write-Host ""

# -- Step 2: Validate source folder --------------------------------------------
$mprFiles = @(Get-ChildItem -Path . -Filter "*.mpr" -File)

if ($mprFiles.Count -ne 1) {
    Write-Host ""
    Write-Host "ERROR: This script must be run from a Mendix project folder." -ForegroundColor Red
    Write-Host "       Expected exactly 1 .mpr file in the current directory." -ForegroundColor Red
    Write-Host "       Found: $($mprFiles.Count)" -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Navigate to your Mendix project folder and run Setup.ps1 from there." -ForegroundColor Yellow
    Write-Host "  Example:" -ForegroundColor Yellow
    Write-Host "    cd C:\Projects\MyMendixApp" -ForegroundColor Yellow
    Write-Host "    .\Setup.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$sourcePath = (Get-Location).Path
Write-Host "[OK] Mendix project found: $($mprFiles[0].Name)"
Write-Host "     Source folder: $sourcePath"
Write-Host ""

# -- Step 2b: Check for .mpr.lock (Studio Pro still open) ----------------------
$lockFile = $mprFiles[0].FullName + ".lock"
if (Test-Path $lockFile) {
    Write-Host "WARNING: A .mpr.lock file was found:" -ForegroundColor Yellow
    Write-Host "         $lockFile" -ForegroundColor Yellow
    Write-Host "         This usually means Studio Pro is still open with this project." -ForegroundColor Yellow
    Write-Host "         Copying a project while it is open may result in an inconsistent workspace." -ForegroundColor Yellow
    Write-Host ""
    $confirm = (Read-Host "Close Studio Pro first, then press Enter, or type Y to copy anyway [y/N]").Trim()
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "[INFO] Aborted. Close Studio Pro and re-run Setup.ps1." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

# -- Step 2c: Check for uncommitted changes ------------------------------------
$gitStatus = git status --porcelain 2>&1
if ($LASTEXITCODE -eq 0 -and $gitStatus) {
    $changedCount = @($gitStatus | Where-Object { $_ }).Count
    Write-Host "WARNING: The project has $changedCount uncommitted file(s):" -ForegroundColor Yellow
    $gitStatus | ForEach-Object { Write-Host "         $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "         It is recommended to commit all changes in Studio Pro before" -ForegroundColor Yellow
    Write-Host "         running Setup, so the review workspace starts from a clean state." -ForegroundColor Yellow
    Write-Host ""
    $confirm = (Read-Host "Continue with uncommitted changes? [y/N]").Trim()
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "[INFO] Aborted. Commit your changes in Studio Pro and re-run Setup.ps1." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

# -- Step 3: Determine review root path ----------------------------------------
$sourceLeaf   = Split-Path $sourcePath -Leaf
$sourceParent = Split-Path $sourcePath -Parent
$defaultReviewRoot = Join-Path $sourceParent "$sourceLeaf-review"

Write-Host "Review root path (the folder that will contain v1, v2, diff and Diff.ps1):"
Write-Host "  Default: $defaultReviewRoot"
Write-Host ""
$userInput = Read-Host "Press Enter to accept the default, or type a custom path"

if ($userInput.Trim() -eq "") {
    $ReviewRoot = $defaultReviewRoot
} else {
    $ReviewRoot = [IO.Path]::GetFullPath($userInput.Trim())
}

Write-Host ""
Write-Host "Review root will be created at:"
Write-Host "  $ReviewRoot"
Write-Host ""
Read-Host "Press Enter to continue, or Ctrl+C to abort"
Write-Host ""

# -- Step 4: Guard -- review root must not already exist -----------------------
if (Test-Path $ReviewRoot) {
    Write-Host ""
    Write-Host "ERROR: The review root folder already exists:" -ForegroundColor Red
    Write-Host "       $ReviewRoot" -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Setup has already been run for this project." -ForegroundColor Yellow
    Write-Host "  To start or continue a review, run Diff.ps1 from the review root:" -ForegroundColor Yellow
    Write-Host "    cd `"$ReviewRoot`"" -ForegroundColor Yellow
    Write-Host "    .\Diff.ps1" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  If you want to start fresh, delete the review root first:" -ForegroundColor Yellow
    Write-Host "    Remove-Item -Recurse -Force `"$ReviewRoot`"" -ForegroundColor Yellow
    Write-Host "  Then re-run Setup.ps1." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# -- Step 5: Create folder structure -------------------------------------------
Write-Host "[SETUP] Creating review folder structure..."
try {
    New-Item -ItemType Directory -Path "$ReviewRoot\v1"   | Out-Null
    New-Item -ItemType Directory -Path "$ReviewRoot\v2"   | Out-Null
    New-Item -ItemType Directory -Path "$ReviewRoot\diff" | Out-Null
    Write-Host "[OK]   Created: $ReviewRoot\v1"
    Write-Host "[OK]   Created: $ReviewRoot\v2"
    Write-Host "[OK]   Created: $ReviewRoot\diff"
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to create the review folder structure." -ForegroundColor Red
    Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Check that you have write permission to: $(Split-Path $ReviewRoot -Parent)" -ForegroundColor Yellow
    Write-Host "  Also make sure the path does not contain invalid characters." -ForegroundColor Yellow
    Write-Host ""
    if (Test-Path $ReviewRoot) {
        Remove-Item -Recurse -Force $ReviewRoot -ErrorAction SilentlyContinue
    }
    exit 1
}
Write-Host ""

# -- Step 6: Copy source into v1, v2, diff -------------------------------------
# robocopy is used instead of Copy-Item because Mendix projects contain deep
# node_modules trees that exceed the MAX_PATH limit. robocopy handles this
# natively. Exit codes 0-7 are all non-error variants; 8+ indicate failures.

foreach ($dest in @("v1", "v2", "diff")) {
    $destPath = "$ReviewRoot\$dest"
    Write-Host "[COPY] Copying source project to $dest\ (this may take several minutes)..."
    robocopy $sourcePath $destPath /E /XD "deployment" ".mendix-cache" "packages" "releases" /XF "*.mpr.lock" /NP /NDL /NFL
    if ($LASTEXITCODE -ge 8) {
        Write-Host ""
        Write-Host "ERROR: robocopy failed while copying to $dest\" -ForegroundColor Red
        Write-Host "       robocopy exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Check available disk space and write permissions on:" -ForegroundColor Yellow
        Write-Host "    $destPath" -ForegroundColor Yellow
        Write-Host "  Then delete the review root and re-run Setup.ps1:" -ForegroundColor Yellow
        Write-Host "    Remove-Item -Recurse -Force `"$ReviewRoot`"" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
    Write-Host "[OK]   Copy to $dest\ complete."
    Write-Host ""
}

# -- Step 7: Copy scripts into the review root ---------------------------------
foreach ($scriptName in @("Diff.ps1", "StorePat.ps1", "SelectCommits.ps1")) {
    $scriptSrc = Join-Path $PSScriptRoot $scriptName
    if (Test-Path $scriptSrc) {
        try {
            Copy-Item -Path $scriptSrc -Destination "$ReviewRoot\$scriptName"
            Write-Host "[OK] $scriptName copied to review root."
        } catch {
            Write-Host ""
            Write-Host "ERROR: Could not copy $scriptName to the review root." -ForegroundColor Red
            Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "HOW TO FIX:" -ForegroundColor Yellow
            Write-Host "  Copy $scriptName manually from:" -ForegroundColor Yellow
            Write-Host "    $scriptSrc" -ForegroundColor Yellow
            Write-Host "  To:" -ForegroundColor Yellow
            Write-Host "    $ReviewRoot\$scriptName" -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }
    } else {
        Write-Host "[WARN] $scriptName was not found next to Setup.ps1." -ForegroundColor Yellow
        Write-Host "       Expected at: $scriptSrc" -ForegroundColor Yellow
        Write-Host "       Copy it to the review root manually once it is available:" -ForegroundColor Yellow
        Write-Host "         $ReviewRoot\$scriptName" -ForegroundColor Yellow
    }
}
Write-Host ""

# -- Step 8: Done message ------------------------------------------------------
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Review root: $ReviewRoot"
Write-Host ""
Write-Host "Next step -- run Diff.ps1 to start a review:"
Write-Host "  cd `"$ReviewRoot`""
Write-Host "  .\Diff.ps1"
Write-Host ""
