[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
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
$stateScript = Join-Path $repositoryRoot '.ai\scripts\workflow-state.ps1'
$stateJson = ((& $stateScript -Action Validate -RunId $RunId) -join "`n")
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($stateJson)) {
    throw "Workflow run '$RunId' could not be validated before commit creation."
}
$state = $stateJson | ConvertFrom-Json
if ([string]$state.status -ne 'READY_FOR_DELIVERY') { throw "Commit creation requires READY_FOR_DELIVERY state, not '$($state.status)'." }
$parentSha = (& $gitCommand.Source -C $repositoryRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $parentSha -ne [string]$state.currentSha) {
    throw 'Current HEAD does not match the reviewed workflow run.'
}
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

$stagedFiles = @(& $gitCommand.Source -C $repositoryRoot diff --cached --name-only --no-renames --diff-filter=ACDMRTUXB)
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
$runtimeRoot = Join-Path $repositoryRoot ".ai\runtime\$RunId"
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
$evidencePath = Join-Path $runtimeRoot 'commit.json'
$temporaryPath = $evidencePath + '.tmp'
$schemaPath = Join-Path $repositoryRoot '.ai\commit-evidence.schema.json'
$evidence = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    sha = $commitSha.ToLowerInvariant()
    parentSha = $parentSha
    branch = $branch
    files = @($stagedFiles | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object -Unique)
    message = $committedMessage
    committedAtUtc = [DateTime]::UtcNow.ToString('o')
}
try {
    $evidenceJson = $evidence | ConvertTo-Json -Depth 5
    $schema = Get-Content -LiteralPath $schemaPath -Raw
    if (-not ($evidenceJson | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Generated commit evidence failed schema validation.' }
    Set-Content -LiteralPath $temporaryPath -Value $evidenceJson -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $evidencePath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

try {
    & $stateScript -Action RecordCommit -RunId $RunId -ArtifactPath $evidencePath | Out-Null
}
catch {
    throw "Commit $commitSha was created, but its workflow evidence could not be recorded: $($_.Exception.Message)"
}
Write-Output "Created and recorded conventional commit $commitSha on branch '$branch' for workflow run '$RunId'."
