[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
    [Parameter(Mandatory = $true)][string]$Solution,
    [Parameter(Mandatory = $true)][string]$Project
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
$dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to locate the repository.' }
if ($null -eq $dotnetCommand) { throw 'dotnet is required to update a solution.' }

$rootOutput = @(& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or $rootOutput.Count -ne 1) { throw 'The current location is not inside a Git repository.' }
$repositoryRoot = [IO.Path]::GetFullPath([string]$rootOutput[0]).TrimEnd('\', '/')

function Resolve-ApprovedPath([string]$Value, [string[]]$Extensions, [string]$Description) {
    if ([IO.Path]::IsPathRooted($Value)) { throw "$Description must be repository-relative." }
    $resolved = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $Value))
    if (-not $resolved.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes the repository: $Value"
    }
    if ($Extensions -notcontains [IO.Path]::GetExtension($resolved).ToLowerInvariant()) {
        throw "$Description has an unsupported extension: $Value"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Description not found: $Value" }
    return $resolved
}

$solutionPath = Resolve-ApprovedPath -Value $Solution -Extensions @('.sln', '.slnx') -Description 'Solution'
$projectPath = Resolve-ApprovedPath -Value $Project -Extensions @('.csproj', '.fsproj', '.vbproj') -Description 'Project'
$solutionRelative = ([IO.Path]::GetRelativePath($repositoryRoot, $solutionPath)).Replace('\', '/')
$projectRelative = ([IO.Path]::GetRelativePath($repositoryRoot, $projectPath)).Replace('\', '/')

$stateScript = Join-Path $repositoryRoot '.ai\scripts\workflow-state.ps1'
$stateJson = ((& $stateScript -Action Validate -RunId $RunId -Transport deterministic-script) -join "`n")
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($stateJson)) { throw "Workflow run '$RunId' could not be validated." }
$state = $stateJson | ConvertFrom-Json
if ([string]$state.status -ne 'IMPLEMENTING') { throw "Solution mutation requires IMPLEMENTING state, not '$($state.status)'." }
if (-not ($state.artifacts.PSObject.Properties.Name -contains 'verification')) { throw 'The run has no approved execution contract.' }

$contractPath = Join-Path $repositoryRoot ".ai\runs\$RunId\$([string]$state.artifacts.verification.path)"
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ([int]$contract.schemaVersion -ne 2) { throw 'Managed solution mutation requires a schema-version-2 execution contract.' }
$approvedChanges = @($contract.expectedChanges | ForEach-Object { ([string]$_.path).Replace('\', '/').ToLowerInvariant() })
if ($approvedChanges -notcontains $solutionRelative.ToLowerInvariant()) { throw "Solution is outside the approved expectedChanges: $solutionRelative" }
if ($approvedChanges -notcontains $projectRelative.ToLowerInvariant()) { throw "Project is outside the approved expectedChanges: $projectRelative" }

$listedProjects = @(& $dotnetCommand.Source sln $solutionPath list 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect solution '$solutionRelative'.`n$($listedProjects -join "`n")" }
$projectFileName = [IO.Path]::GetFileName($projectPath)
$alreadyPresent = @($listedProjects | Where-Object { ([string]$_).Trim().EndsWith($projectFileName, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
if (-not $alreadyPresent) {
    $addOutput = @(& $dotnetCommand.Source sln $solutionPath add $projectPath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to add '$projectRelative' to '$solutionRelative'.`n$($addOutput -join "`n")" }
}

[ordered]@{
    verdict = if ($alreadyPresent) { 'DOTNET_PROJECT_ALREADY_PRESENT' } else { 'DOTNET_PROJECT_ADDED' }
    runId = $RunId
    solution = $solutionRelative
    project = $projectRelative
    status = [string]$state.status
    transport = 'deterministic-script'
} | ConvertTo-Json -Depth 4
