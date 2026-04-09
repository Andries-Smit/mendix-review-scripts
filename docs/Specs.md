# Mendix Code Review Tool — Specification

## Goal
Automate the Mendix code review process currently described in `CodeReviewProcedure.md`.  
Produces two PowerShell scripts: **`Setup.ps1`** and **`Review.ps1`**.

---

## Shared Assumptions

- The user's Mendix project folder is a local git repository (cloned from the Mendix git server).
- The project folder contains exactly one `.mpr` file in its root.
- Git is available on `PATH`.
- Mendix Studio Pro is installed. Its executable is found by scanning `C:\Program Files\Mendix\` for the newest version of `studiopro.exe`.
- PAT storage reuses the `Get-StoredPAT` function from `StorePat.ps1` (dot-sourced where needed). The credential name is `"MendixReview_PAT"`.
- The `CredentialManager` PowerShell module must be present (same fail-safe check as in `StorePat.ps1`).

---

## Folder Structure

```
<ReviewRoot>/            ← default: sibling of source project, named "<ProjectFolderName>-review"
  v1/                    ← full copy of source project checked out at CommitA (base)
  v2/                    ← full copy of source project checked out at CommitB (tip)
  diff/                  ← full copy of source project (v2 files + v1's .git for git diff)
  Review.ps1               ← copied here during Setup so reviewers only need this one file
```

---

## Script 1 — `Setup.ps1`

**Purpose:** One-time initialisation. Run from inside the source project folder.

### Steps

1. **Welcome message**  
   Print a short explanation of what the tool does and how the review process works.

2. **Validate source folder**  
   - Check that the current directory contains exactly one `.mpr` file.  
   - If not found: print an error explaining the requirement and exit.

3. **Determine review root path**  
   - Default: sibling folder named `<CurrentFolderName>-review`  
     (e.g. source = `C:\Projects\MyApp` → review root = `C:\Projects\MyApp-review`)  
   - Prompt the user to accept the default or enter a custom path.  
   - Show the resolved path and ask for confirmation before continuing.

4. **Guard: review root must not already exist**  
   - If the folder already exists: print an error saying setup has already been run,  
     direct the user to run `Review.ps1` instead, and exit.

5. **Create folder structure**  
   Create `<ReviewRoot>\v1`, `<ReviewRoot>\v2`, `<ReviewRoot>\diff`.

6. **Copy source project into all three subfolders**  
   Copy the entire source project (excluding the `deployment\` subfolder) into `v1`, `v2`, and `diff`.  
   - Print progress as folders are copied (this can take several minutes).  
   - After each of the three copies completes, print a status line.

7. **Copy `Review.ps1` into the review root**  
   Copy `Review.ps1` from the same directory as `Setup.ps1` to `<ReviewRoot>\Review.ps1`.

8. **Done message**  
   Print the path to `<ReviewRoot>\Review.ps1` and instruct the user to run it from the review root to start a review.

---

## Script 2 — `Review.ps1`

**Purpose:** Ongoing review management. Lives in `<ReviewRoot>` and is run from there.

### Startup validation

Before showing the menu, verify the environment:

- The current directory must **not** contain a `.mpr` file directly (it is the review root, not a project folder).
- The current directory must contain the three subfolders `v1`, `v2`, and `diff`, each of which must contain a `.mpr` file.
- If validation fails: print a clear error explaining the expected layout, show remediation steps, and exit.

### Main menu

After validation, display an interactive numbered menu and wait for input:

```
What would you like to do?
  1. Start review
  2. Continue review
  3. Finish review
  4. Change PAT
  5. Help
```

---

### Action 1 — Start Review

1. **Check for uncommitted changes in `diff\`**  
   Run `git -C diff status --porcelain`.  
   If output is non-empty: warn the user that there are uncommitted changes and exit without making any changes.

2. **PAT authentication**  
   Call `Get-StoredPAT -CredentialName "MendixReview_PAT"`.  
   - If no PAT is stored, the function prompts the user to enter one and saves it.  
   - Verify the PAT works by making a test request to the Mendix git API before continuing.  
   - If the PAT is invalid: tell the user to use option 4 (Change PAT) and exit.

3. **Select commit range**  
   Run the interactive commit-selector logic from `SelectCommits.ps1` (dot-source it).  
   - Point it at the `v1\` folder as the repo path (it has the full git history).  
   - The selector outputs `$CommitA` (base, before range) and `$CommitB` (tip, newest selected).

4. **Update `v1\` to CommitA**  
   Inside `v1\`:
   ```
   git fetch --depth 1 origin <CommitA>
   git checkout FETCH_HEAD
   ```

5. **Update `v2\` to CommitB**  
   Inside `v2\`:
   ```
   git fetch --depth 1 origin <CommitB>
   git checkout FETCH_HEAD
   ```

6. **Prepare `diff\` folder**  
   - Copy all project files from `v2\` into `diff\` (overwrite, excluding `deployment\` and `.git\`).  
   - Remove `diff\.git\`.  
   - Copy `v1\.git\` into `diff\.git\`.

7. **Open Studio Pro**  
   Launch Studio Pro with the `.mpr` file found in `diff\`.  
   Do not wait for it to close — continue to step 8.

8. **Post-open prompt**  
   Display:
   ```
   Studio Pro is open. What would you like to do?
     1. Continue later  (closes this script; run again and choose "Continue review")
     2. Finish review   (performs the Finish Review action below)
   ```

---

### Action 2 — Continue Review

1. Remove `diff\.git\`.
2. Copy `v1\.git\` into `diff\.git\`.
3. Open Studio Pro with the `.mpr` file in `diff\`.

---

### Action 3 — Finish Review

1. Remove `diff\.git\`.
2. Copy `v2\.git\` into `diff\.git\`.
3. Open Studio Pro with the `.mpr` file in `diff\`.

---

### Action 4 — Change PAT

Remove the stored credential `"MendixReview_PAT"` from Windows Credential Manager  
(using `Remove-StoredCredential`), then call `Get-StoredPAT` to prompt the user for a new one.

---

### Action 5 — Help

Print a concise explanation of:
- What each action does and when to use it.
- The folder structure and why it exists.
- How to regenerate the review setup from scratch (delete `<ReviewRoot>` and rerun `Setup.ps1`).

---

## Error Handling Requirements

All scripts must follow the fail-safe pattern established in `StorePat.ps1`:
- Every error prints `ERROR:` in red followed by a `HOW TO FIX:` block in yellow.
- All `exit` calls use code `1` for errors, `0` for clean exits.
- Git and file-copy operations check `$LASTEXITCODE` / use `try/catch` and surface meaningful messages.
- Long-running copy operations show progress so the user knows the script has not hung.
