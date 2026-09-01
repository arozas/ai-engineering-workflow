[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$SchemaPath = '.ai/diagnosis.schema.json',
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$ExpectedRunId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to validate a repository diagnosis.' }
$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'Diagnosis validation requires an initialized Git repository.'
}
$repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot.Trim()).TrimEnd('\', '/')

function Resolve-RepositoryFile([string]$CandidatePath, [string]$Description) {
    $candidate = if ([IO.Path]::IsPathRooted($CandidatePath)) { $CandidatePath } else { Join-Path $repositoryRoot $CandidatePath }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not $resolved.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description must be inside the repository: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Description not found: $resolved" }
    return $resolved
}

$resolvedPath = Resolve-RepositoryFile -CandidatePath $Path -Description 'Diagnosis artifact'
$resolvedSchema = Resolve-RepositoryFile -CandidatePath $SchemaPath -Description 'Diagnosis schema'
$diagnosisJson = Get-Content -LiteralPath $resolvedPath -Raw
$schemaJson = Get-Content -LiteralPath $resolvedSchema -Raw
if (-not ($diagnosisJson | Test-Json -Schema $schemaJson -ErrorAction Stop)) {
    throw 'Diagnosis does not validate against .ai/diagnosis.schema.json.'
}
$diagnosis = $diagnosisJson | ConvertFrom-Json
$errors = @()

if (-not [string]::IsNullOrWhiteSpace($ExpectedRunId) -and [string]$diagnosis.runId -ne $ExpectedRunId) {
    $errors += "Diagnosis run ID '$($diagnosis.runId)' does not match expected run '$ExpectedRunId'."
}

$evidenceIds = @{}
foreach ($item in @($diagnosis.evidence)) {
    $id = [string]$item.id
    if ($evidenceIds.ContainsKey($id)) { $errors += "Duplicate evidence ID: $id" }
    $evidenceIds[$id] = $true
}

$hypothesisIds = @{}
$confirmed = @()
foreach ($hypothesis in @($diagnosis.hypotheses)) {
    $id = [string]$hypothesis.id
    if ($hypothesisIds.ContainsKey($id)) { $errors += "Duplicate hypothesis ID: $id" }
    $hypothesisIds[$id] = $true
    if ([string]$hypothesis.status -eq 'CONFIRMED') { $confirmed += $hypothesis }
    foreach ($reference in @($hypothesis.supportingEvidenceIds) + @($hypothesis.contradictingEvidenceIds)) {
        if (-not $evidenceIds.ContainsKey([string]$reference)) {
            $errors += "Hypothesis '$id' references unknown evidence '$reference'."
        }
    }
}

foreach ($reference in @($diagnosis.reproduction.evidenceIds)) {
    if (-not $evidenceIds.ContainsKey([string]$reference)) { $errors += "Reproduction references unknown evidence '$reference'." }
}
if ($null -ne $diagnosis.rootCause) {
    foreach ($reference in @($diagnosis.rootCause.evidenceIds)) {
        if (-not $evidenceIds.ContainsKey([string]$reference)) { $errors += "Root cause references unknown evidence '$reference'." }
    }
}

switch ([string]$diagnosis.status) {
    'ROOT_CAUSE_CONFIRMED' {
        if ($confirmed.Count -ne 1) { $errors += 'A confirmed diagnosis requires exactly one CONFIRMED hypothesis.' }
        if ($null -eq $diagnosis.rootCause) { $errors += 'A confirmed diagnosis requires a rootCause.' }
        elseif (@($diagnosis.rootCause.evidenceIds).Count -eq 0) { $errors += 'A confirmed root cause requires supporting evidence.' }
        if ([string]::IsNullOrWhiteSpace([string]$diagnosis.regressionTest)) { $errors += 'A confirmed diagnosis requires a regression-test obligation.' }
        if (@($diagnosis.missingEvidence).Count -ne 0) { $errors += 'A confirmed diagnosis cannot retain missing evidence.' }
        if ($null -ne $diagnosis.escalationReason) { $errors += 'A confirmed diagnosis cannot contain an escalation reason.' }
        $projectPath = Join-Path $repositoryRoot '.ai\project.json'
        if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
            $project = Get-Content -LiteralPath $projectPath -Raw | ConvertFrom-Json
            if ($project.PSObject.Properties.Name -contains 'diagnostics' -and
                $project.diagnostics.PSObject.Properties.Name -contains 'requireReproduction' -and
                [bool]$project.diagnostics.requireReproduction -and
                @('REPRODUCED', 'PARTIAL') -notcontains [string]$diagnosis.reproduction.status) {
                $errors += 'Project policy requires a successful or partial reproduction before confirming root cause.'
            }
        }
    }
    'BLOCKED' {
        if ($confirmed.Count -ne 0) { $errors += 'A blocked diagnosis cannot contain a CONFIRMED hypothesis.' }
        if ($null -ne $diagnosis.rootCause) { $errors += 'A blocked diagnosis cannot claim a root cause.' }
        if (@($diagnosis.missingEvidence).Count -eq 0) { $errors += 'A blocked diagnosis must identify missing evidence.' }
        if ($null -ne $diagnosis.escalationReason) { $errors += 'A blocked diagnosis cannot contain an escalation reason.' }
    }
    'ESCALATED' {
        if ([string]::IsNullOrWhiteSpace([string]$diagnosis.escalationReason)) { $errors += 'An escalated diagnosis requires an escalation reason.' }
        if ($confirmed.Count -ne 0 -or $null -ne $diagnosis.rootCause) { $errors += 'An escalated diagnosis cannot claim a confirmed root cause.' }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Diagnosis validation failed with $($errors.Count) error(s)."
}

[ordered]@{
    verdict = 'DIAGNOSIS_VALID'
    runId = [string]$diagnosis.runId
    status = [string]$diagnosis.status
    evidenceCount = @($diagnosis.evidence).Count
    hypothesisCount = @($diagnosis.hypotheses).Count
} | ConvertTo-Json -Depth 4
exit 0
