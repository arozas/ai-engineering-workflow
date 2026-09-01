[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'ApprovePlan', 'BeginImplementation', 'RecordGates', 'RecordReview', 'BeginCorrection', 'RecordDiagnosis', 'BeginDiagnosticIteration', 'RecordCommit', 'RecordPublish', 'RecordPullRequest', 'Escalate', 'Show', 'Validate')]
    [string]$Action,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
    [ValidateSet('standard', 'fast-path', 'diagnostic')][string]$WorkflowPath,
    [ValidateLength(1, 80)][string]$TaskType,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$SourceRunId,
    [string]$ArtifactPath,
    [ValidateSet('PASS', 'FAIL', 'ESCALATE')][string]$Verdict,
    [ValidateLength(1, 2000)][string]$Reason
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RepositoryRoot {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) { throw 'Git is required for persisted workflow state.' }
    $root = (& $git.Source rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        throw 'Persisted workflow state requires an initialized Git repository.'
    }
    return [System.IO.Path]::GetFullPath($root.Trim()).TrimEnd('\', '/')
}

function Get-CurrentSha([string]$RepositoryRoot) {
    $sha = (& git -C $RepositoryRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sha)) { return 'UNBORN' }
    return $sha.Trim().ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-InRepositoryFile([string]$RepositoryRoot, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'ArtifactPath is required for this action.' }
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepositoryRoot $Path }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not $resolved.StartsWith($RepositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact must be inside the repository: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Artifact not found: $resolved" }
    return $resolved
}

function Get-WorktreeFingerprint([string]$RepositoryRoot, [string]$CurrentSha) {
    $temporaryIndex = Join-Path ([IO.Path]::GetTempPath()) ('ai-engineering-workflow-index-' + [Guid]::NewGuid().ToString('N'))
    $previousIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process')
    $emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
    try {
        [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $temporaryIndex, 'Process')
        if ($CurrentSha -eq 'UNBORN') {
            & git -C $RepositoryRoot read-tree --empty
        }
        else {
            & git -C $RepositoryRoot read-tree $CurrentSha
        }
        if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the temporary Git index.' }

        & git -C $RepositoryRoot add -A -- .
        if ($LASTEXITCODE -ne 0) { throw 'Unable to construct the canonical worktree snapshot.' }

        $baseline = if ($CurrentSha -eq 'UNBORN') { $emptyTree } else { $CurrentSha }
        $diff = @(& git -C $RepositoryRoot diff --cached --binary --no-ext-diff $baseline --)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to calculate the canonical worktree diff.' }
        return Get-StringSha256 -Value ((@("HEAD=$CurrentSha", 'DIFF', ($diff -join "`n"))) -join "`n")
    }
    finally {
        [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $previousIndex, 'Process')
        if (Test-Path -LiteralPath $temporaryIndex) { Remove-Item -LiteralPath $temporaryIndex -Force }
        $lockPath = $temporaryIndex + '.lock'
        if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force }
    }
}

function Get-CommitFingerprint([string]$RepositoryRoot, [string]$ParentSha, [string]$CommitSha) {
    $baseline = if ($ParentSha -eq 'UNBORN') { '4b825dc642cb6eb9a060e54bf8d69288fbee4904' } else { $ParentSha }
    $diff = @(& git -C $RepositoryRoot diff --binary --no-ext-diff $baseline $CommitSha --)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to calculate committed diff fingerprint.' }
    return Get-StringSha256 -Value ((@("HEAD=$ParentSha", 'DIFF', ($diff -join "`n"))) -join "`n")
}

function Read-State([string]$StatePath) {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { throw "Workflow run does not exist: $RunId" }
    return Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json -AsHashtable
}

