[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$distributionRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ai-engineering-workflow-tests-' + [Guid]::NewGuid().ToString('N'))
$repositoryRoot = Join-Path $testRoot 'consumer'
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:passed++
}

function Invoke-PowerShell([string]$ScriptPath, [string[]]$Arguments, [int]$ExpectedExitCode = 0, [string]$WorkingDirectory = $distributionRoot) {
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $output = @(& pwsh -NoProfile -File $ScriptPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    if ($exitCode -ne $ExpectedExitCode) {
        throw "Expected exit $ExpectedExitCode from $ScriptPath but received $exitCode.`n$($output -join "`n")"
    }
    return @($output)
}

function Get-RunRuntimePath([string]$RunId, [string]$FileName) {
    $directory = Join-Path $repositoryRoot ".ai\runtime\$RunId"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    return Join-Path $directory $FileName
}

function Get-RunRuntimeRelativePath([string]$RunId, [string]$FileName) {
    return ".ai/runtime/$RunId/$FileName"
}

try {
    New-Item -ItemType Directory -Path $repositoryRoot -Force | Out-Null
    & git -C $repositoryRoot init -b main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize test repository.' }
    & git -C $repositoryRoot config user.email 'workflow-tests@example.invalid'
    & git -C $repositoryRoot config user.name 'Workflow Tests'

    $sourceRoot = Join-Path $repositoryRoot 'src\app'
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceRoot 'app.js') -Value 'export const value = "before";' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $sourceRoot 'package.json') -Value '{"name":"workflow-test-app","private":true}' -Encoding utf8
    & git -C $repositoryRoot add -- 'src/app/app.js' 'src/app/package.json'
    & git -C $repositoryRoot commit -m 'test: create fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to commit test fixture.' }
    & git -C $repositoryRoot switch -c 'test/workflow' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the test feature branch.' }

    Invoke-PowerShell -ScriptPath (Join-Path $distributionRoot 'scripts\validate.ps1') -Arguments @() | Out-Null
    Assert-True -Condition $true -Message 'Distribution validation runs.'

    Invoke-PowerShell -ScriptPath (Join-Path $distributionRoot 'scripts\install.ps1') -Arguments @('-TargetPath', $repositoryRoot, '-Mode', 'Local') | Out-Null
    Assert-True -Condition (@(& git -C $repositoryRoot status --porcelain).Count -eq 0) -Message 'Local installation remains invisible to Git.'
    $metadata = Get-Content -LiteralPath (Join-Path $repositoryRoot '.ai\workflow-installation.json') -Raw | ConvertFrom-Json
    Assert-True -Condition ($metadata.workflowVersion -eq '1.10.0') -Message 'Installed metadata records version 1.10.0.'

    $profileScript = Join-Path $repositoryRoot '.ai\scripts\profile-project.ps1'
    $profileOutput = Invoke-PowerShell -ScriptPath $profileScript -Arguments @('-OutputPath', '.ai/project-profile.json') -WorkingDirectory $repositoryRoot
    $profile = ($profileOutput -join "`n") | ConvertFrom-Json
    Assert-True -Condition ($profile.fileCount -eq 2 -and $profile.structureFingerprint -match '^[a-f0-9]{64}$' -and $profile.languages.id -contains 'javascript' -and $profile.moduleCandidates.path -contains 'src/app') -Message 'The deterministic profiler identifies application files, languages, module candidates, and a stable fingerprint.'
    Invoke-PowerShell -ScriptPath $profileScript -Arguments @('-OutputPath', 'src/app/forbidden-profile.json') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'forbidden-profile.json'))) -Message 'The profiler cannot use its approved output option to overwrite application paths.'

    $projectSkillRoot = Join-Path $repositoryRoot '.opencode\skills\project-app'
    New-Item -ItemType Directory -Path $projectSkillRoot -Force | Out-Null
    @'
---
name: project-app
description: Project-specific rules for the workflow test application
compatibility: opencode-v2
---

## Scope

Applies to `src/app`.

## Evidence

- `src/app/app.js` and `src/app/package.json` establish the application fixture.

## Rules

- Keep fixture behavior inside `src/app`.

## Quality and testing

- Run the configured PowerShell verification command.

## Unknowns

