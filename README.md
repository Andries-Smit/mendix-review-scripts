# Mendix Code Review Tool

Automates the diff-folder review process described in [CodeReviewProcedure.md](docs/CodeReviewProcedure.md).

> **Before using these scripts, read [CodeReviewProcedure.md](docs/CodeReviewProcedure.md) and complete the process manually at least once.**  
> The scripts automate steps you need to understand first. If something goes wrong, you will not know how to recover without that background.

---

## Prerequisites

- Mendix Studio Pro 10 (Git-based project)
- Git command line on `PATH`
- PowerShell 5.1 or later
- A Mendix Personal Access Token (PAT) with `mx:modelrepository:repo:read` scope  
  Generate one at **sprintr.home.mendix.com → Profile → Security → API Keys**
- `CredentialManager` PowerShell module (installed automatically on first run if missing — see the error message for the exact command)

---

## One-time Setup

1. **Copy the scripts into your Mendix project folder**

   Create a folder `scripts/` root of your Mendix project (next to the `.mpr` file), and add the following scripts:
   - `Setup.ps1`
   - `Review.ps1`
   - `StorePat.ps1`
   - `SelectCommits.ps1`

2. **Commit the project in Studio Pro**

   Open the project in Studio Pro and commit any pending changes before running Setup.  
   The review workspace is built from the current state of the repository.

3. **Run Setup.ps1**

   Open PowerShell, navigate to your project folder, and run:
   ```powershell
   cd "C:\Projects\MyMendixApp\scripts"
   .\Setup.ps1
   ```

   The script will:
   - Confirm the review root path (default: `<ProjectFolder>-review`, next to your project)
   - Copy the project into three subfolders: `v1\`, `v2\`, `diff\`
   - Copy the scripts into the review root

   > This copy can take several minutes for large projects.

4. **Navigate to the review root and run Review.ps1**

   ```powershell
   cd "C:\Projects\MyMendixApp-review"
   .\Review.ps1
   ```

Setup only needs to be done once per project. After that, always run `Review.ps1` from the review root.

---

## Using Review.ps1

Run `Review.ps1` from the review root. It shows a menu:

```
What would you like to do?
  1. Start review
  2. Continue review
  3. Finish review
  4. Change PAT
  5. Help
```

| Option | When to use |
|--------|-------------|
| **1. Start review** | Begin reviewing a new set of commits. You will pick a commit range from the git log, the tool fetches both ends, sets up the diff workspace, and opens Studio Pro. |
| **2. Continue review** | You closed Studio Pro mid-review. Reopens the same workspace without changing the selected commits. |
| **3. Finish review** | You are done reviewing. Swaps the workspace to the v2 baseline so you can see only your own fixes, then reopens Studio Pro to commit them. |
| **4. Change PAT** | Your PAT has expired or authentication is failing. Replaces the stored token. |
| **5. Open log file** | Opens the detailed log. |
| **5. Help** | In-tool explanation of the folder structure and each option. |

Enter `Q` at the menu to quit.

### Start review — selecting commits - Step 1

On **Start review** select the commits you would like to review

```
  [Phase 2] Navigate DOWN to extend range end. ENTER / SPACE to confirm. ESC to reset.    
  Range: 2-5  |  CommitB (tip): 925f862  |  CommitA (base): c95db44
   #      Hash      Date        Author              Subject
   ---    --------  ----------  ------------------  --------------------------------------
     1     d70ee7f  2026-04-02  Jhon Doe            Extra feature
     2 [+  925f862  2026-04-02  Alice               Fix some stuff
     3  |  3998371  2026-04-02  Alice               Add Microflow
>    4  +] 9723bea  2026-04-02  Alice               Add page
     5     b9e67b3  2026-04-02  Jhon Doe            My awesome feature
     6     c95db44  2026-04-02  Jhon Doe            Initial app upload.
```
---

### Applying changes from a review, in step 3

> **Experimental — handle with care.**  
> Making and committing changes from inside the review workspace is supported, but is not the primary use-case of this tool.

This tool fills a gap: ideally Mendix Studio Pro would have native support for reviewing a commit range and applying reviewer fixes directly. Until that exists, you can use **Finish review** to commit your changes back to the branch.

**How it works:** Finish review swaps the `diff\` workspace to the v2 baseline, so only your own edits appear as local modifications. You can then review and commit those changes in Studio Pro.

**Limitations to be aware of:**

- **Rebasing requirement when not at HEAD.** If the reviewed commits are not at the tip of the branch, you will need to rebase your fix commit onto HEAD after committing. Without this your changes target an older tree and will require conflict resolution during the rebase.

- **Keep changes small.** Every change you commit from the review workspace becomes a potential source of merge conflicts for any commits that follow the reviewed range. Large refactoring changes are strongly recommended to be done directly at the HEAD of the branch instead, where conflict surface is minimal.

## How it works (short version)

See [CodeReviewProcedure.md](docs/CodeReviewProcedure.md) for the full explanation.

In short: the `diff\` folder contains the **new files** (CommitB) but the **old git history** (CommitA). Studio Pro sees the gap between them and presents every change as a local modification — giving you a clean visual diff of everything that changed across your selected commits.

## Development

### Tests

```
 Invoke-Pester ./tests     
```