function Write-State([System.Collections.IDictionary]$State, [string]$StatePath, [string]$SchemaPath) {
    $State.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $json = $State | ConvertTo-Json -Depth 8
    $schema = Get-Content -LiteralPath $SchemaPath -Raw
    if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Generated workflow state failed schema validation.' }
    $temporary = $StatePath + '.tmp'
    try {
        Set-Content -LiteralPath $temporary -Value $json -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination $StatePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Add-Artifact([System.Collections.IDictionary]$State, [string]$Name, [string]$SourcePath, [string]$RunRoot, [string]$ArtifactVerdict) {
    $extension = [IO.Path]::GetExtension($SourcePath)
    if ([string]::IsNullOrWhiteSpace($extension)) { $extension = '.md' }
    $fileName = $Name + $extension.ToLowerInvariant()
    $destination = Join-Path $RunRoot $fileName
    Copy-Item -LiteralPath $SourcePath -Destination $destination -Force
    $record = [ordered]@{ path = $fileName; sha256 = Get-FileSha256 -Path $destination }
    if (-not [string]::IsNullOrWhiteSpace($ArtifactVerdict)) { $record.verdict = $ArtifactVerdict }
    $State.artifacts[$Name] = $record
}

function Assert-Status([System.Collections.IDictionary]$State, [string[]]$Allowed) {
    if ($Allowed -notcontains [string]$State.status) {
        throw "Action '$Action' is not valid from state '$($State.status)'. Expected: $($Allowed -join ', ')."
    }
}

function Assert-Head([System.Collections.IDictionary]$State, [string]$RepositoryRoot) {
    $current = Get-CurrentSha -RepositoryRoot $RepositoryRoot
    if ($current -ne [string]$State.currentSha) {
        throw "Repository HEAD changed from $($State.currentSha) to $current. Start or reconcile the run before continuing."
    }
}

function Test-State([System.Collections.IDictionary]$State, [string]$RunRoot, [string]$SchemaPath) {
    $json = $State | ConvertTo-Json -Depth 8
    $schema = Get-Content -LiteralPath $SchemaPath -Raw
    if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Workflow state does not validate against its schema.' }
    foreach ($name in $State.artifacts.Keys) {
        $record = $State.artifacts[$name]
        $path = Join-Path $RunRoot ([string]$record.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing run artifact: $name" }
        if ((Get-FileSha256 -Path $path) -ne [string]$record.sha256) { throw "Run artifact hash mismatch: $name" }
    }
}

$repositoryRoot = Get-RepositoryRoot
$schemaPath = Join-Path $repositoryRoot '.ai\workflow-run.schema.json'
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Workflow run schema not found: $schemaPath" }
$runsRoot = Join-Path $repositoryRoot '.ai\runs'
$runRoot = Join-Path $runsRoot $RunId
$statePath = Join-Path $runRoot 'state.json'

if ($Action -eq 'Start') {
    if ([string]::IsNullOrWhiteSpace($WorkflowPath) -or [string]::IsNullOrWhiteSpace($TaskType)) {
        throw 'Start requires WorkflowPath and TaskType.'
    }
    if (Test-Path -LiteralPath $runRoot) { throw "Workflow run already exists: $RunId" }
    $requirementSource = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
    if (-not [string]::IsNullOrWhiteSpace($SourceRunId)) {
        if ($WorkflowPath -ne 'standard') { throw 'SourceRunId is supported only when starting a standard implementation run.' }
        $sourceRunRoot = Join-Path $runsRoot $SourceRunId
        $sourceStatePath = Join-Path $sourceRunRoot 'state.json'
        $sourceState = Read-State -StatePath $sourceStatePath
        Test-State -State $sourceState -RunRoot $sourceRunRoot -SchemaPath $schemaPath
        if ([string]$sourceState.workflowPath -ne 'diagnostic' -or [string]$sourceState.status -ne 'ROOT_CAUSE_CONFIRMED') {
            throw "Source run '$SourceRunId' is not a confirmed diagnostic run."
        }
        $sourceDiagnosisPath = Join-Path $sourceRunRoot ([string]$sourceState.artifacts.diagnosis.path)
        $diagnosisValidator = Join-Path $repositoryRoot '.ai\scripts\validate-diagnosis.ps1'
        & $diagnosisValidator -Path $sourceDiagnosisPath -ExpectedRunId $SourceRunId | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Source diagnosis '$SourceRunId' failed validation." }
    }
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $now = [DateTime]::UtcNow.ToString('o')
    $sha = Get-CurrentSha -RepositoryRoot $repositoryRoot
    $maximumCorrections = 1
    $maximumDiagnosticIterations = 3
    $projectPath = Join-Path $repositoryRoot '.ai\project.json'
    if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
        $project = Get-Content -LiteralPath $projectPath -Raw | ConvertFrom-Json
        if ($project.PSObject.Properties.Name -contains 'diagnostics' -and
            $project.diagnostics.PSObject.Properties.Name -contains 'maxHypothesisIterations') {
            $maximumDiagnosticIterations = [Math]::Min(3, [Math]::Max(1, [int]$project.diagnostics.maxHypothesisIterations))
        }
    }
    if ($WorkflowPath -eq 'standard') {
        $maximumCorrections = 3
        if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
            if ($project.PSObject.Properties.Name -contains 'review' -and
                $project.review.PSObject.Properties.Name -contains 'maxIterations') {
                $maximumCorrections = [Math]::Min(3, [Math]::Max(1, [int]$project.review.maxIterations))
            }
        }
    }
    $state = [ordered]@{
        schemaVersion = 1
        runId = $RunId
        workflowPath = $WorkflowPath
        taskType = $TaskType
        status = if ($WorkflowPath -eq 'diagnostic') { 'DIAGNOSING' } else { 'PLANNING' }
        sourceRunId = if ([string]::IsNullOrWhiteSpace($SourceRunId)) { $null } else { $SourceRunId }
        baseSha = $sha
        currentSha = $sha
        worktreeFingerprint = $null
        correctionIterations = 0
        maximumCorrectionIterations = $maximumCorrections
        diagnosticIterations = 0
        maximumDiagnosticIterations = $maximumDiagnosticIterations
        createdAtUtc = $now
        updatedAtUtc = $now
        escalationReason = $null
        artifacts = [ordered]@{}
    }
    Add-Artifact -State $state -Name 'requirement' -SourcePath $requirementSource -RunRoot $runRoot -ArtifactVerdict ''
    Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
}
else {
    $state = Read-State -StatePath $statePath
    Test-State -State $state -RunRoot $runRoot -SchemaPath $schemaPath
    switch ($Action) {
        'ApprovePlan' {
            Assert-Status -State $state -Allowed @('PLANNING')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            $source = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
            Add-Artifact -State $state -Name 'plan' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict 'PASS'
            $state.status = 'PLAN_APPROVED'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'BeginImplementation' {
            Assert-Status -State $state -Allowed @('PLAN_APPROVED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            $state.status = 'IMPLEMENTING'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordGates' {
            Assert-Status -State $state -Allowed @('IMPLEMENTING')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            if (@('PASS', 'FAIL') -notcontains $Verdict) { throw 'RecordGates requires Verdict PASS or FAIL.' }
            $source = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
            Add-Artifact -State $state -Name 'gates' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict $Verdict
            $state.worktreeFingerprint = Get-WorktreeFingerprint -RepositoryRoot $repositoryRoot -CurrentSha ([string]$state.currentSha)
            $state.status = if ($Verdict -eq 'PASS') { 'GATES_PASSED' } else { 'GATE_FAILED' }
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordReview' {
            Assert-Status -State $state -Allowed @('GATES_PASSED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            if ([string]::IsNullOrWhiteSpace($Verdict)) { throw 'RecordReview requires a verdict.' }
            $currentFingerprint = Get-WorktreeFingerprint -RepositoryRoot $repositoryRoot -CurrentSha ([string]$state.currentSha)
            if ($currentFingerprint -ne [string]$state.worktreeFingerprint) { throw 'Worktree changed after gates; rerun the complete gate before review.' }
            $source = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
            Add-Artifact -State $state -Name 'review' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict $Verdict
            $state.status = switch ($Verdict) {
                'PASS' { 'READY_FOR_DELIVERY' }
                'FAIL' { 'REVIEW_FAILED' }
                'ESCALATE' { 'ESCALATED' }
            }
            if ($Verdict -eq 'ESCALATE') { $state.escalationReason = if ($Reason) { $Reason } else { 'Independent review required escalation.' } }
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'BeginCorrection' {
            Assert-Status -State $state -Allowed @('GATE_FAILED', 'REVIEW_FAILED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            $next = [int]$state.correctionIterations + 1
            if ($next -gt [int]$state.maximumCorrectionIterations) { throw 'Correction limit reached; escalate instead of continuing.' }
            $state.correctionIterations = $next
            $state.status = 'IMPLEMENTING'
            $state.worktreeFingerprint = $null
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordDiagnosis' {
            Assert-Status -State $state -Allowed @('DIAGNOSING')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            if (@('PASS', 'FAIL', 'ESCALATE') -notcontains $Verdict) { throw 'RecordDiagnosis requires Verdict PASS, FAIL, or ESCALATE.' }
            $next = [int]$state.diagnosticIterations + 1
            if ($next -gt [int]$state.maximumDiagnosticIterations) { throw 'Diagnostic iteration limit reached; escalate instead of continuing.' }
            $source = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
            $diagnosisValidator = Join-Path $repositoryRoot '.ai\scripts\validate-diagnosis.ps1'
            $validationOutput = @(& $diagnosisValidator -Path $source -ExpectedRunId $RunId)
            if ($LASTEXITCODE -ne 0) { throw 'Diagnosis artifact failed deterministic validation.' }
            $diagnosis = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
            $expectedDiagnosisStatus = switch ($Verdict) {
                'PASS' { 'ROOT_CAUSE_CONFIRMED' }
                'FAIL' { 'BLOCKED' }
                'ESCALATE' { 'ESCALATED' }
            }
            if ([string]$diagnosis.status -ne $expectedDiagnosisStatus) {
                throw "Diagnosis status '$($diagnosis.status)' does not match verdict '$Verdict'."
            }
            Add-Artifact -State $state -Name 'diagnosis' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict $Verdict
            $state.diagnosticIterations = $next
            $state.status = switch ($Verdict) {
                'PASS' { 'ROOT_CAUSE_CONFIRMED' }
                'FAIL' { 'DIAGNOSIS_BLOCKED' }
                'ESCALATE' { 'ESCALATED' }
            }
            if ($Verdict -eq 'ESCALATE') { $state.escalationReason = [string]$diagnosis.escalationReason }
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'BeginDiagnosticIteration' {
            Assert-Status -State $state -Allowed @('DIAGNOSIS_BLOCKED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            if ([int]$state.diagnosticIterations -ge [int]$state.maximumDiagnosticIterations) {
                throw 'Diagnostic iteration limit reached; escalate instead of continuing.'
            }
            $state.status = 'DIAGNOSING'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordCommit' {
            Assert-Status -State $state -Allowed @('READY_FOR_DELIVERY')
            $newSha = Get-CurrentSha -RepositoryRoot $repositoryRoot
            if ($newSha -eq [string]$state.currentSha -or $newSha -eq 'UNBORN') { throw 'RecordCommit requires one new commit.' }
            $parents = @(& git -C $repositoryRoot show -s --format=%P $newSha)
            $parentShas = @($parents | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $validParent = if ([string]$state.currentSha -eq 'UNBORN') {
                $parentShas.Count -eq 0
            }
            else {
                $parentShas.Count -eq 1 -and $parentShas[0] -eq [string]$state.currentSha
            }
            if ($LASTEXITCODE -ne 0 -or -not $validParent) {
                throw 'New commit must be the single next commit after the recorded run SHA.'
            }
            $status = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all)
            if ($LASTEXITCODE -ne 0 -or $status.Count -gt 0) { throw 'RecordCommit requires a clean working tree.' }
            $committedFingerprint = Get-CommitFingerprint -RepositoryRoot $repositoryRoot -ParentSha ([string]$state.currentSha) -CommitSha $newSha
            if ($committedFingerprint -ne [string]$state.worktreeFingerprint) { throw 'Committed diff does not match the gate-reviewed worktree fingerprint.' }
            $source = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
            Add-Artifact -State $state -Name 'commit' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict 'PASS'
            $state.currentSha = $newSha
            $state.status = 'COMMITTED'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordPublish' {
            Assert-Status -State $state -Allowed @('COMMITTED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            $source = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
            Add-Artifact -State $state -Name 'publish' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict 'PASS'
            $state.status = 'PUBLISHED'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordPullRequest' {
            Assert-Status -State $state -Allowed @('PUBLISHED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            $source = Resolve-InRepositoryFile -RepositoryRoot $repositoryRoot -Path $ArtifactPath
            Add-Artifact -State $state -Name 'pull-request' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict 'PASS'
            $state.status = 'DRAFT_PR_CREATED'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'Escalate' {
            if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Escalate requires Reason.' }
            $state.status = 'ESCALATED'
            $state.escalationReason = $Reason
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'Validate' { Test-State -State $state -RunRoot $runRoot -SchemaPath $schemaPath }
        'Show' { }
    }
}

$finalState = Read-State -StatePath $statePath
if ($Action -in @('Validate', 'Show')) { Test-State -State $finalState -RunRoot $runRoot -SchemaPath $schemaPath }
$finalState | ConvertTo-Json -Depth 8
