# StorePat.ps1 — PAT storage via DPAPI (no external module required)
# Dot-sourced by Review.ps1. Exposes Get-StoredPAT and Remove-StoredPAT.

Add-Type -AssemblyName System.Security   # Required for ProtectedData

$script:PatFile    = Join-Path $env:APPDATA "MendixReview\pat.dpapi"
$script:PatEntropy = [System.Text.Encoding]::UTF8.GetBytes("MendixReview_PAT_v1")

function Get-StoredPAT {
    param(
        [string]$CredentialName = "MendixReview_PAT"   # kept for call-site compatibility
    )

    # -- Try to load existing encrypted PAT --
    if (Test-Path $script:PatFile) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($script:PatFile)
            $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $bytes, $script:PatEntropy,
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            $pat = [System.Text.Encoding]::UTF8.GetString($plain)
            if ($pat.Length -gt 0) { return $pat }
        } catch {
            Write-Host "[WARN] Could not decrypt stored PAT: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # -- Prompt once --
    Write-Host "No stored PAT found. You will be prompted once." -ForegroundColor Yellow
    Write-Host "Your PAT will be stored encrypted in: $script:PatFile"
    Write-Host ""

    $securePAT = Read-Host -Prompt "Enter your Personal Access Token" -AsSecureString

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

    # Convert SecureString to plain text (in memory only, never written as plain text)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePAT)
    $pat  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    # -- Encrypt with DPAPI and persist --
    try {
        $dir = Split-Path $script:PatFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

        $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
            [System.Text.Encoding]::UTF8.GetBytes($pat),
            $script:PatEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        [System.IO.File]::WriteAllBytes($script:PatFile, $encrypted)
        Write-Host "PAT saved (encrypted) to: $script:PatFile" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "ERROR: Failed to save the PAT." -ForegroundColor Red
        Write-Host "  Reason: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "HOW TO FIX:" -ForegroundColor Yellow
        Write-Host "  Make sure you have write access to: $(Split-Path $script:PatFile -Parent)" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    return $pat
}

function Remove-StoredPAT {
    if (Test-Path $script:PatFile) {
        Remove-Item -Path $script:PatFile -Force -ErrorAction SilentlyContinue
        Write-Host "[OK]  Stored PAT file removed."
    } else {
        Write-Host "[OK]  No stored PAT file found (nothing to remove)."
    }
}
