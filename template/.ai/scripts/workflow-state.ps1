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
    [ValidateLength(1, 1000)][string]$AffectedModules,
    [ValidateSet('PASS', 'FAIL', 'ESCALATE')][string]$Verdict,
    [ValidateLength(1, 2000)][string]$Reason
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$qualityPhaseOrder = @('restore', 'build', 'lint', 'typecheck', 'test', 'e2e')

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

function Resolve-RunRuntimeArtifact(
    [string]$RepositoryRoot,
    [string]$RunId,
    [string]$Path,
    [string]$FileName
) {
    $resolved = Resolve-InRepositoryFile -RepositoryRoot $RepositoryRoot -Path $Path
    $expected = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ".ai\runtime\$RunId\$FileName"))
    if (-not [string]::Equals($resolved, $expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "This action accepts '$FileName' only from .ai/runtime/$RunId/$FileName."
    }
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

function Get-ControlPlaneFingerprint([string]$RepositoryRoot) {
    $records = [Collections.Generic.List[string]]::new()
    foreach ($relativeRoot in @('AGENTS.md', 'opencode.json', '.ai', '.opencode')) {
        $absoluteRoot = Join-Path $RepositoryRoot $relativeRoot
        if (Test-Path -LiteralPath $absoluteRoot -PathType Leaf) {
            $normalized = [IO.Path]::GetRelativePath($RepositoryRoot, $absoluteRoot).Replace('\', '/')
            $records.Add($normalized + "`t" + (Get-FileSha256 -Path $absoluteRoot))
            continue
        }
        if (-not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $absoluteRoot -Recurse -Force -File) {
            $normalized = [IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName).Replace('\', '/')
            if ($normalized -match '^\.ai/(?:runtime|runs)(?:/|$)') { continue }
            $records.Add($normalized + "`t" + (Get-FileSha256 -Path $file.FullName))
        }
    }
    return Get-StringSha256 -Value ((@($records | Sort-Object)) -join "`n")
}

function Assert-ControlPlane([System.Collections.IDictionary]$State, [string]$RepositoryRoot) {
    if (-not $State.Contains('controlPlaneFingerprint') -or [string]::IsNullOrWhiteSpace([string]$State.controlPlaneFingerprint)) {
        throw 'This run predates deterministic control-plane protection. Start a new run before continuing.'
    }
    $current = Get-ControlPlaneFingerprint -RepositoryRoot $RepositoryRoot
    if ($current -ne [string]$State.controlPlaneFingerprint) {
        throw 'Workflow control plane changed after the run started. Restore or approve the configuration change, then start a new run.'
    }
}

function Get-QualityPlan([string]$RepositoryRoot, [string[]]$AffectedModuleIds) {
    $projectPath = Join-Path $RepositoryRoot '.ai\project.json'
    $projectSchemaPath = Join-Path $RepositoryRoot '.ai\project.schema.json'
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) { throw 'Quality planning requires .ai/project.json.' }
    if (-not (Test-Path -LiteralPath $projectSchemaPath -PathType Leaf)) { throw 'Quality planning requires .ai/project.schema.json.' }
    $projectJson = Get-Content -LiteralPath $projectPath -Raw
    $projectSchema = Get-Content -LiteralPath $projectSchemaPath -Raw
    if (-not ($projectJson | Test-Json -Schema $projectSchema -ErrorAction Stop)) { throw '.ai/project.json failed schema validation.' }
    $project = $projectJson | ConvertFrom-Json
    $requestedIds = @(
        $AffectedModuleIds |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    if ($requestedIds.Count -eq 0) { throw 'At least one affected module is required to approve an implementation plan.' }

    $availableModules = @($project.modules)
    $availableIds = @($availableModules | ForEach-Object { [string]$_.id })
    $missingIds = @($requestedIds | Where-Object { $availableIds -notcontains $_ })
    if ($missingIds.Count -gt 0) { throw "Unknown affected module(s): $($missingIds -join ', ')" }

    $modules = @(
        foreach ($moduleId in $requestedIds) {
            $module = @($availableModules | Where-Object { [string]$_.id -eq $moduleId })[0]
            [ordered]@{
                id = $moduleId
                path = ([string]$module.path).Replace('\', '/')
                phases = @(
                    foreach ($phaseName in $script:qualityPhaseOrder) {
                        [ordered]@{
                            name = $phaseName
                            commands = @($module.quality.$phaseName | ForEach-Object { [string]$_ })
                        }
                    }
                )
            }
        }
    )
    $matrixJson = ([ordered]@{ modules = $modules } | ConvertTo-Json -Depth 8 -Compress)
    return [pscustomobject]@{
        AffectedModuleIds = $requestedIds
        ProjectSha256 = Get-FileSha256 -Path $projectPath
        MatrixSha256 = Get-StringSha256 -Value $matrixJson
        Modules = $modules
    }
}

function Get-ValidatedGateEvidence([string]$SourcePath, [string]$RepositoryRoot, [System.Collections.IDictionary]$State) {
    $gateSchemaPath = Join-Path $RepositoryRoot '.ai\quality-gates.schema.json'
    $projectPath = Join-Path $RepositoryRoot '.ai\project.json'
    $runnerPath = Join-Path $RepositoryRoot '.ai\scripts\run-quality-gates.ps1'
    foreach ($requiredPath in @($gateSchemaPath, $projectPath, $runnerPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required gate validation input not found: $requiredPath" }
    }

    $json = Get-Content -LiteralPath $SourcePath -Raw
    $schema = Get-Content -LiteralPath $gateSchemaPath -Raw
    if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Quality-gate evidence failed schema validation.' }
    $evidence = $json | ConvertFrom-Json
    if ([string]$evidence.runId -ne [string]$State.runId) { throw 'Quality-gate evidence belongs to a different workflow run.' }
    if (-not $State.Contains('qualityPlan') -or $null -eq $State.qualityPlan) {
        throw 'This run has no approved quality plan. Approve a new plan with affected modules.'
    }
    $expectedPlan = Get-QualityPlan -RepositoryRoot $RepositoryRoot -AffectedModuleIds @($State.qualityPlan.affectedModuleIds)
    if ([string]$State.qualityPlan.projectSha256 -ne $expectedPlan.ProjectSha256 -or
        [string]$State.qualityPlan.matrixSha256 -ne $expectedPlan.MatrixSha256) {
        throw 'The approved quality plan no longer matches .ai/project.json.'
    }
    if ([string]$evidence.projectSha256 -ne $expectedPlan.ProjectSha256) {
        throw 'Quality-gate evidence was produced from a different .ai/project.json.'
    }
    if ([string]$evidence.runnerSha256 -ne (Get-FileSha256 -Path $runnerPath)) {
        throw 'Quality-gate evidence was produced by a different runner version.'
    }
    if ([string]$evidence.qualityPlanSha256 -ne $expectedPlan.MatrixSha256) {
        throw 'Quality-gate evidence does not match the approved command matrix.'
    }

    $derivedModuleStatuses = @()
    $evidenceModules = @($evidence.modules)
    $expectedModules = @($expectedPlan.Modules)
    if ($evidenceModules.Count -ne $expectedModules.Count) { throw 'Quality-gate evidence does not contain every affected module.' }
    for ($moduleIndex = 0; $moduleIndex -lt $expectedModules.Count; $moduleIndex++) {
        $module = $evidenceModules[$moduleIndex]
        $expectedModule = $expectedModules[$moduleIndex]
        if ([string]$module.id -ne [string]$expectedModule.id -or [string]$module.path -ne [string]$expectedModule.path) {
            throw "Quality-gate module identity mismatch at index $moduleIndex."
        }
        $evidencePhases = @($module.phases)
        $expectedPhases = @($expectedModule.phases)
        if ($evidencePhases.Count -ne $expectedPhases.Count) { throw "Quality-gate phase count mismatch for module '$($module.id)'." }
        for ($phaseIndex = 0; $phaseIndex -lt $expectedPhases.Count; $phaseIndex++) {
            $evidencePhase = $evidencePhases[$phaseIndex]
            $expectedPhase = $expectedPhases[$phaseIndex]
            if ([string]$evidencePhase.name -ne [string]$expectedPhase.name) {
                throw "Quality-gate phase order mismatch for module '$($module.id)'."
            }
            $evidenceCommands = @($evidencePhase.commands)
            $expectedCommands = @($expectedPhase.commands)
            if ($evidenceCommands.Count -ne $expectedCommands.Count) {
                throw "Quality-gate command count mismatch for module '$($module.id)' phase '$($evidencePhase.name)'."
            }
            for ($commandIndex = 0; $commandIndex -lt $expectedCommands.Count; $commandIndex++) {
                if ([string]$evidenceCommands[$commandIndex].command -ne [string]$expectedCommands[$commandIndex]) {
                    throw "Quality-gate command mismatch for module '$($module.id)' phase '$($evidencePhase.name)' index $commandIndex."
                }
            }
        }
        $commands = @($module.phases | ForEach-Object { @($_.commands) })
        if ([int]$module.configuredCommandCount -ne $commands.Count) {
            throw "Quality-gate command count mismatch for module '$($module.id)'."
        }
        $derivedModuleStatus = if ($commands.Count -eq 0) {
            'INCOMPLETE_CONFIGURATION'
        }
        elseif (@($commands | Where-Object { [string]$_.status -ne 'PASS' }).Count -gt 0) {
            'FAIL'
        }
        else { 'PASS' }
        if ([string]$module.overall -ne $derivedModuleStatus) {
            throw "Quality-gate module verdict mismatch for '$($module.id)'."
        }
        $derivedModuleStatuses += $derivedModuleStatus
    }

    if ([bool]$evidence.worktreeStable -ne ([string]$evidence.startedWorktreeFingerprint -eq [string]$evidence.worktreeFingerprint)) {
        throw 'Quality-gate worktree stability flag is inconsistent with its fingerprints.'
    }
    $derivedOverall = if (-not [bool]$evidence.worktreeStable -or $derivedModuleStatuses -contains 'FAIL') {
        'FAIL'
    }
    elseif ($derivedModuleStatuses -contains 'INCOMPLETE_CONFIGURATION') {
        'INCOMPLETE_CONFIGURATION'
    }
    else { 'PASS' }
    if ([string]$evidence.overall -ne $derivedOverall) { throw 'Quality-gate overall verdict does not match command evidence.' }

    $currentSha = Get-CurrentSha -RepositoryRoot $RepositoryRoot
    $currentFingerprint = Get-WorktreeFingerprint -RepositoryRoot $RepositoryRoot -CurrentSha $currentSha
    if ($currentFingerprint -ne [string]$evidence.worktreeFingerprint) {
        throw 'Worktree changed after deterministic quality gates ran.'
    }
    return [pscustomobject]@{
        Verdict = if ($derivedOverall -eq 'PASS') { 'PASS' } else { 'FAIL' }
        Overall = $derivedOverall
        WorktreeFingerprint = [string]$evidence.worktreeFingerprint
    }
}

function Get-ValidatedPublishEvidence(
    [string]$SourcePath,
    [string]$RepositoryRoot,
    [System.Collections.IDictionary]$State
) {
    $schemaPath = Join-Path $RepositoryRoot '.ai\publish-evidence.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Publish evidence schema not found: $schemaPath" }
    $json = Get-Content -LiteralPath $SourcePath -Raw
    $schema = Get-Content -LiteralPath $schemaPath -Raw
    if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Publish evidence failed schema validation.' }
    $evidence = $json | ConvertFrom-Json

    $currentSha = Get-CurrentSha -RepositoryRoot $RepositoryRoot
    $currentBranch = (& git -C $RepositoryRoot branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) { throw 'Publish verification requires a named branch.' }
    if ($currentBranch -match '^(main|master|develop|development|trunk|release)(/|$)') {
        throw "Publish evidence targets protected or shared branch '$currentBranch'."
    }
    if ([string]$evidence.runId -ne [string]$State.runId) { throw 'Publish evidence belongs to a different workflow run.' }
    if ([string]$evidence.sha -ne $currentSha -or [string]$evidence.sha -ne [string]$State.currentSha) {
        throw 'Published SHA does not match the persisted run and current HEAD.'
    }
    if ([string]$evidence.branch -ne $currentBranch) { throw 'Published branch does not match the current branch.' }
    $expectedRef = "refs/heads/$currentBranch"
    if ([string]$evidence.ref -ne $expectedRef) { throw "Published ref must be '$expectedRef'." }

    $remote = [string]$evidence.remote
    $remoteUrl = (& git -C $RepositoryRoot remote get-url $remote 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) { throw "Remote '$remote' is not configured." }
    $upstream = (& git -C $RepositoryRoot rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $upstream.Trim() -ne "$remote/$currentBranch") {
        throw "Current branch upstream is not '$remote/$currentBranch'."
    }

    $previousPrompt = [Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0', 'Process')
        $remoteRows = @(& git -C $RepositoryRoot ls-remote --exit-code $remote $expectedRef 2>$null)
        if ($LASTEXITCODE -ne 0 -or $remoteRows.Count -ne 1) { throw "Remote ref '$remote/$currentBranch' could not be verified." }
    }
    finally {
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', $previousPrompt, 'Process')
    }
    $remoteSha = (($remoteRows[0] -split '\s+')[0]).ToLowerInvariant()
    if ($remoteSha -ne $currentSha) { throw "Remote ref '$remote/$currentBranch' does not point to the recorded commit." }
    return $evidence
}

function Get-ValidatedPullRequestEvidence(
    [string]$SourcePath,
    [string]$RepositoryRoot,
    [System.Collections.IDictionary]$State
) {
    $schemaPath = Join-Path $RepositoryRoot '.ai\pull-request-evidence.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Pull-request evidence schema not found: $schemaPath" }
    $json = Get-Content -LiteralPath $SourcePath -Raw
    $schema = Get-Content -LiteralPath $schemaPath -Raw
    if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Pull-request evidence failed schema validation.' }
    $evidence = $json | ConvertFrom-Json
    if ([string]$evidence.runId -ne [string]$State.runId) { throw 'Pull-request evidence belongs to a different workflow run.' }

    $currentSha = Get-CurrentSha -RepositoryRoot $RepositoryRoot
    $currentBranch = (& git -C $RepositoryRoot branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) { throw 'Pull-request verification requires a named branch.' }
    if ([string]$evidence.head -ne $currentBranch) { throw 'Pull-request head does not match the current branch.' }
    if ([string]$evidence.headSha -ne $currentSha -or [string]$evidence.headSha -ne [string]$State.currentSha) {
        throw 'Pull-request head SHA does not match the persisted run and current HEAD.'
    }

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) { throw 'GitHub CLI is required to verify pull-request evidence.' }
    Push-Location $RepositoryRoot
    try {
        $actualJson = (& $ghCommand.Source pr view ([string]$evidence.number) --json 'number,url,baseRefName,headRefName,headRefOid,title,isDraft,state')
        $ghSucceeded = $?
        if (-not $ghSucceeded -or [string]::IsNullOrWhiteSpace($actualJson)) { throw 'GitHub CLI could not verify the pull request.' }
    }
    finally { Pop-Location }
    $actual = $actualJson | ConvertFrom-Json
    $checks = [ordered]@{
        number = ([int]$actual.number -eq [int]$evidence.number)
        url = ([string]$actual.url -eq [string]$evidence.url)
        base = ([string]$actual.baseRefName -eq [string]$evidence.base)
        head = ([string]$actual.headRefName -eq [string]$evidence.head)
        headSha = ([string]$actual.headRefOid -eq [string]$evidence.headSha)
        title = ([string]$actual.title -eq [string]$evidence.title)
        draft = ([bool]$actual.isDraft -and [bool]$evidence.draft)
        state = ([string]$actual.state -eq 'OPEN' -and [string]$evidence.state -eq 'OPEN')
    }
    $mismatches = @($checks.Keys | Where-Object { -not $checks[$_] })
    if ($mismatches.Count -gt 0) { throw "Pull-request evidence does not match GitHub: $($mismatches -join ', ')." }
    return $evidence
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
    $requirementSource = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'requirement.md'
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
        controlPlaneFingerprint = Get-ControlPlaneFingerprint -RepositoryRoot $repositoryRoot
        qualityPlan = $null
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
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
            if ([string]::IsNullOrWhiteSpace($AffectedModules)) { throw 'ApprovePlan requires AffectedModules as a comma-separated list.' }
            $qualityPlan = Get-QualityPlan -RepositoryRoot $repositoryRoot -AffectedModuleIds @($AffectedModules.Split(',', [StringSplitOptions]::RemoveEmptyEntries))
            $source = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'plan.md'
            Add-Artifact -State $state -Name 'plan' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict 'PASS'
            $state.qualityPlan = [ordered]@{
                affectedModuleIds = @($qualityPlan.AffectedModuleIds)
                projectSha256 = $qualityPlan.ProjectSha256
                matrixSha256 = $qualityPlan.MatrixSha256
            }
            $state.status = 'PLAN_APPROVED'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'BeginImplementation' {
            Assert-Status -State $state -Allowed @('PLAN_APPROVED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
            $state.status = 'IMPLEMENTING'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordGates' {
            Assert-Status -State $state -Allowed @('IMPLEMENTING')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
            if (@('PASS', 'FAIL') -notcontains $Verdict) { throw 'RecordGates requires Verdict PASS or FAIL.' }
            $source = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'gates.json'
            $gateEvidence = Get-ValidatedGateEvidence -SourcePath $source -RepositoryRoot $repositoryRoot -State $state
            if ($Verdict -ne [string]$gateEvidence.Verdict) {
                throw "RecordGates verdict '$Verdict' does not match deterministic evidence '$($gateEvidence.Overall)'."
            }
            Add-Artifact -State $state -Name 'gates' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict $Verdict
            $state.worktreeFingerprint = [string]$gateEvidence.WorktreeFingerprint
            $state.status = if ($Verdict -eq 'PASS') { 'GATES_PASSED' } else { 'GATE_FAILED' }
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordReview' {
            Assert-Status -State $state -Allowed @('GATES_PASSED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
            if ([string]::IsNullOrWhiteSpace($Verdict)) { throw 'RecordReview requires a verdict.' }
            $currentFingerprint = Get-WorktreeFingerprint -RepositoryRoot $repositoryRoot -CurrentSha ([string]$state.currentSha)
            if ($currentFingerprint -ne [string]$state.worktreeFingerprint) { throw 'Worktree changed after gates; rerun the complete gate before review.' }
            $source = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'review.md'
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
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
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
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
            if (@('PASS', 'FAIL', 'ESCALATE') -notcontains $Verdict) { throw 'RecordDiagnosis requires Verdict PASS, FAIL, or ESCALATE.' }
            $next = [int]$state.diagnosticIterations + 1
            if ($next -gt [int]$state.maximumDiagnosticIterations) { throw 'Diagnostic iteration limit reached; escalate instead of continuing.' }
            $source = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'diagnosis.json'
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
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
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
            $source = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'commit.json'
            Add-Artifact -State $state -Name 'commit' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict 'PASS'
            $state.currentSha = $newSha
            $state.status = 'COMMITTED'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordPublish' {
            Assert-Status -State $state -Allowed @('COMMITTED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
            $source = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'publish.json'
            Get-ValidatedPublishEvidence -SourcePath $source -RepositoryRoot $repositoryRoot -State $state | Out-Null
            Add-Artifact -State $state -Name 'publish' -SourcePath $source -RunRoot $runRoot -ArtifactVerdict 'PASS'
            $state.status = 'PUBLISHED'
            Write-State -State $state -StatePath $statePath -SchemaPath $schemaPath
        }
        'RecordPullRequest' {
            Assert-Status -State $state -Allowed @('PUBLISHED')
            Assert-Head -State $state -RepositoryRoot $repositoryRoot
            Assert-ControlPlane -State $state -RepositoryRoot $repositoryRoot
            $source = Resolve-RunRuntimeArtifact -RepositoryRoot $repositoryRoot -RunId $RunId -Path $ArtifactPath -FileName 'pull-request.json'
            Get-ValidatedPullRequestEvidence -SourcePath $source -RepositoryRoot $repositoryRoot -State $state | Out-Null
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
