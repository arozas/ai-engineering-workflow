[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('QuickFix', 'SmallTask')][string]$TaskType,
    [Parameter(Mandatory = $true)][ValidateSet('Estimate', 'Actual')][string]$Phase,
    [Parameter(Mandatory = $true)][ValidateRange(0, 100)][int]$ModuleCount,
    [Parameter(Mandatory = $true)][ValidateRange(1, 10000)][int]$FileCount,
    [Parameter(Mandatory = $true)][ValidateRange(1, 1000000)][int]$LineCount,
    [ValidateRange(1, 3)][int]$MaximumFiles = 3,
    [ValidateRange(1, 120)][int]$MaximumLines = 120,
    [switch]$AcceptanceClear,
    [switch]$RootCauseKnown,
    [switch]$VerificationAvailable,
    [switch]$PublicContract,
    [switch]$NewDependency,
    [switch]$Migration,
    [switch]$SecuritySensitive,
    [switch]$Infrastructure,
    [switch]$DataIntegrity,
    [switch]$Concurrency,
    [switch]$CrossModule,
    [switch]$GeneratedCode
)

$ErrorActionPreference = 'Stop'
$blockers = @()

if (-not $AcceptanceClear) {
    $blockers += 'Acceptance criteria are not clear and observable.'
}
if (-not $VerificationAvailable) {
    $blockers += 'No deterministic verification or regression test is available.'
}
if ($TaskType -eq 'QuickFix') {
    if ($ModuleCount -ne 1) {
        $blockers += 'A quick fix must affect exactly one configured module.'
    }
    if (-not $RootCauseKnown) {
        $blockers += 'The root cause is not established by bounded evidence.'
    }
}
elseif ($ModuleCount -gt 1) {
    $blockers += 'A small task may affect at most one configured module.'
}
if ($FileCount -gt $MaximumFiles) {
    $blockers += "File count $FileCount exceeds the fast-path maximum of $MaximumFiles."
}
if ($LineCount -gt $MaximumLines) {
    $blockers += "Line count $LineCount exceeds the fast-path maximum of $MaximumLines."
}

$riskFlags = [ordered]@{
    publicContract = [bool]$PublicContract
    newDependency = [bool]$NewDependency
    migration = [bool]$Migration
    securitySensitive = [bool]$SecuritySensitive
    infrastructure = [bool]$Infrastructure
    dataIntegrity = [bool]$DataIntegrity
    concurrency = [bool]$Concurrency
    crossModule = [bool]$CrossModule
    generatedCode = [bool]$GeneratedCode
}
$riskMessages = @{
    publicContract = 'Public API or external contract changes require the standard workflow.'
    newDependency = 'New or replaced dependencies require the standard workflow.'
    migration = 'Database or data migrations require the standard workflow.'
    securitySensitive = 'Authentication, authorization, secrets, or other security-sensitive changes require the critical workflow.'
    infrastructure = 'CI/CD, infrastructure, deployment, or cloud changes require the critical workflow.'
    dataIntegrity = 'Data-integrity-sensitive changes require the standard or critical workflow.'
    concurrency = 'Concurrency-sensitive changes require the standard or critical workflow.'
    crossModule = 'Cross-module behavior requires the standard workflow.'
    generatedCode = 'Generated-code or generator changes require the standard workflow.'
}
foreach ($riskName in $riskFlags.Keys) {
    if ($riskFlags[$riskName]) {
        $blockers += $riskMessages[$riskName]
    }
}

$eligible = $blockers.Count -eq 0
$result = [ordered]@{
    taskType = $TaskType
    phase = $Phase
    verdict = if ($eligible) { 'FAST_PATH_ELIGIBLE' } else { 'ESCALATE_STANDARD' }
    eligible = $eligible
    thresholds = [ordered]@{
        maximumModules = 1
        maximumFiles = $MaximumFiles
        maximumLines = $MaximumLines
        maximumCorrectionIterations = 1
    }
    observed = [ordered]@{
        moduleCount = $ModuleCount
        fileCount = $FileCount
        lineCount = $LineCount
        acceptanceClear = [bool]$AcceptanceClear
        rootCauseKnown = [bool]$RootCauseKnown
        verificationAvailable = [bool]$VerificationAvailable
        riskFlags = $riskFlags
    }
    blockers = @($blockers)
}

$result | ConvertTo-Json -Depth 6
if (-not $eligible) {
    exit 3
}
exit 0