- No framework is established by repository evidence.
'@ | Set-Content -LiteralPath (Join-Path $projectSkillRoot 'SKILL.md') -Encoding utf8

    [ordered]@{
        version = 1
        repositoryFingerprint = [string]$profile.structureFingerprint
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        skills = @([ordered]@{
            id = 'project-app'
            moduleId = 'app'
            path = '.opencode/skills/project-app/SKILL.md'
            confidence = 'HIGH'
            reason = 'The application fixture has a repository-specific module boundary.'
            composedWith = @()
            evidence = @([ordered]@{ path = 'src/app/app.js'; claim = 'This tracked source file establishes the fixture module.' })
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\generated-skills.json') -Encoding utf8

    $project = [ordered]@{
        '$schema' = './project.schema.json'
        version = 1
        name = 'workflow-test-consumer'
        fastPath = [ordered]@{ enabled = $true; maximumFiles = 3; maximumLines = 120; maximumProductionFilesForDiagnosis = 2; maximumTestFilesForDiagnosis = 2; maximumCorrectionIterations = 1 }
        review = [ordered]@{ maxIterations = 2; diffBudget = [ordered]@{ filesMultiplier = 2; linesMultiplier = 3 } }
        diagnostics = [ordered]@{ maxHypothesisIterations = 2; requireReproduction = $false; commands = @() }
        profile = [ordered]@{ repositoryFingerprint = [string]$profile.structureFingerprint; analyzedAtUtc = [DateTime]::UtcNow.ToString('o'); source = '.ai/project-profile.json'; generatedSkillsManifest = '.ai/generated-skills.json' }
        modules = @([ordered]@{
            id = 'app'
            path = 'src/app'
            languages = @('text')
            frameworks = @()
            architectures = @()
            contextSkills = @('project-app')
            quality = [ordered]@{ restore = @(); build = @(); lint = @(); typecheck = @(); test = @('pwsh -NoProfile -Command "exit 0"'); e2e = @() }
        })
    }
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-project.ps1') -Arguments @() -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'A profiled project and generated module skill pass deterministic validation.'
    Assert-True -Condition (@(& git -C $repositoryRoot status --porcelain).Count -eq 0) -Message 'Local personalization artifacts remain invisible to Git.'

    $stateScript = Join-Path $repositoryRoot '.ai\scripts\workflow-state.ps1'
    $gateRunner = Join-Path $repositoryRoot '.ai\scripts\run-quality-gates.ps1'

    $passingGateRunId = 'gate-pass-app'
    Set-Content -LiteralPath (Get-RunRuntimePath $passingGateRunId 'requirement.md') -Value 'Verify the passing quality-gate fixture.' -Encoding utf8
    Set-Content -LiteralPath (Get-RunRuntimePath $passingGateRunId 'plan.md') -Value 'Run the configured app quality matrix.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $passingGateRunId, '-WorkflowPath', 'standard', '-TaskType', 'Test', '-ArtifactPath', (Get-RunRuntimeRelativePath $passingGateRunId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'ApprovePlan', '-RunId', $passingGateRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $passingGateRunId 'plan.md'), '-AffectedModules', 'app') -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginImplementation', '-RunId', $passingGateRunId) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $gateRunner -Arguments @('-RunId', $passingGateRunId) -WorkingDirectory $repositoryRoot | Out-Null
    $gateEvidence = Get-Content -LiteralPath (Get-RunRuntimePath $passingGateRunId 'gates.json') -Raw | ConvertFrom-Json
    Assert-True -Condition ($gateEvidence.runId -eq $passingGateRunId -and $gateEvidence.overall -eq 'PASS' -and $gateEvidence.modules[0].phases[4].commands[0].exitCode -eq 0 -and $gateEvidence.worktreeStable) -Message 'The deterministic gate runner derives PASS from the persisted run matrix and stable worktree fingerprints.'

    $project.modules[0].quality.test = @('pwsh -NoProfile -Command "exit 7"')
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8
    $failingGateRunId = 'gate-fail-app'
    Set-Content -LiteralPath (Get-RunRuntimePath $failingGateRunId 'requirement.md') -Value 'Verify the failing quality-gate fixture.' -Encoding utf8
    Set-Content -LiteralPath (Get-RunRuntimePath $failingGateRunId 'plan.md') -Value 'Run the configured failing app quality matrix.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $failingGateRunId, '-WorkflowPath', 'standard', '-TaskType', 'Test', '-ArtifactPath', (Get-RunRuntimeRelativePath $failingGateRunId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'ApprovePlan', '-RunId', $failingGateRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $failingGateRunId 'plan.md'), '-AffectedModules', 'app') -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginImplementation', '-RunId', $failingGateRunId) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $gateRunner -Arguments @('-RunId', $failingGateRunId) -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    $failedGateEvidence = Get-Content -LiteralPath (Get-RunRuntimePath $failingGateRunId 'gates.json') -Raw | ConvertFrom-Json
    Assert-True -Condition ($failedGateEvidence.overall -eq 'FAIL' -and $failedGateEvidence.modules[0].phases[4].commands[0].exitCode -eq 7) -Message 'The deterministic gate runner derives FAIL and preserves the real nonzero exit code.'
    $preservedPassingEvidence = Get-Content -LiteralPath (Get-RunRuntimePath $passingGateRunId 'gates.json') -Raw | ConvertFrom-Json
    Assert-True -Condition ($preservedPassingEvidence.runId -eq $passingGateRunId -and $preservedPassingEvidence.overall -eq 'PASS') -Message 'Concurrent run staging does not overwrite earlier gate evidence.'
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordGates', '-RunId', $passingGateRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $failingGateRunId 'gates.json'), '-Verdict', 'FAIL') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'State rejects evidence staged under another workflow run ID.'
    $project.modules[0].quality.test = @('pwsh -NoProfile -Command "exit 0"')
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8

    $project.modules[0].path = '.'
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-project.ps1') -Arguments @() -WorkingDirectory $repositoryRoot | Out-Null
    $rootGateRunId = 'gate-root-module'
    Set-Content -LiteralPath (Get-RunRuntimePath $rootGateRunId 'requirement.md') -Value 'Verify a root-level application module.' -Encoding utf8
    Set-Content -LiteralPath (Get-RunRuntimePath $rootGateRunId 'plan.md') -Value 'Run the root module quality matrix.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $rootGateRunId, '-WorkflowPath', 'standard', '-TaskType', 'Test', '-ArtifactPath', (Get-RunRuntimeRelativePath $rootGateRunId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'ApprovePlan', '-RunId', $rootGateRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $rootGateRunId 'plan.md'), '-AffectedModules', 'app') -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginImplementation', '-RunId', $rootGateRunId) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $gateRunner -Arguments @('-RunId', $rootGateRunId) -WorkingDirectory $repositoryRoot | Out-Null
    $rootGateEvidence = Get-Content -LiteralPath (Get-RunRuntimePath $rootGateRunId 'gates.json') -Raw | ConvertFrom-Json
    Assert-True -Condition ($rootGateEvidence.overall -eq 'PASS' -and $rootGateEvidence.modules[0].path -eq '.') -Message 'A schema-valid root module executes quality gates at the repository root.'
    $project.modules[0].path = 'src/app'
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8

    $auxiliaryModule = ($project.modules[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable)
    $auxiliaryModule.id = 'aux'
    $auxiliaryModule.contextSkills = @()
    $project.modules = @($project.modules[0], $auxiliaryModule)
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8
    $matrixGateRunId = 'gate-exact-matrix'
    Set-Content -LiteralPath (Get-RunRuntimePath $matrixGateRunId 'requirement.md') -Value 'Verify that all approved modules are required.' -Encoding utf8
    Set-Content -LiteralPath (Get-RunRuntimePath $matrixGateRunId 'plan.md') -Value 'Run app and aux quality matrices.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $matrixGateRunId, '-WorkflowPath', 'standard', '-TaskType', 'Test', '-ArtifactPath', (Get-RunRuntimeRelativePath $matrixGateRunId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'ApprovePlan', '-RunId', $matrixGateRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $matrixGateRunId 'plan.md'), '-AffectedModules', 'app,aux') -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginImplementation', '-RunId', $matrixGateRunId) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $gateRunner -Arguments @('-RunId', $matrixGateRunId) -WorkingDirectory $repositoryRoot | Out-Null
    $partialGateEvidence = Get-Content -LiteralPath (Get-RunRuntimePath $matrixGateRunId 'gates.json') -Raw | ConvertFrom-Json -AsHashtable
    $partialGateEvidence.modules = @($partialGateEvidence.modules[0])
    $partialGateEvidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Get-RunRuntimePath $matrixGateRunId 'gates.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordGates', '-RunId', $matrixGateRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $matrixGateRunId 'gates.json'), '-Verdict', 'PASS') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'Schema-valid evidence that omits one approved module is rejected.'
    $project.modules = @($project.modules[0])
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8

    $ordinarySource = Join-Path $sourceRoot 'ordinary.txt'
    Set-Content -LiteralPath $ordinarySource -Value 'ordinary source growth' -Encoding utf8
    $ordinaryProfileOutput = Invoke-PowerShell -ScriptPath $profileScript -Arguments @() -WorkingDirectory $repositoryRoot
    $ordinaryProfile = ($ordinaryProfileOutput -join "`n") | ConvertFrom-Json
    Remove-Item -LiteralPath $ordinarySource -Force
    Assert-True -Condition ($ordinaryProfile.structureFingerprint -eq $profile.structureFingerprint) -Message 'Ordinary source growth inside known structure does not force profile regeneration.'

    $domainRoot = Join-Path $sourceRoot 'domain'
    New-Item -ItemType Directory -Path $domainRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $domainRoot 'model.txt') -Value 'structural drift' -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-project.ps1') -Arguments @() -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Remove-Item -LiteralPath $domainRoot -Recurse -Force
    Assert-True -Condition $true -Message 'A new architecture marker invalidates the persisted profile and requires ai-refresh.'

    $invalidProjectPath = Join-Path $repositoryRoot '.ai\invalid-project.json'
    $invalid = ($project | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable)
    $invalid.modules[0].path = '../outside'
    $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidProjectPath -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-project.ps1') -Arguments @('-ProjectPath', '.ai/invalid-project.json') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Remove-Item -LiteralPath $invalidProjectPath -Force
    Assert-True -Condition $true -Message 'A module path escaping the repository is rejected.'

    $invalidDiagnosticProject = ($project | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable)
    $invalidDiagnosticProject.diagnostics.commands = @('kubectl apply -f production.yaml')
    $invalidDiagnosticProject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidProjectPath -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-project.ps1') -Arguments @('-ProjectPath', '.ai/invalid-project.json') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Remove-Item -LiteralPath $invalidProjectPath -Force
    Assert-True -Condition $true -Message 'Known delivery and infrastructure mutations are rejected from diagnostic commands.'

    $diagnosticRunId = 'diagnose-stale-value'
    $diagnosisPath = Get-RunRuntimePath $diagnosticRunId 'diagnosis.json'
    $diagnosisRelativePath = Get-RunRuntimeRelativePath $diagnosticRunId 'diagnosis.json'
    Set-Content -LiteralPath (Get-RunRuntimePath $diagnosticRunId 'requirement.md') -Value 'Production requests intermittently return a stale value; cause unknown.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $diagnosticRunId, '-WorkflowPath', 'diagnostic', '-TaskType', 'ProductionBug', '-ArtifactPath', (Get-RunRuntimeRelativePath $diagnosticRunId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    $diagnosticStarted = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Show', '-RunId', $diagnosticRunId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($diagnosticStarted.status -eq 'DIAGNOSING' -and $diagnosticStarted.maximumDiagnosticIterations -eq 2) -Message 'A diagnostic run starts read-only with the configured bounded iteration count.'

    @'
{
  "schemaVersion": 1,
  "runId": "diagnose-stale-value",
  "status": "BLOCKED",
  "summary": "The symptom is established but current evidence cannot distinguish cache and source-data hypotheses.",
  "impact": { "severity": "HIGH", "affectedUsers": "Some production users", "firstObservedUtc": null, "affectedVersions": [] },
  "evidence": [
    { "id": "E1", "type": "incident-report", "source": "sanitized user report", "observation": "Responses can contain a stale value.", "sanitized": true }
  ],
  "hypotheses": [
    { "id": "H1", "statement": "A cache entry may outlive its source value.", "status": "OPEN", "supportingEvidenceIds": ["E1"], "contradictingEvidenceIds": [], "falsificationTest": "Compare sanitized cache age and source update time for one affected request.", "result": null }
  ],
  "reproduction": { "status": "NOT_ATTEMPTED", "steps": [], "evidenceIds": [] },
  "rootCause": null,
  "regressionTest": null,
  "missingEvidence": ["A sanitized trace correlating one stale response with cache and source timestamps."],
  "mitigationOptions": [],
  "escalationReason": null,
  "safety": { "productionMutationPerformed": false, "secretsAccessed": false }
}
'@ | Set-Content -LiteralPath $diagnosisPath -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordDiagnosis', '-RunId', $diagnosticRunId, '-ArtifactPath', $diagnosisRelativePath, '-Verdict', 'FAIL') -WorkingDirectory $repositoryRoot | Out-Null
    $blockedDiagnosis = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Show', '-RunId', $diagnosticRunId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($blockedDiagnosis.status -eq 'DIAGNOSIS_BLOCKED' -and $blockedDiagnosis.diagnosticIterations -eq 1) -Message 'Insufficient evidence is persisted as DIAGNOSIS_BLOCKED without claiming a cause.'

    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginDiagnosticIteration', '-RunId', $diagnosticRunId) -WorkingDirectory $repositoryRoot | Out-Null
    $invalidConfirmed = Get-Content -LiteralPath $diagnosisPath -Raw | ConvertFrom-Json -AsHashtable
    $invalidConfirmed.status = 'ROOT_CAUSE_CONFIRMED'
    $invalidConfirmed.missingEvidence = @()
    $invalidConfirmed.hypotheses[0].status = 'CONFIRMED'
    $invalidConfirmed.regressionTest = 'Verify an updated value is returned.'
    $invalidConfirmed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $diagnosisPath -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordDiagnosis', '-RunId', $diagnosticRunId, '-ArtifactPath', $diagnosisRelativePath, '-Verdict', 'PASS') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'A plausible hypothesis cannot be recorded as confirmed without an evidence-backed root cause.'

    @'
{
  "schemaVersion": 1,
  "runId": "diagnose-stale-value",
  "status": "ROOT_CAUSE_CONFIRMED",
  "summary": "The cached value remains valid after the source value changes.",
  "impact": { "severity": "HIGH", "affectedUsers": "Some production users", "firstObservedUtc": null, "affectedVersions": ["fixture"] },
  "evidence": [
    { "id": "E1", "type": "incident-report", "source": "sanitized user report", "observation": "Responses can contain a stale value.", "sanitized": true },
    { "id": "E2", "type": "trace", "source": "sanitized correlated trace", "observation": "The response used a cache entry created before the source update.", "sanitized": true }
  ],
  "hypotheses": [
    { "id": "H1", "statement": "The cache entry outlives its source value.", "status": "CONFIRMED", "supportingEvidenceIds": ["E1", "E2"], "contradictingEvidenceIds": [], "falsificationTest": "Compare cache creation and source update time for an affected response.", "result": "E2 shows the stale cache entry was selected after the source update." }
  ],
  "reproduction": { "status": "NOT_REPRODUCED", "steps": [], "evidenceIds": [] },
  "rootCause": { "statement": "Cache invalidation does not occur after the source value changes.", "confidence": "HIGH", "evidenceIds": ["E1", "E2"] },
  "regressionTest": "Update the source value after priming the cache and verify the next response returns the updated value.",
  "missingEvidence": [],
  "mitigationOptions": ["Invalidate the affected cache key after a successful source update."],
  "escalationReason": null,
  "safety": { "productionMutationPerformed": false, "secretsAccessed": false }
}
'@ | Set-Content -LiteralPath $diagnosisPath -Encoding utf8
    $project.diagnostics.requireReproduction = $true
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-diagnosis.ps1') -Arguments @('-Path', $diagnosisRelativePath, '-ExpectedRunId', $diagnosticRunId) -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    $project.diagnostics.requireReproduction = $false
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8
    Assert-True -Condition $true -Message 'Project policy can require reproduction before root-cause confirmation.'
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordDiagnosis', '-RunId', $diagnosticRunId, '-ArtifactPath', $diagnosisRelativePath, '-Verdict', 'PASS') -WorkingDirectory $repositoryRoot | Out-Null
    $confirmedDiagnosis = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Validate', '-RunId', $diagnosticRunId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($confirmedDiagnosis.status -eq 'ROOT_CAUSE_CONFIRMED' -and $confirmedDiagnosis.diagnosticIterations -eq 2) -Message 'An evidence-backed root cause reaches ROOT_CAUSE_CONFIRMED within the iteration limit.'

    $handoffRunId = 'ticket-stale-cache-fix'
    Set-Content -LiteralPath (Get-RunRuntimePath $handoffRunId 'requirement.md') -Value 'Implement the confirmed stale-cache fix and regression test.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $handoffRunId, '-WorkflowPath', 'standard', '-TaskType', 'BugFix', '-SourceRunId', $diagnosticRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $handoffRunId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    $handoff = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Show', '-RunId', $handoffRunId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($handoff.status -eq 'PLANNING' -and $handoff.sourceRunId -eq $diagnosticRunId) -Message 'Only a confirmed diagnosis can seed a traceable standard implementation run.'

    $runId = 'quick-fixture-change'
    Set-Content -LiteralPath (Get-RunRuntimePath $runId 'requirement.md') -Value 'Change the fixture text.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $runId, '-WorkflowPath', 'fast-path', '-TaskType', 'QuickFix', '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    $approvedPlan = 'Change src/app/app.js, add src/app/new.txt, and verify both files.'
    Set-Content -LiteralPath (Get-RunRuntimePath $runId 'plan.md') -Value $approvedPlan -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'ApprovePlan', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'plan.md'), '-AffectedModules', 'app') -WorkingDirectory $repositoryRoot | Out-Null
    $managedBranch = 'test/workflow-evidence'
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\create-branch.ps1') -Arguments @('-RunId', $runId, '-Name', $managedBranch) -WorkingDirectory $repositoryRoot | Out-Null
    $branchState = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Validate', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($branchState.status -eq 'PLAN_APPROVED' -and $branchState.artifacts.branch.verdict -eq 'PASS' -and (& git -C $repositoryRoot branch --show-current).Trim() -eq $managedBranch) -Message 'Approved branch creation persists evidence and keeps the plan ready for implementation.'
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginImplementation', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceRoot 'app.js') -Value 'export const value = "after";' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $sourceRoot 'new.txt') -Value 'new file' -Encoding utf8

    $classifier = Join-Path $repositoryRoot '.ai\scripts\fast-path-check.ps1'
    $classification = Invoke-PowerShell -ScriptPath $classifier -Arguments @('-TaskType', 'QuickFix', '-Phase', 'Actual', '-BaseRef', 'HEAD', '-AcceptanceClear', '-RootCauseKnown', '-VerificationAvailable') -WorkingDirectory $repositoryRoot
    $classificationJson = ($classification -join "`n") | ConvertFrom-Json
    Assert-True -Condition ($classificationJson.verdict -eq 'FAST_PATH_ELIGIBLE' -and $classificationJson.observed.fileCount -eq 2 -and $classificationJson.observed.moduleCount -eq 1) -Message 'Actual fast-path scope is derived from tracked and untracked Git changes.'

    Set-Content -LiteralPath (Get-RunRuntimePath $runId 'gates.json') -Value '{"overall":"PASS"}' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordGates', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'gates.json'), '-Verdict', 'PASS') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'Workflow state rejects an agent-authored PASS artifact without deterministic command evidence.'

    Invoke-PowerShell -ScriptPath $gateRunner -Arguments @('-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-Null
    $installedDeveloperPath = Join-Path $repositoryRoot '.opencode\agents\developer.md'
    $installedDeveloperBytes = [IO.File]::ReadAllBytes($installedDeveloperPath)
    Add-Content -LiteralPath $installedDeveloperPath -Value "`nunauthorized control-plane mutation"
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordGates', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'gates.json'), '-Verdict', 'PASS') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    [IO.File]::WriteAllBytes($installedDeveloperPath, $installedDeveloperBytes)
    Assert-True -Condition $true -Message 'A control-plane mutation invalidates the run before gate evidence can advance state.'

    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordGates', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'gates.json'), '-Verdict', 'PASS') -WorkingDirectory $repositoryRoot | Out-Null

    $canonicalPlanPath = Join-Path $repositoryRoot ".ai\runs\$runId\plan.md"
    Set-Content -LiteralPath $canonicalPlanPath -Value 'unapproved replacement plan' -Encoding utf8
    $reviewPayloadPath = Get-RunRuntimePath $runId 'review-input.json'
    $reviewPayload = [ordered]@{
        summary = 'The bounded fixture change satisfies its acceptance criterion.'
        findings = @()
        acceptanceCriteriaCoverage = @([ordered]@{
            criterion = 'Update the fixture and add the requested file.'
            status = 'COVERED'
            evidence = 'src/app/app.js and src/app/new.txt contain the requested bounded change.'
        })
        residualRisks = @()
    }
    $reviewPayload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewPayloadPath -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\record-review.ps1') -Arguments @('-RunId', $runId, '-ReviewerRole', 'quick-reviewer', '-PayloadPath', (Get-RunRuntimeRelativePath $runId 'review-input.json')) -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'Every state transition rejects a modified canonical artifact.'
    Set-Content -LiteralPath $canonicalPlanPath -Value $approvedPlan -Encoding utf8

    $forgedReview = Get-Content -LiteralPath (Get-RunRuntimePath $runId 'review.json') -Raw | ConvertFrom-Json
    $forgedReview.gateEvidenceSha256 = ('0' * 64)
    $forgedReview | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Get-RunRuntimePath $runId 'review.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordReview', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'review.json'), '-Verdict', 'PASS') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'Forged review evidence cannot advance workflow state.'
    $reviewPayload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewPayloadPath -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\record-review.ps1') -Arguments @('-RunId', $runId, '-ReviewerRole', 'quick-reviewer', '-PayloadPath', (Get-RunRuntimeRelativePath $runId 'review-input.json')) -WorkingDirectory $repositoryRoot | Out-Null
    $ready = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Validate', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($ready.status -eq 'READY_FOR_DELIVERY' -and $ready.artifacts.review.path -eq 'review.json') -Message 'Reviewer-scoped structured evidence advances the approved run to READY_FOR_DELIVERY.'

    & git -C $repositoryRoot add -- 'src/app/app.js' 'src/app/new.txt'
    & git -C $repositoryRoot commit -m 'update fixture without conventional type' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create state-machine test commit.' }
    $commitSha = (& git -C $repositoryRoot rev-parse HEAD).Trim()
    $commitEvidence = [ordered]@{
        schemaVersion = 1
        runId = $runId
        sha = $commitSha
        parentSha = [string]$ready.currentSha
        branch = $managedBranch
        files = @('src/app/app.js', 'src/app/new.txt')
        message = 'update fixture without conventional type'
        committedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $commitEvidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-RunRuntimePath $runId 'commit.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordCommit', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'commit.json')) -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'State rejects the actual Git commit when its message is not Conventional Commits, even when evidence matches it.'
    & git -C $repositoryRoot commit --amend -m 'test: update fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to replace the adversarial test fixture with a valid commit.' }
    $commitSha = (& git -C $repositoryRoot rev-parse HEAD).Trim()
    $commitEvidence.sha = $commitSha
    $commitEvidence.message = 'fix: forged evidence message'
    $commitEvidence.committedAtUtc = [DateTime]::UtcNow.ToString('o')
    $commitEvidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-RunRuntimePath $runId 'commit.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordCommit', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'commit.json')) -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'Commit evidence cannot substitute a forged message for the actual Git commit message.'
    $commitEvidence.message = 'test: update fixture'
    $commitEvidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-RunRuntimePath $runId 'commit.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordCommit', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'commit.json')) -WorkingDirectory $repositoryRoot | Out-Null
    $committed = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Show', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($committed.status -eq 'COMMITTED' -and $committed.currentSha -eq $commitSha) -Message 'The exact reviewed diff, including a new file, can be recorded as committed.'

    $remoteRoot = Join-Path $testRoot 'origin.git'
    & git init --bare $remoteRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the test remote.' }
    & git -C $repositoryRoot remote add origin $remoteRoot
    & git -C $repositoryRoot push --set-upstream origin HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to publish the test feature branch.' }

    $publishPath = Get-RunRuntimePath $runId 'publish.json'
    [ordered]@{
        schemaVersion = 1
        runId = $runId
        remote = 'origin'
        branch = $managedBranch
        ref = "refs/heads/$managedBranch"
        sha = '0000000000000000000000000000000000000000'
        result = 'PUBLISHED'
        publishedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $publishPath -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordPublish', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'publish.json')) -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'Forged publish evidence cannot advance workflow state.'

    [ordered]@{
        schemaVersion = 1
        runId = $runId
        remote = 'origin'
        branch = $managedBranch
        ref = "refs/heads/$managedBranch"
        sha = $commitSha
        result = 'PUBLISHED'
        publishedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $publishPath -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordPublish', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'publish.json')) -WorkingDirectory $repositoryRoot | Out-Null
    $published = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Show', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($published.status -eq 'PUBLISHED') -Message 'Publish state advances only after the upstream remote ref is independently verified.'

    $mockBin = Join-Path $testRoot 'mock-bin'
    New-Item -ItemType Directory -Path $mockBin -Force | Out-Null
    @'
$args | Out-Null
Write-Output $env:AI_TEST_PR_JSON
exit 0
'@ | Set-Content -LiteralPath (Join-Path $mockBin 'gh.ps1') -Encoding utf8
    $previousPath = $env:PATH
    $previousPrJson = $env:AI_TEST_PR_JSON
    try {
        $env:PATH = $mockBin + [IO.Path]::PathSeparator + $previousPath
        $prUrl = 'https://example.invalid/pull/42'
        $prTitle = 'fix: update fixture'
        $env:AI_TEST_PR_JSON = ([ordered]@{
            number = 42
            url = $prUrl
            baseRefName = 'main'
            headRefName = $managedBranch
            headRefOid = $commitSha
            title = $prTitle
            isDraft = $true
            state = 'OPEN'
        } | ConvertTo-Json -Compress)
        $prEvidence = [ordered]@{
            schemaVersion = 1
            runId = $runId
            number = 42
            url = $prUrl
            base = 'main'
            head = $managedBranch
            headSha = $commitSha
            title = $prTitle
            draft = $true
            state = 'OPEN'
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        $prEvidence.title = 'fix: forged title'
        $prEvidence | ConvertTo-Json | Set-Content -LiteralPath (Get-RunRuntimePath $runId 'pull-request.json') -Encoding utf8
        Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordPullRequest', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'pull-request.json')) -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
        Assert-True -Condition $true -Message 'Forged pull-request metadata cannot advance workflow state.'
        $prEvidence.title = $prTitle
        $prEvidence | ConvertTo-Json | Set-Content -LiteralPath (Get-RunRuntimePath $runId 'pull-request.json') -Encoding utf8
        Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordPullRequest', '-RunId', $runId, '-ArtifactPath', (Get-RunRuntimeRelativePath $runId 'pull-request.json')) -WorkingDirectory $repositoryRoot | Out-Null
    }
    finally {
        $env:PATH = $previousPath
        $env:AI_TEST_PR_JSON = $previousPrJson
    }
    $draftPr = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Show', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($draftPr.status -eq 'DRAFT_PR_CREATED') -Message 'Draft PR state advances only after GitHub metadata is independently verified.'

    $guardedCommitRunId = 'guarded-commit-script'
    Set-Content -LiteralPath (Get-RunRuntimePath $guardedCommitRunId 'requirement.md') -Value 'Verify the guarded commit script end to end.' -Encoding utf8
    Set-Content -LiteralPath (Get-RunRuntimePath $guardedCommitRunId 'plan.md') -Value 'Update the fixture value and create one validated conventional commit.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $guardedCommitRunId, '-WorkflowPath', 'fast-path', '-TaskType', 'Test', '-ArtifactPath', (Get-RunRuntimeRelativePath $guardedCommitRunId 'requirement.md')) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'ApprovePlan', '-RunId', $guardedCommitRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $guardedCommitRunId 'plan.md'), '-AffectedModules', 'app') -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginImplementation', '-RunId', $guardedCommitRunId) -WorkingDirectory $repositoryRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceRoot 'app.js') -Value 'export const value = "guarded-commit";' -Encoding utf8
    Invoke-PowerShell -ScriptPath $gateRunner -Arguments @('-RunId', $guardedCommitRunId) -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordGates', '-RunId', $guardedCommitRunId, '-ArtifactPath', (Get-RunRuntimeRelativePath $guardedCommitRunId 'gates.json'), '-Verdict', 'PASS') -WorkingDirectory $repositoryRoot | Out-Null
    $guardedReviewPayload = [ordered]@{
        summary = 'The guarded commit fixture satisfies the approved one-file change.'
        findings = @()
        acceptanceCriteriaCoverage = @([ordered]@{
            criterion = 'Update the fixture value.'
            status = 'COVERED'
            evidence = 'src/app/app.js contains the approved guarded-commit value.'
        })
        residualRisks = @()
    }
    $guardedReviewPayload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Get-RunRuntimePath $guardedCommitRunId 'review-input.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\record-review.ps1') -Arguments @('-RunId', $guardedCommitRunId, '-ReviewerRole', 'quick-reviewer', '-PayloadPath', (Get-RunRuntimeRelativePath $guardedCommitRunId 'review-input.json')) -WorkingDirectory $repositoryRoot | Out-Null
    & git -C $repositoryRoot add -- 'src/app/app.js'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stage the guarded commit fixture.' }
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\commit-approved.ps1') -Arguments @('-RunId', $guardedCommitRunId, '-Subject', 'test: verify guarded commit script') -WorkingDirectory $repositoryRoot | Out-Null
    $guardedCommitState = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Validate', '-RunId', $guardedCommitRunId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    $guardedCommitEvidence = Get-Content -LiteralPath (Join-Path $repositoryRoot ".ai\runs\$guardedCommitRunId\commit.json") -Raw | ConvertFrom-Json
    Assert-True -Condition ($guardedCommitState.status -eq 'COMMITTED' -and $guardedCommitEvidence.message -eq 'test: verify guarded commit script' -and $guardedCommitEvidence.files -contains 'src/app/app.js') -Message 'The guarded commit script creates, validates, records, and canonicalizes the actual commit evidence.'

    Set-Content -LiteralPath (Join-Path $repositoryRoot 'package.json') -Value '{"name":"risk"}' -Encoding utf8
    Invoke-PowerShell -ScriptPath $classifier -Arguments @('-TaskType', 'SmallTask', '-Phase', 'Actual', '-BaseRef', 'HEAD', '-AcceptanceClear', '-VerificationAvailable') -ExpectedExitCode 3 -WorkingDirectory $repositoryRoot | Out-Null
    Remove-Item -LiteralPath (Join-Path $repositoryRoot 'package.json') -Force
    Assert-True -Condition $true -Message 'Dependency manifest changes escalate from the fast path.'

    $reviewer = Get-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\agents\reviewer.md') -Raw
    $quickReviewer = Get-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\agents\quick-reviewer.md') -Raw
    Assert-True -Condition ($reviewer -notmatch 'resource:\s*"git ' -and $quickReviewer -notmatch 'resource:\s*"git ') -Message 'Review agents expose no shell exceptions.'
    $developer = Get-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\agents\developer.md') -Raw
    $quickFix = Get-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\agents\quick-fix.md') -Raw
    Assert-True -Condition ($developer -match 'resource:\s*"\.ai/\*"\s+effect:\s*deny' -and $quickFix -match 'resource:\s*"\.ai/runtime/\*/gates\.json"\s+effect:\s*deny') -Message 'Implementation agents deny control-plane edits and direct gate-evidence writes.'
    $installedOpenCode = Get-Content -LiteralPath (Join-Path $repositoryRoot 'opencode.json') -Raw
    $workflowTools = Get-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\tools\workflow.ts') -Raw
    Assert-True -Condition ($installedOpenCode -notmatch 'run-quality-gates\.ps1 \*.*allow' -and $installedOpenCode -match '"action": "workflow_\*".*"effect": "deny"') -Message 'Managed scripts are not exposed through automatically allowed shell wildcards.'
    Assert-True -Condition ($workflowTools -match 'Bun\.spawn\(\["pwsh"' -and $workflowTools -match 'export const gate = tool' -and $workflowTools -match 'export const state = tool') -Message 'Typed workflow tools pass validated arguments without shell-string interpolation.'

    $benchmarkPath = Join-Path $testRoot 'benchmark.json'
    $benchmarkSummaryPath = Join-Path $testRoot 'benchmark-summary.md'
    [ordered]@{
        version = 1
        suiteName = 'isolated-test'
        scenarios = @([ordered]@{
            id = 'fixture-change'
            category = 'bugfix'
            description = 'Fixture benchmark'
            runs = @(
                [ordered]@{ workflowPath = 'standard'; modelProfile = 'test'; inputTokens = 800; outputTokens = 200; costUsd = 1; durationSeconds = 20; correctionCycles = 1; result = 'PASS'; escapedDefects = 0 },
                [ordered]@{ workflowPath = 'fast-path'; modelProfile = 'test'; inputTokens = 400; outputTokens = 100; costUsd = 0.5; durationSeconds = 10; correctionCycles = 0; result = 'PASS'; escapedDefects = 0 }
            )
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $benchmarkPath -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $distributionRoot 'scripts\summarize-evaluations.ps1') -Arguments @('-InputPath', $benchmarkPath, '-OutputPath', $benchmarkSummaryPath) | Out-Null
    Assert-True -Condition ((Get-Content -LiteralPath $benchmarkSummaryPath -Raw) -match '50% savings') -Message 'Benchmark tooling validates and compares recorded token usage.'

    $smokeSelfTestOutput = Invoke-PowerShell -ScriptPath (Join-Path $distributionRoot 'scripts\smoke-opencode.ps1') -Arguments @('-SelfTest')
    Assert-True -Condition (($smokeSelfTestOutput -join "`n") -match 'OpenCode smoke helper self-test passed: 4 assertions\.') -Message 'OpenCode smoke helper parsers are covered without starting the beta runtime.'

    Add-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\agents\developer.md') -Value "`nlocal customization"
    Invoke-PowerShell -ScriptPath (Join-Path $distributionRoot 'scripts\update.ps1') -Arguments @('-TargetPath', $repositoryRoot, '-DryRun') -ExpectedExitCode 1 | Out-Null
    Assert-True -Condition $true -Message 'Updater rejects a locally modified managed agent.'

    Write-Host "Workflow test suite passed: $passed assertions."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolved)).StartsWith('ai-engineering-workflow-tests-', [StringComparison]::Ordinal)) {
            throw "Unsafe test cleanup target: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

# The updater-conflict test intentionally executes a child process that exits
# with 1. Do not propagate that expected child exit code as the suite result.
exit 0
