[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
    [Parameter(Mandatory = $true)][ValidateSet('reviewer', 'quick-reviewer')][string]$ReviewerRole,
    [Parameter(Mandatory = $true)][string]$PayloadPath,
    [ValidateSet('typed-tool', 'deterministic-script')][string]$Transport = 'deterministic-script'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

function Get-RepositoryRoot {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) { throw 'Git is required to record review evidence.' }
    $root = (& $git.Source rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) { throw 'Review recording requires an initialized Git repository.' }
    return [IO.Path]::GetFullPath($root.Trim()).TrimEnd('\', '/')
}

function Resolve-ExactRuntimePath([string]$RepositoryRoot, [string]$RelativePath, [string]$FileName) {
    $candidate = if ([IO.Path]::IsPathRooted($RelativePath)) { $RelativePath } else { Join-Path $RepositoryRoot $RelativePath }
    $resolved = [IO.Path]::GetFullPath($candidate)
    $expected = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ".ai\runtime\$RunId\$FileName"))
    if (-not [string]::Equals($resolved, $expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Review payload must be staged at .ai/runtime/$RunId/$FileName."
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Review payload not found: $resolved" }
    return $resolved
}

$repositoryRoot = Get-RepositoryRoot
$resolvedPayloadPath = Resolve-ExactRuntimePath -RepositoryRoot $repositoryRoot -RelativePath $PayloadPath -FileName 'review-input.json'
$statePath = Join-Path $repositoryRoot ".ai\runs\$RunId\state.json"
$stateSchemaPath = Join-Path $repositoryRoot '.ai\workflow-run.schema.json'
$reviewSchemaPath = Join-Path $repositoryRoot '.ai\review-evidence.schema.json'
$stateScriptPath = Join-Path $repositoryRoot '.ai\scripts\workflow-state.ps1'
foreach ($requiredPath in @($statePath, $stateSchemaPath, $reviewSchemaPath, $stateScriptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required review input not found: $requiredPath" }
}

$stateJson = Get-Content -LiteralPath $statePath -Raw
$stateSchema = Get-Content -LiteralPath $stateSchemaPath -Raw
if (-not ($stateJson | Test-Json -Schema $stateSchema -ErrorAction Stop)) { throw "Run '$RunId' failed state schema validation." }
$state = $stateJson | ConvertFrom-Json -AsHashtable
if ([string]$state.status -ne 'GATES_PASSED') { throw "Run '$RunId' must be in GATES_PASSED before independent review can be recorded." }
$expectedRole = switch ([string]$state.workflowPath) {
    'standard' { 'reviewer' }
    'fast-path' { 'quick-reviewer' }
    default { throw 'Diagnostic runs do not accept implementation review evidence.' }
}
if ($ReviewerRole -ne $expectedRole) { throw "Run '$RunId' requires reviewer role '$expectedRole', not '$ReviewerRole'." }
if (-not $state.artifacts.Contains('gates') -or [string]$state.artifacts.gates.verdict -ne 'PASS') {
    throw "Run '$RunId' has no persisted passing gate evidence."
}

$payload = Get-Content -LiteralPath $resolvedPayloadPath -Raw | ConvertFrom-Json -AsHashtable
foreach ($requiredProperty in @('summary', 'findings', 'acceptanceCriteriaCoverage', 'residualRisks')) {
    if (-not $payload.Contains($requiredProperty)) { throw "Review payload is missing '$requiredProperty'." }
}
$escalationReason = if ($payload.Contains('escalationReason') -and -not [string]::IsNullOrWhiteSpace([string]$payload.escalationReason)) {
    ([string]$payload.escalationReason).Trim()
}
else { $null }

$severityCounts = [ordered]@{ BLOCKER = 0; HIGH = 0; MEDIUM = 0; LOW = 0; NIT = 0 }
foreach ($finding in @($payload.findings)) {
    $severity = [string]$finding.severity
    if (-not $severityCounts.Contains($severity)) { throw "Unsupported review severity: $severity" }
    $severityCounts[$severity] = [int]$severityCounts[$severity] + 1
}
$incompleteCoverage = @($payload.acceptanceCriteriaCoverage | Where-Object { [string]$_.status -ne 'COVERED' }).Count -gt 0
$verdict = if ($null -ne $escalationReason) {
    'ESCALATE'
}
elseif ([int]$severityCounts.BLOCKER -gt 0 -or [int]$severityCounts.HIGH -gt 0 -or $incompleteCoverage) {
    'FAIL'
}
else { 'PASS' }

$gatePath = Join-Path (Split-Path -Parent $statePath) ([string]$state.artifacts.gates.path)
if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) { throw "Canonical gate evidence not found: $gatePath" }
$gateHash = (Get-FileHash -LiteralPath $gatePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($gateHash -ne [string]$state.artifacts.gates.sha256) { throw 'Canonical gate evidence hash does not match persisted state.' }

$reviewEvidence = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    reviewerRole = $ReviewerRole
    workflowPath = [string]$state.workflowPath
    currentSha = [string]$state.currentSha
    worktreeFingerprint = [string]$state.worktreeFingerprint
    gateEvidenceSha256 = $gateHash
    reviewedAtUtc = [DateTime]::UtcNow.ToString('o')
    summary = [string]$payload.summary
    findings = @($payload.findings)
    severityCounts = $severityCounts
    acceptanceCriteriaCoverage = @($payload.acceptanceCriteriaCoverage)
    gateStatus = 'PASS'
    residualRisks = @($payload.residualRisks | ForEach-Object { [string]$_ })
    escalationReason = $escalationReason
    verdict = $verdict
}
$reviewJson = $reviewEvidence | ConvertTo-Json -Depth 10
$reviewSchema = Get-Content -LiteralPath $reviewSchemaPath -Raw
if (-not ($reviewJson | Test-Json -Schema $reviewSchema -ErrorAction Stop)) { throw 'Generated review evidence failed schema validation.' }

$runtimeDirectory = Join-Path $repositoryRoot ".ai\runtime\$RunId"
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$reviewPath = Join-Path $runtimeDirectory 'review.json'
$temporaryPath = $reviewPath + '.tmp'
try {
    Set-Content -LiteralPath $temporaryPath -Value $reviewJson -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $reviewPath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

if ($null -ne $escalationReason) {
    & $stateScriptPath -Transport $Transport -Action RecordReview -RunId $RunId -ArtifactPath ".ai/runtime/$RunId/review.json" -Verdict $verdict -Reason $escalationReason
}
else {
    & $stateScriptPath -Transport $Transport -Action RecordReview -RunId $RunId -ArtifactPath ".ai/runtime/$RunId/review.json" -Verdict $verdict
}
if ($LASTEXITCODE -ne 0) { throw 'Review evidence was generated but workflow state rejected it.' }
