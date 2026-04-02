# Get-PAT.ps1 — retrieves PAT from Credential Manager, prompts once if missing

# Ensure CredentialManager module is available
if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
    Write-Host ""
    Write-Host "ERROR: The 'CredentialManager' PowerShell module is not installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "HOW TO FIX:" -ForegroundColor Yellow
    Write-Host "  Run the following command in PowerShell (as your normal user, no admin needed):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "      Install-Module -Name CredentialManager -Scope CurrentUser -Force" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Then re-run this script." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Import-Module CredentialManager -ErrorAction Stop

function Get-StoredPAT {
    param(
        [string]$CredentialName = "MendixReview_PAT"
    )

    # Try to load the credential silently
    $cred = Get-StoredCredential -Target $CredentialName -ErrorAction SilentlyContinue

    if (-not $cred) {
        Write-Host "Checking Windows Credential Manager"
        Write-Host "No stored PAT found. You will be prompted once." -ForegroundColor Yellow
        Write-Host "Your PAT will be stored in your Windows Credential Manager, and only accessible by you"

        $securePAT = Read-Host -Prompt "Enter your Personal Access Token" -AsSecureString

        # Validate the user didn't just press Enter
        if ($securePAT.Length -eq 0) {
            Write-Host ""
            Write-Host "ERROR: No PAT entered. The script cannot continue without a token." -ForegroundColor Red
            Write-Host ""
            Write-Host "HOW TO FIX:" -ForegroundColor Yellow
            Write-Host "  Re-run the script and paste your Personal Access Token when prompted." -ForegroundColor Yellow
            Write-Host "  You can generate a PAT at:" -ForegroundColor Yellow
            Write-Host "    https://sprintr.home.mendix.com/index.html  (Profile > Security > API Keys)" -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }

        # Store it in Windows Credential Manager (encrypted, current user only)
        try {
            New-StoredCredential `
                -Target $CredentialName `
                -UserName $env:USERNAME `
                -SecurePassword $securePAT `
                -Type Generic `
                -Persist LocalMachine | Out-Null
        } catch {
            Write-Host ""
            Write-Host "ERROR: Failed to save the PAT to Windows Credential Manager." -ForegroundColor Red
            Write-Host "  Reason: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "HOW TO FIX:" -ForegroundColor Yellow
            Write-Host "  Make sure you are running PowerShell as yourself (not SYSTEM or a service account)." -ForegroundColor Yellow
            Write-Host "  Windows Credential Manager requires an interactive user session." -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }

        Write-Host "PAT saved to Credential Manager as '$CredentialName'." -ForegroundColor Green
        $cred = Get-StoredCredential -Target $CredentialName
    }

    # Guard: credential should exist at this point
    if (-not $cred) {
        Write-Host ""
        Write-Host "ERROR: Could not retrieve the stored credential '$CredentialName'." -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  1. Open 'Credential Manager' in Windows (search in Start menu)." -ForegroundColor Yellow
        Write-Host "  2. Go to 'Windows Credentials' and look for an entry named '$CredentialName'." -ForegroundColor Yellow
        Write-Host "  3. If it is missing or corrupt, delete it and re-run this script." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    # Return as plain text (only in memory, never written to disk)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)
    )
}
