[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [Parameter(Mandatory = $true)][string]$Title,
    [string]$BodyFile = '.ai/pr-draft.md'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to create a pull request.' }
if ($null -eq $ghCommand) { throw 'GitHub CLI is required to create a pull request.' }
if ($Base -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$') { throw "Invalid base branch: $Base" }
if ([string]::IsNullOrWhiteSpace($Title) -or $Title.Contains("`n") -or $Title.Contains("`r")) {
    throw 'Pull-request title must be a non-empty single line.'
}

$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The current location is not inside a Git repository.'
}
$repositoryRoot = $repositoryRoot.Trim()
$branch = (& $gitCommand.Source -C $repositoryRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'Pull-request creation requires a named branch.'
}
if ($branch -match '^(main|master|develop|development|trunk|release)(/|$)' -or $branch -eq $Base) {
    throw "Refusing to create a pull request from protected, shared, or base branch '$branch'."
}

$bodyPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $BodyFile))
if (-not $bodyPath.StartsWith($repositoryRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Pull-request body file must be inside the repository.'
}
if (-not (Test-Path -LiteralPath $bodyPath -PathType Leaf)) { throw "Pull-request body file not found: $bodyPath" }
if ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $bodyPath -Raw))) { throw 'Pull-request body is empty.' }

$status = @(& $gitCommand.Source -C $repositoryRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the working tree.' }
if ($status.Count -gt 0) { throw 'Draft PR creation requires a clean working tree. The ignored .ai/pr-draft.md is allowed.' }

$upstream = (& $gitCommand.Source -C $repositoryRoot rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstream)) {
    throw 'The current branch has no upstream. Run the approved publish workflow first.'
}

$existingJson = (& $ghCommand.Source pr list --head $branch --state open --json number,url)
if ($LASTEXITCODE -ne 0) { throw 'Unable to check for an existing pull request.' }
$existing = @($existingJson | ConvertFrom-Json)
if ($existing.Count -gt 0) { throw "An open pull request already exists: $($existing[0].url)" }

& $ghCommand.Source pr create --draft --base $Base --head $branch --title $Title --body-file $bodyPath
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI failed to create the draft pull request.' }
