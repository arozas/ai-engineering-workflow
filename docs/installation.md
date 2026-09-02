# Installation, updates, and new projects

## Before installation

The target must be an initialized Git repository for `Local` mode because the installer uses the repository-local exclude file. Run the dry run first whenever the target may already contain `AGENTS.md`, `opencode.json`, `.ai/`, or `.opencode/`.

The installer is conflict-intolerant by design. It inventories every managed destination and aborts instead of overwriting an existing file. Review conflicts deliberately; do not delete a project's existing instructions merely to make the installer pass.

## Local mode

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -TargetPath "C:\repos\application" `
  -Mode Local
```

Local mode is recommended for evaluation, individual use, and teams that do not want runtime orchestration files in application pull requests.

It:

1. Verifies that every workflow-owned target path is currently untracked.
2. Captures the initial Git status.
3. Copies the versioned template.
4. Writes installation metadata.
5. Adds an identified managed block to `.git/info/exclude`.
6. Verifies that installed paths are ignored and the visible Git status is unchanged.

It does not edit the tracked `.gitignore`, create a branch, stage files, or commit anything. Because `.git/info/exclude` belongs to one clone, another developer must install the workflow independently.

Use `-ShareProjectContext` with Local mode only when the runtime should remain local but approved project context is meant to be visible to Git. Review the resulting exclude set with `-DryRun` before using this option.

## Shared mode

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -TargetPath "C:\repos\application" `
  -Mode Shared
```

Shared mode copies the same payload without clone-local exclusions. Git will show the files as untracked, allowing the team to review and commit them through its normal process. The installer still never stages or commits them.

Choose Shared mode when:

- the repository owners have agreed to version the workflow;
- agents and project rules should be identical in every clone;
- control-plane updates will be reviewed like application tooling;
- the additional repository surface is acceptable.

Do not switch an existing Local installation to Shared by merely deleting the exclude block. Use the documented update or reinstall path so metadata and managed hashes remain consistent.

## Dry run

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -TargetPath "C:\repos\application" `
  -Mode Local `
  -DryRun
```

The preview reports intended files, conflicts, installation mode, and Git exclusion behavior without writing. A successful dry run is not an approval for later application changes; it only validates installation feasibility.

## Installation metadata

`.ai/workflow-installation.json` records the workflow version, manifest identity, installation mode, sharing choice, managed files and hashes, local excluded paths, and installation time. The updater relies on these hashes to distinguish an unchanged managed file from a user customization.

Treat metadata as managed control-plane content. In Local mode it remains excluded with the rest of the runtime. In Shared mode it can be versioned to make the installed distribution version explicit.

## Updating an installation

Preview:

```powershell
pwsh -NoProfile -File .\scripts\update.ps1 `
  -TargetPath "C:\repos\application" `
  -DryRun
```

Apply:

```powershell
pwsh -NoProfile -File .\scripts\update.ps1 `
  -TargetPath "C:\repos\application"
```

The updater compares current managed files with the hashes recorded at installation. If a managed file was edited locally, it stops instead of overwriting the customization. Resolve the conflict by deciding whether to keep the local change, move it into supported project context, or accept the distribution version through a separately reviewed change.

After a control-plane update, start new workflow runs. Existing runs retain fingerprints of the previous policy and correctly refuse to advance.

## Creating a project from a preset

Discover presets:

```powershell
pwsh -NoProfile -File .\scripts\new-project.ps1 -ListPresets
```

Preview a project:

```powershell
pwsh -NoProfile -File .\scripts\new-project.ps1 `
  -Name "catalog" `
  -ParentPath "C:\repos" `
  -Preset react-vite `
  -Architecture vertical-slice `
  -Mode Local `
  -InitializeGit `
  -DryRun
```

Remove `-DryRun` to create it. The generator validates preset identifiers, copies the project preset, composes requested stack and architecture context, optionally initializes Git, and installs the workflow using the selected mode.

Available project presets:

- `empty`: only the workflow and a minimal project shell.
- `dotnet-webapi`: a .NET web API starting point.
- `node-basic`: a basic Node.js project.
- `python-basic`: a basic Python project.
- `react-vite`: a React/Vite project.

Available stack profiles are `dotnet`, `java`, `node`, `python`, and `react`. Architecture presets are `clean`, `event-driven`, `hexagonal`, `simple-layered`, and `vertical-slice`.

Presets are starting points, not evidence about an existing repository. Existing projects must use `/ai-bootstrap` so their configuration is derived from their own files.

## First run in a consumer repository

1. Install OpenCode V2 and confirm `opencode2 --version` works in a new terminal.
2. Change to the consumer repository root.
3. Start `opencode2`.
4. Run `/ai-bootstrap`.
5. Review and optionally edit the durable proposal under `.ai/bootstrap-proposal/`.
6. Run `/ai-bootstrap-apply` when the proposal is approved.
7. Wait for `PROJECT_VALID` before using `/ticket`, `/diagnose`, or `/ai-refresh`.

The bootstrap proposal is a draft only. It may be overwritten by rerunning `/ai-bootstrap`, and it is excluded from Local-mode application commits. Approval applies to the draft files under `.ai/bootstrap-proposal/`; repository drift between proposal and persistence blocks the write.

Every later workflow run stages its candidate artifacts under `.ai/runtime/<run-id>/`; concurrent OpenCode sessions must keep and pass their exact run IDs. Local mode excludes both runtime staging and canonical `.ai/runs/<run-id>/` evidence from application commits.
