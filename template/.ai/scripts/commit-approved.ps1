[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Subject,
    [string]$Body
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to create a commit.' }

$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The current location is not inside a Git repository.'
}
$repositoryRoot = $repositoryRoot.Trim()
$branch = (& $gitCommand.Source -C $repositoryRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'Commits require a named branch; detached HEAD is not supported.'
}
if ($branch -match '^(main|master|develop|development|trunk|release)(/|$)') {
    throw "Refusing to create a workflow commit directly on protected or shared branch '$branch'."
}

$fullMessage = $Subject
if (-not [string]::IsNullOrWhiteSpace($Body)) {
    $fullMessage += "`n`n" + $Body.Trim()
}
$validatorPath = Join-Path $PSScriptRoot 'validate-commit-message.ps1'
& $validatorPath -Message $fullMessage | Out-Null

$stagedFiles = @(& $gitCommand.Source -C $repositoryRoot diff --cached --name-only --diff-filter=ACDMRTUXB)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect staged changes.' }
if ($stagedFiles.Count -eq 0) { throw 'No staged changes are available to commit.' }
foreach ($stagedFile in $stagedFiles) {
    $normalizedPath = $stagedFile.Replace('\', '/')
    if ($normalizedPath -match '(^|/)\.env($|\.)' -and $normalizedPath -notmatch '(^|/)\.env\.example$') {
        throw "Refusing to commit a protected environment file: $stagedFile"
    }
}

$messageFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-engineering-workflow-commit-" + [Guid]::NewGuid().ToString('N') + '.txt')
try {
    Set-Content -LiteralPath $messageFile -Value $fullMessage -Encoding utf8
    & $gitCommand.Source -C $repositoryRoot commit --cleanup=verbatim --file $messageFile
    if ($LASTEXITCODE -ne 0) { throw 'Git commit failed. Staged changes were left intact for inspection.' }
}
finally {
    if (Test-Path -LiteralPath $messageFile) { Remove-Item -LiteralPath $messageFile -Force }
}

$committedMessage = ((& $gitCommand.Source -C $repositoryRoot log -1 --pretty=%B) -join "`n").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Commit was created, but its final message could not be verified.' }
& $validatorPath -Message $committedMessage | Out-Null
$commitSha = (& $gitCommand.Source -C $repositoryRoot rev-parse HEAD).Trim()
Write-Output "Created conventional commit $commitSha on branch '$branch'."
