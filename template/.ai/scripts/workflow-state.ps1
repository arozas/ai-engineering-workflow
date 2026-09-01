[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'ApprovePlan', 'BeginImplementation', 'RecordGates', 'RecordReview', 'BeginCorrection', 'RecordCommit', 'RecordPublish', 'RecordPullRequest', 'Escalate', 'Show', 'Validate')]
    [string]$Action,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
    [ValidateSet('standard', 'fast-path')][string]$WorkflowPath,
    [ValidateLength(1, 80)][string]$TaskType,
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
    $parts = @("HEAD=$CurrentSha")
    if ($CurrentSha -ne 'UNBORN') {
        $diff = @(& git -C $RepositoryRoot diff --binary HEAD --)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to calculate the tracked worktree diff.' }
        $parts += 'DIFF'
        $parts += ($diff -join "`n")
    }
    $untracked = @(& git -C $RepositoryRoot ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect untracked files.' }
    foreach ($relative in @($untracked | Sort-Object)) {
        $full = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $relative))
        if (-not $full.StartsWith($RepositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Untracked path escapes repository: $relative"
        }
        $parts += "UNTRACKED=${relative}:$(Get-FileSha256 -Path $full)"
    }
    return Get-StringSha256 -Value ($parts -join "`n")
}

function Get-CommitFingerprint([string]$RepositoryRoot, [string]$ParentSha, [string]$CommitSha) {
    $diff = @(& git -C $RepositoryRoot diff --binary $ParentSha $CommitSha --)
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
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $now = [DateTime]::UtcNow.ToString('o')
    $sha = Get-CurrentSha -RepositoryRoot $repositoryRoot
    $maximumCorrections = 1
    if ($WorkflowPath -eq 'standard') {
        $maximumCorrections = 3
        $projectPath = Join-Path $repositoryRoot '.ai\project.json'
        if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
            $project = Get-Content -LiteralPath $projectPath -Raw | ConvertFrom-Json
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
        status = 'PLANNING'
        baseSha = $sha
        currentSha = $sha
        worktreeFingerprint = $null
        correctionIterations = 0
        maximumCorrectionIterations = $maximumCorrections
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
        'RecordCommit' {
            Assert-Status -State $state -Allowed @('READY_FOR_DELIVERY')
            $newSha = Get-CurrentSha -RepositoryRoot $repositoryRoot
            if ($newSha -eq [string]$state.currentSha -or $newSha -eq 'UNBORN') { throw 'RecordCommit requires one new commit.' }
            $parents = @(& git -C $repositoryRoot show -s --format=%P $newSha)
            if ($LASTEXITCODE -ne 0 -or $parents.Count -ne 1 -or $parents[0].Trim() -ne [string]$state.currentSha) {
                throw 'New commit must have the recorded run SHA as its single parent.'
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
