[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
    [Parameter(Mandatory = $true)][string]$Name
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to create a branch.' }

$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The current location is not inside a Git repository.'
}
$repositoryRoot = $repositoryRoot.Trim()
$stateScript = Join-Path $repositoryRoot '.ai\scripts\workflow-state.ps1'
$stateJson = ((& $stateScript -Action Validate -RunId $RunId) -join "`n")
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($stateJson)) {
    throw "Workflow run '$RunId' could not be validated before branch creation."
}
$state = $stateJson | ConvertFrom-Json
if ([string]$state.status -ne 'PLAN_APPROVED') { throw "Branch creation requires PLAN_APPROVED state, not '$($state.status)'." }

$previousBranch = (& $gitCommand.Source -C $repositoryRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($previousBranch)) {
    throw 'Branch creation requires a named current branch.'
}
if (-not ($state.PSObject.Properties.Name -contains 'baseBranch') -or [string]$state.baseBranch -ne $previousBranch) {
    throw "Current branch '$previousBranch' does not match the workflow run base branch."
}
$startingSha = (& $gitCommand.Source -C $repositoryRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $startingSha -ne [string]$state.currentSha) {
    throw 'Current HEAD does not match the workflow run before branch creation.'
}

& $gitCommand.Source check-ref-format --branch $Name *> $null
if ($LASTEXITCODE -ne 0) { throw "Invalid branch name: $Name" }
if ($Name -match '^(main|master|develop|development|trunk|release)(/|$)') {
    throw "Refusing to create a protected or shared branch name: $Name"
}

$status = @(& $gitCommand.Source -C $repositoryRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the working tree.' }
if ($status.Count -gt 0) {
    throw 'Branch creation requires a clean working tree.'
}

& $gitCommand.Source -C $repositoryRoot show-ref --verify --quiet ("refs/heads/" + $Name)
if ($LASTEXITCODE -eq 0) { throw "Local branch already exists: $Name" }

& $gitCommand.Source -C $repositoryRoot switch -c $Name
if ($LASTEXITCODE -ne 0) { throw "Git failed to create branch: $Name" }

$head = (& $gitCommand.Source -C $repositoryRoot rev-parse HEAD).Trim()
$runtimeRoot = Join-Path $repositoryRoot ".ai\runtime\$RunId"
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
$evidencePath = Join-Path $runtimeRoot 'branch.json'
$temporaryPath = $evidencePath + '.tmp'
$schemaPath = Join-Path $repositoryRoot '.ai\branch-evidence.schema.json'
$evidence = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    previousBranch = $previousBranch
    branch = $Name
    sha = $head.ToLowerInvariant()
    result = 'BRANCH_CREATED'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
}
try {
    $evidenceJson = $evidence | ConvertTo-Json -Depth 5
    $schema = Get-Content -LiteralPath $schemaPath -Raw
    if (-not ($evidenceJson | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Generated branch evidence failed schema validation.' }
    Set-Content -LiteralPath $temporaryPath -Value $evidenceJson -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $evidencePath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

try {
    & $stateScript -Action RecordBranch -RunId $RunId -ArtifactPath $evidencePath | Out-Null
}
catch {
    throw "Branch '$Name' was created, but its workflow evidence could not be recorded: $($_.Exception.Message)"
}
Write-Output "Created and recorded branch '$Name' at $head for workflow run '$RunId'."
