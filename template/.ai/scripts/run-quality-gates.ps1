[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 900,
    [switch]$ContinueAfterFailure,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

$phaseOrder = @('restore', 'build', 'lint', 'typecheck', 'test', 'e2e')
$maximumCapturedCharacters = 12000

function Get-RepositoryRoot {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) { throw 'Git is required to run deterministic quality gates.' }
    $root = (& $git.Source rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        throw 'Quality gates require an initialized Git repository.'
    }
    return [IO.Path]::GetFullPath($root.Trim()).TrimEnd('\', '/')
}

function Get-StringSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TaskVerification(
    [string]$VerificationPath,
    [string]$SchemaPath,
    [string]$ExpectedRunId,
    [string[]]$AffectedModuleIds
) {
    foreach ($requiredPath in @($VerificationPath, $SchemaPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required run-specific verification input not found: $requiredPath"
        }
    }
    $json = Get-Content -LiteralPath $VerificationPath -Raw
    $schema = Get-Content -LiteralPath $SchemaPath -Raw
    if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) {
        throw 'Run-specific verification manifest failed schema validation.'
    }
    $manifest = $json | ConvertFrom-Json
    if ([string]$manifest.runId -ne $ExpectedRunId) {
        throw 'Run-specific verification manifest belongs to a different workflow run.'
    }
    if ([int]$manifest.schemaVersion -eq 2) {
        $contractModules = @($manifest.affectedModules | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $approvedModules = @($AffectedModuleIds | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (($contractModules -join "`n") -ne ($approvedModules -join "`n")) {
            throw 'Execution contract affectedModules no longer match the approved affected modules.'
        }
    }
    $unsafeCommandPattern = '(?i)(?:^|\s)(?:git\s+(?:add|commit|push|merge|rebase|reset|clean|tag|branch|switch|checkout)|gh\s+(?:pr\s+(?:create|edit|ready|merge)|release|secret|variable|workflow\s+run)|kubectl\s+(?:apply|delete|patch|scale|rollout|exec|cp)|terraform\s+(?:apply|destroy|import|taint|untaint)|az\s+deployment)(?:\s|$)'
    $seen = @{}
    foreach ($record in @($manifest.commands)) {
        $moduleId = [string]$record.moduleId
        if ($AffectedModuleIds -notcontains $moduleId) {
            throw "Run-specific verification references module '$moduleId' outside the approved affected modules."
        }
        $command = [string]$record.command
        if ($command -match $unsafeCommandPattern) {
            throw "Run-specific verification contains a delivery or mutation command: $command"
        }
        $key = "$moduleId`n$([string]$record.phase)`n$command"
        if ($seen.ContainsKey($key)) {
            throw "Run-specific verification contains a duplicate command for module '$moduleId': $command"
        }
        $seen[$key] = $true
    }
    return [pscustomobject]@{
        Sha256 = Get-FileSha256 -Path $VerificationPath
        Manifest = $manifest
    }
}

function Get-QualityPlan(
    [object]$Project,
    [string[]]$AffectedModuleIds,
    [string]$ProjectPath,
    [object]$TaskVerification
) {
    $requestedIds = @(
        $AffectedModuleIds |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    if ($requestedIds.Count -eq 0) { throw 'The persisted quality plan contains no affected modules.' }

    $availableModules = @($Project.modules)
    $availableIds = @($availableModules | ForEach-Object { [string]$_.id })
    $missingIds = @($requestedIds | Where-Object { $availableIds -notcontains $_ })
    if ($missingIds.Count -gt 0) { throw "Unknown quality-plan module(s): $($missingIds -join ', ')" }

    $modules = @(
        foreach ($moduleId in $requestedIds) {
            $module = @($availableModules | Where-Object { [string]$_.id -eq $moduleId })[0]
            [ordered]@{
                id = $moduleId
                path = ([string]$module.path).Replace('\', '/')
                phases = @(
                    foreach ($phaseName in $script:phaseOrder) {
                        $configuredCommands = @($module.quality.$phaseName | ForEach-Object { [string]$_ })
                        $runCommands = @(
                            $TaskVerification.Manifest.commands |
                                Where-Object { [string]$_.moduleId -eq $moduleId -and [string]$_.phase -eq $phaseName } |
                                ForEach-Object { [string]$_.command }
                        )
                        $duplicates = @($runCommands | Where-Object { $configuredCommands -contains $_ })
                        if ($duplicates.Count -gt 0) {
                            throw "Run-specific verification duplicates a configured command for module '$moduleId' phase '$phaseName': $($duplicates -join ', ')"
                        }
                        [ordered]@{
                            name = $phaseName
                            commands = @($configuredCommands + $runCommands)
                        }
                    }
                )
            }
        }
    )
    $matrixJson = ([ordered]@{ modules = $modules } | ConvertTo-Json -Depth 8 -Compress)
    return [pscustomobject]@{
        AffectedModuleIds = $requestedIds
        ProjectSha256 = Get-FileSha256 -Path $ProjectPath
        MatrixSha256 = Get-StringSha256 -Value $matrixJson
        VerificationSha256 = $TaskVerification.Sha256
        Modules = $modules
    }
}

function Get-WorktreeFingerprint([string]$RepositoryRoot) {
    $currentSha = @(& git -C $RepositoryRoot rev-parse HEAD 2>$null)
    $head = if ($LASTEXITCODE -eq 0 -and $currentSha.Count -eq 1) { ([string]$currentSha[0]).Trim().ToLowerInvariant() } else { 'UNBORN' }
    $temporaryIndex = Join-Path ([IO.Path]::GetTempPath()) ('ai-engineering-workflow-gates-index-' + [Guid]::NewGuid().ToString('N'))
    $previousIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process')
    $emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
    try {
        [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $temporaryIndex, 'Process')
        if ($head -eq 'UNBORN') { & git -C $RepositoryRoot read-tree --empty }
        else { & git -C $RepositoryRoot read-tree $head }
        if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the quality-gate Git snapshot.' }

        & git -C $RepositoryRoot add -A -- .
        if ($LASTEXITCODE -ne 0) { throw 'Unable to construct the quality-gate worktree snapshot.' }

        $baseline = if ($head -eq 'UNBORN') { $emptyTree } else { $head }
        $diff = @(& git -C $RepositoryRoot diff --cached --binary --no-ext-diff $baseline --)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to calculate the quality-gate worktree diff.' }
        return Get-StringSha256 -Value ((@("HEAD=$head", 'DIFF', ($diff -join "`n"))) -join "`n")
    }
    finally {
        [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $previousIndex, 'Process')
        if (Test-Path -LiteralPath $temporaryIndex) { Remove-Item -LiteralPath $temporaryIndex -Force }
        $lockPath = $temporaryIndex + '.lock'
        if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force }
    }
}

function Get-WorktreePathSnapshot([string]$RepositoryRoot) {
    & git -C $RepositoryRoot rev-parse --verify HEAD *> $null
    $tracked = if ($LASTEXITCODE -eq 0) {
        @(& git -C $RepositoryRoot diff --name-only HEAD --)
    }
    else {
        @(& git -C $RepositoryRoot diff --cached --name-only --)
    }
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list tracked worktree changes.' }
    $untracked = @(& git -C $RepositoryRoot ls-files --others --exclude-standard --)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list untracked worktree changes.' }
    return [pscustomobject]@{
        Tracked = @($tracked | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object -Unique)
        Untracked = @($untracked | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object -Unique)
    }
}

function ConvertTo-EvidenceSnapshot([object]$Snapshot) {
    $maximumPaths = 200
    $tracked = @($Snapshot.Tracked)
    $untracked = @($Snapshot.Untracked)
    return [ordered]@{
        trackedCount = $tracked.Count
        untrackedCount = $untracked.Count
        tracked = @($tracked | Select-Object -First $maximumPaths)
        untracked = @($untracked | Select-Object -First $maximumPaths)
        truncated = ($tracked.Count -gt $maximumPaths -or $untracked.Count -gt $maximumPaths)
    }
}

function Get-WorktreeChangeEvidence([object]$Before, [object]$After) {
    $beforePaths = @(@($Before.Tracked) + @($Before.Untracked) | Sort-Object -Unique)
    $afterPaths = @(@($After.Tracked) + @($After.Untracked) | Sort-Object -Unique)
    return [ordered]@{
        before = ConvertTo-EvidenceSnapshot -Snapshot $Before
        after = ConvertTo-EvidenceSnapshot -Snapshot $After
        addedDuringRun = @($afterPaths | Where-Object { $beforePaths -notcontains $_ } | Select-Object -First 200)
        removedDuringRun = @($beforePaths | Where-Object { $afterPaths -notcontains $_ } | Select-Object -First 200)
    }
}

function Get-RepositoryHygiene([string]$RepositoryRoot, [object]$Project) {
    $trackedFiles = @(& git -C $RepositoryRoot ls-files --)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect tracked files for repository hygiene.' }
    $trackedFiles = @($trackedFiles | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object -Unique)
    $issues = [Collections.Generic.List[object]]::new()
    $seen = @{}

    foreach ($module in @($Project.modules)) {
        $modulePath = ([string]$module.path).Replace('\', '/').TrimEnd('/')
        $stackTokens = @(@($module.languages) + @($module.frameworks) | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $generatedDirectories = [Collections.Generic.List[string]]::new()
        if (@($stackTokens | Where-Object { $_ -in @('csharp', 'fsharp', 'visual-basic', 'aspnetcore', 'dotnet') }).Count -gt 0) {
            $generatedDirectories.Add('bin')
            $generatedDirectories.Add('obj')
        }
        if (@($stackTokens | Where-Object { $_ -in @('javascript', 'typescript', 'node', 'react') }).Count -gt 0) { $generatedDirectories.Add('node_modules') }
        if ($stackTokens -contains 'python') {
            $generatedDirectories.Add('__pycache__')
            $generatedDirectories.Add('.pytest_cache')
        }
        if (@($stackTokens | Where-Object { $_ -in @('java', 'kotlin', 'spring') }).Count -gt 0) {
            $generatedDirectories.Add('target')
            $generatedDirectories.Add('build')
        }

        foreach ($directory in @($generatedDirectories | Sort-Object -Unique)) {
            $prefix = if ([string]::IsNullOrWhiteSpace($modulePath) -or $modulePath -eq '.') { '' } else { $modulePath + '/' }
            $directoryPath = $prefix + $directory
            $pathPattern = '^(?:' + [regex]::Escape($prefix) + ')(?:.*/)?' + [regex]::Escape($directory) + '/'
            foreach ($trackedPath in @($trackedFiles | Where-Object { $_ -match $pathPattern } | Select-Object -First 100)) {
                $key = 'tracked:' + $trackedPath.ToLowerInvariant()
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $issues.Add([ordered]@{
                        code = 'TRACKED_GENERATED_ARTIFACT'
                        path = $trackedPath
                        message = "Generated output is tracked by Git. Remove it from version control through a separate reviewed repository-hygiene change."
                    })
                }
            }

            $ignoreProbe = $directoryPath + '/.ai-workflow-ignore-probe'
            & git -C $RepositoryRoot check-ignore --no-index --quiet -- $ignoreProbe
            if ($LASTEXITCODE -ne 0) {
                $key = 'ignore:' + $directoryPath.ToLowerInvariant()
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $issues.Add([ordered]@{
                        code = 'GENERATED_PATH_NOT_IGNORED'
                        path = $directoryPath + '/'
                        message = 'Generated output is not ignored. Add an appropriate repository ignore rule before running build commands.'
                    })
                }
            }
        }
    }

    return [ordered]@{
        status = if ($issues.Count -gt 0) { 'BLOCKED' } else { 'PASS' }
        issues = @($issues)
    }
}

function Get-ControlPlaneOutputPaths([string]$RepositoryRoot, [object]$Project) {
    $matches = [Collections.Generic.List[string]]::new()
    foreach ($module in @($Project.modules)) {
        $moduleRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ([string]$module.path)))
        foreach ($directory in @('bin', 'obj', 'dist', 'target', 'build')) {
            $outputRoot = Join-Path $moduleRoot $directory
            if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $outputRoot -Recurse -File -ErrorAction SilentlyContinue)) {
                $relative = ([IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName)).Replace('\', '/')
                if ($file.Name -in @('opencode.json', 'AGENTS.md') -or $relative -match '(?:^|/)(?:\.ai|\.opencode)(?:/|$)') {
                    $matches.Add($relative)
                    if ($matches.Count -ge 100) { break }
                }
            }
            if ($matches.Count -ge 100) { break }
        }
        if ($matches.Count -ge 100) { break }
    }
    return @($matches | Sort-Object -Unique)
}

function Get-CapturedText([string]$Value) {
    if ($null -eq $Value) { return [pscustomobject]@{ Text = ''; Truncated = $false } }
    if ($Value.Length -le $maximumCapturedCharacters) {
        return [pscustomobject]@{ Text = $Value; Truncated = $false }
    }
    return [pscustomobject]@{
        Text = $Value.Substring(0, $maximumCapturedCharacters) + "`n...[truncated by deterministic quality-gate runner]"
        Truncated = $true
    }
}

function Invoke-GateCommand([string]$Command, [string]$WorkingDirectory, [int]$Timeout) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) { throw 'pwsh is required to execute configured quality-gate commands.' }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh.Source
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-NonInteractive')
    $startInfo.ArgumentList.Add('-Command')
    $wrappedCommand = @(
        '$global:LASTEXITCODE = 0'
        $Command
        'if (-not $?) { if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; exit 1 }'
        'exit $LASTEXITCODE'
    ) -join "`n"
    $startInfo.ArgumentList.Add($wrappedCommand)

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        if (-not $process.Start()) { throw "Unable to start configured command: $Command" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout * 1000)) {
            $timedOut = $true
            $process.Kill($true)
            $process.WaitForExit()
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
    }
    finally {
        $stopwatch.Stop()
        $process.Dispose()
    }

    $capturedStdout = Get-CapturedText -Value $stdout
    $capturedStderr = Get-CapturedText -Value $stderr
    return [ordered]@{
        command = $Command
        workingDirectory = [IO.Path]::GetRelativePath($script:repositoryRoot, $WorkingDirectory).Replace('\', '/')
        status = if ($exitCode -eq 0 -and -not $timedOut) { 'PASS' } else { 'FAIL' }
        exitCode = [int]$exitCode
        durationMilliseconds = [int64]$stopwatch.ElapsedMilliseconds
        timedOut = $timedOut
        stdout = [string]$capturedStdout.Text
        stderr = [string]$capturedStderr.Text
        outputTruncated = [bool]($capturedStdout.Truncated -or $capturedStderr.Truncated)
    }
}

function New-NotRunResult([string]$Command, [string]$WorkingDirectory) {
    return [ordered]@{
        command = $Command
        workingDirectory = [IO.Path]::GetRelativePath($script:repositoryRoot, $WorkingDirectory).Replace('\', '/')
        status = 'NOT_RUN'
        exitCode = $null
        durationMilliseconds = $null
        timedOut = $false
        stdout = ''
        stderr = ''
        outputTruncated = $false
    }
}

try {
    $repositoryRoot = Get-RepositoryRoot
    $projectPath = Join-Path $repositoryRoot '.ai\project.json'
    $projectSchemaPath = Join-Path $repositoryRoot '.ai\project.schema.json'
    $verificationSchemaPath = Join-Path $repositoryRoot '.ai\task-verification.schema.json'
    $gateSchemaPath = Join-Path $repositoryRoot '.ai\quality-gates.schema.json'
    $runSchemaPath = Join-Path $repositoryRoot '.ai\workflow-run.schema.json'
    $statePath = Join-Path $repositoryRoot ".ai\runs\$RunId\state.json"
    $runRoot = Split-Path -Parent $statePath
    $outputPath = Join-Path $repositoryRoot ".ai\runtime\$RunId\gates.json"
    $runnerPath = $MyInvocation.MyCommand.Path

    foreach ($requiredPath in @($projectPath, $projectSchemaPath, $verificationSchemaPath, $gateSchemaPath, $runSchemaPath, $statePath, $runnerPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required quality-gate input not found: $requiredPath" }
    }

    $projectJson = Get-Content -LiteralPath $projectPath -Raw
    $projectSchema = Get-Content -LiteralPath $projectSchemaPath -Raw
    if (-not ($projectJson | Test-Json -Schema $projectSchema -ErrorAction Stop)) {
        throw '.ai/project.json failed schema validation.'
    }
    $project = $projectJson | ConvertFrom-Json
    $stateJson = Get-Content -LiteralPath $statePath -Raw
    $runSchema = Get-Content -LiteralPath $runSchemaPath -Raw
    if (-not ($stateJson | Test-Json -Schema $runSchema -ErrorAction Stop)) { throw "Run '$RunId' failed state schema validation." }
    $state = $stateJson | ConvertFrom-Json
    if ([string]$state.status -ne 'IMPLEMENTING') { throw "Run '$RunId' must be in IMPLEMENTING state to execute quality gates." }
    if ($null -eq $state.qualityPlan) { throw "Run '$RunId' has no approved quality plan. Approve a new plan with affected modules." }
    if (-not ($state.artifacts.PSObject.Properties.Name -contains 'verification')) {
        throw "Run '$RunId' has no approved run-specific verification manifest."
    }
    $verificationPath = Join-Path $runRoot ([string]$state.artifacts.verification.path)
    $verification = Get-TaskVerification -VerificationPath $verificationPath -SchemaPath $verificationSchemaPath -ExpectedRunId $RunId -AffectedModuleIds @($state.qualityPlan.affectedModuleIds)
    if ([string]$state.artifacts.verification.sha256 -ne $verification.Sha256 -or
        [string]$state.qualityPlan.verificationSha256 -ne $verification.Sha256) {
        throw "Run '$RunId' verification manifest hash does not match approved state."
    }
    $qualityPlan = Get-QualityPlan -Project $project -AffectedModuleIds @($state.qualityPlan.affectedModuleIds) -ProjectPath $projectPath -TaskVerification $verification
    if ([string]$state.qualityPlan.projectSha256 -ne $qualityPlan.ProjectSha256 -or
        [string]$state.qualityPlan.matrixSha256 -ne $qualityPlan.MatrixSha256 -or
        [string]$state.qualityPlan.verificationSha256 -ne $qualityPlan.VerificationSha256) {
        throw "Run '$RunId' quality plan is stale or does not match .ai/project.json."
    }

    $startedFingerprint = Get-WorktreeFingerprint -RepositoryRoot $repositoryRoot
    $startedPathSnapshot = Get-WorktreePathSnapshot -RepositoryRoot $repositoryRoot
    $repositoryHygiene = Get-RepositoryHygiene -RepositoryRoot $repositoryRoot -Project $project
    $planScope = [ordered]@{ status = 'PASS'; unexpectedPaths = @(); missingPaths = @() }
    if ([int]$verification.Manifest.schemaVersion -eq 2) {
        $actualPaths = @(@($startedPathSnapshot.Tracked) + @($startedPathSnapshot.Untracked) | Sort-Object -Unique)
        $expectedPaths = @($verification.Manifest.expectedChanges | ForEach-Object { ([string]$_.path).Replace('\', '/') } | Sort-Object -Unique)
        $unexpectedPaths = @($actualPaths | Where-Object { $candidate = $_; @($expectedPaths | Where-Object { [string]::Equals($_, $candidate, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0 })
        $missingPaths = @($expectedPaths | Where-Object { $candidate = $_; @($actualPaths | Where-Object { [string]::Equals($_, $candidate, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0 })
        $planScope = [ordered]@{
            status = if ($unexpectedPaths.Count -gt 0 -or $missingPaths.Count -gt 0) { 'INVALID' } else { 'PASS' }
            unexpectedPaths = @($unexpectedPaths | Select-Object -First 200)
            missingPaths = @($missingPaths | Select-Object -First 200)
        }
    }
    if (-not $Force -and (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        try {
            $existingJson = Get-Content -LiteralPath $outputPath -Raw
            $existingSchema = Get-Content -LiteralPath $gateSchemaPath -Raw
            if ($existingJson | Test-Json -Schema $existingSchema -ErrorAction Stop) {
                $existing = $existingJson | ConvertFrom-Json
                $currentProjectHash = Get-FileSha256 -Path $projectPath
                $currentRunnerHash = Get-FileSha256 -Path $runnerPath
                if ([string]$existing.runId -eq $RunId -and
                    [string]$existing.projectSha256 -eq $currentProjectHash -and
                    [string]$existing.runnerSha256 -eq $currentRunnerHash -and
                    [string]$existing.qualityPlanSha256 -eq $qualityPlan.MatrixSha256 -and
                    [bool]$existing.worktreeStable -and
                    [string]$existing.startedWorktreeFingerprint -eq $startedFingerprint -and
                    [string]$existing.worktreeFingerprint -eq $startedFingerprint) {
                    Write-Output $existingJson
                    if ([string]$existing.overall -eq 'PASS') { exit 0 }
                    if ([string]$existing.overall -eq 'INCOMPLETE_CONFIGURATION') { exit 2 }
                    if ([string]$existing.overall -in @('BLOCKED_REPOSITORY_HYGIENE', 'CONTROL_PLANE_OUTPUT', 'PLAN_INVALIDATED')) { exit 4 }
                    exit 1
                }
            }
        }
        catch {
            # Invalid or stale runtime evidence is replaced by a fresh deterministic run.
        }
    }

    $generatedAt = [DateTime]::UtcNow.ToString('o')
    $moduleResults = @()
    if ([string]$planScope.status -eq 'INVALID' -or [string]$repositoryHygiene.status -eq 'BLOCKED') {
        foreach ($module in $qualityPlan.Modules) {
            $modulePath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot ([string]$module.path)))
            $configuredCount = 0
            $phaseResults = @()
            foreach ($phase in @($module.phases)) {
                $commands = @($phase.commands | ForEach-Object { [string]$_ })
                $configuredCount += $commands.Count
                $commandResults = @($commands | ForEach-Object { New-NotRunResult -Command $_ -WorkingDirectory $modulePath })
                $phaseResults += [ordered]@{ name = [string]$phase.name; status = 'NOT_RUN'; commands = $commandResults }
            }
            $moduleResults += [ordered]@{
                id = [string]$module.id
                path = ([string]$module.path).Replace('\', '/')
                overall = 'BLOCKED'
                configuredCommandCount = $configuredCount
                phases = $phaseResults
            }
        }

        $completedFingerprint = Get-WorktreeFingerprint -RepositoryRoot $repositoryRoot
        $completedPathSnapshot = Get-WorktreePathSnapshot -RepositoryRoot $repositoryRoot
        $artifact = [ordered]@{
            schemaVersion = 1
            runId = $RunId
            generatedAtUtc = $generatedAt
            completedAtUtc = [DateTime]::UtcNow.ToString('o')
            projectPath = '.ai/project.json'
            projectSha256 = Get-FileSha256 -Path $projectPath
            runnerSha256 = Get-FileSha256 -Path $runnerPath
            qualityPlanSha256 = $qualityPlan.MatrixSha256
            startedWorktreeFingerprint = $startedFingerprint
            worktreeFingerprint = $completedFingerprint
            worktreeStable = $startedFingerprint -eq $completedFingerprint
            overall = if ([string]$planScope.status -eq 'INVALID') { 'PLAN_INVALIDATED' } else { 'BLOCKED_REPOSITORY_HYGIENE' }
            repositoryHygiene = $repositoryHygiene
            planScope = $planScope
            worktreeChanges = Get-WorktreeChangeEvidence -Before $startedPathSnapshot -After $completedPathSnapshot
            controlPlaneOutputPaths = @()
            modules = $moduleResults
        }
        $json = $artifact | ConvertTo-Json -Depth 12
        $gateSchema = Get-Content -LiteralPath $gateSchemaPath -Raw
        if (-not ($json | Test-Json -Schema $gateSchema -ErrorAction Stop)) { throw 'Generated repository-hygiene evidence failed schema validation.' }
        $outputDirectory = Split-Path -Parent $outputPath
        if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
        $temporaryPath = $outputPath + '.tmp'
        try {
            Set-Content -LiteralPath $temporaryPath -Value $json -Encoding utf8
            Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
        Write-Output $json
        exit 4
    }

    foreach ($module in $qualityPlan.Modules) {
        $modulePath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot ([string]$module.path)))
        if ($modulePath -ne $repositoryRoot -and
            -not $modulePath.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Module path escapes the repository: $($module.path)"
        }
        if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) { throw "Module path does not exist: $($module.path)" }

        $configuredCount = 0
        foreach ($phase in @($module.phases)) { $configuredCount += @($phase.commands).Count }
        $moduleFailed = $false
        $stopModule = $false
        $phaseResults = @()
        foreach ($phase in @($module.phases)) {
            $phaseName = [string]$phase.name
            $commands = @($phase.commands | ForEach-Object { [string]$_ })
            $commandResults = @()
            if ($stopModule) {
                foreach ($command in $commands) { $commandResults += New-NotRunResult -Command $command -WorkingDirectory $modulePath }
                $phaseStatus = 'NOT_RUN'
            }
            elseif ($commands.Count -eq 0) { $phaseStatus = 'NOT_CONFIGURED' }
            else {
                $phaseFailed = $false
                for ($commandIndex = 0; $commandIndex -lt $commands.Count; $commandIndex++) {
                    $command = $commands[$commandIndex]
                    if ($phaseFailed -and -not $ContinueAfterFailure) {
                        $commandResults += New-NotRunResult -Command $command -WorkingDirectory $modulePath
                        continue
                    }
                    $result = Invoke-GateCommand -Command $command -WorkingDirectory $modulePath -Timeout $TimeoutSeconds
                    $commandResults += $result
                    if ($result.status -eq 'FAIL') {
                        $phaseFailed = $true
                        $moduleFailed = $true
                    }
                }
                $phaseStatus = if ($phaseFailed) { 'FAIL' } else { 'PASS' }
                if ($phaseFailed -and -not $ContinueAfterFailure) { $stopModule = $true }
            }
            $phaseResults += [ordered]@{ name = $phaseName; status = $phaseStatus; commands = $commandResults }
        }
        $moduleOverall = if ($configuredCount -eq 0) { 'INCOMPLETE_CONFIGURATION' } elseif ($moduleFailed) { 'FAIL' } else { 'PASS' }
        $moduleResults += [ordered]@{
            id = [string]$module.id
            path = ([string]$module.path).Replace('\', '/')
            overall = $moduleOverall
            configuredCommandCount = $configuredCount
            phases = $phaseResults
        }
    }

    $completedFingerprint = Get-WorktreeFingerprint -RepositoryRoot $repositoryRoot
    $completedPathSnapshot = Get-WorktreePathSnapshot -RepositoryRoot $repositoryRoot
    $worktreeStable = $startedFingerprint -eq $completedFingerprint
    $controlPlaneOutputPaths = @(Get-ControlPlaneOutputPaths -RepositoryRoot $repositoryRoot -Project $project)
    $overall = if ($controlPlaneOutputPaths.Count -gt 0) {
        'CONTROL_PLANE_OUTPUT'
    }
    elseif (-not $worktreeStable -or @($moduleResults | Where-Object { $_.overall -eq 'FAIL' }).Count -gt 0) {
        'FAIL'
    }
    elseif (@($moduleResults | Where-Object { $_.overall -eq 'INCOMPLETE_CONFIGURATION' }).Count -gt 0) {
        'INCOMPLETE_CONFIGURATION'
    }
    else { 'PASS' }

    $artifact = [ordered]@{
        schemaVersion = 1
        runId = $RunId
        generatedAtUtc = $generatedAt
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        projectPath = '.ai/project.json'
        projectSha256 = Get-FileSha256 -Path $projectPath
        runnerSha256 = Get-FileSha256 -Path $runnerPath
        qualityPlanSha256 = $qualityPlan.MatrixSha256
        startedWorktreeFingerprint = $startedFingerprint
        worktreeFingerprint = $completedFingerprint
        worktreeStable = $worktreeStable
        overall = $overall
        repositoryHygiene = $repositoryHygiene
        planScope = $planScope
        worktreeChanges = Get-WorktreeChangeEvidence -Before $startedPathSnapshot -After $completedPathSnapshot
        controlPlaneOutputPaths = $controlPlaneOutputPaths
        modules = $moduleResults
    }
    $json = $artifact | ConvertTo-Json -Depth 12
    $gateSchema = Get-Content -LiteralPath $gateSchemaPath -Raw
    if (-not ($json | Test-Json -Schema $gateSchema -ErrorAction Stop)) { throw 'Generated quality-gate evidence failed schema validation.' }

    $outputDirectory = Split-Path -Parent $outputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
    $temporaryPath = $outputPath + '.tmp'
    try {
        Set-Content -LiteralPath $temporaryPath -Value $json -Encoding utf8
        Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
    Write-Output $json
    if ($overall -eq 'PASS') { exit 0 }
    if ($overall -eq 'INCOMPLETE_CONFIGURATION') { exit 2 }
    if ($overall -in @('BLOCKED_REPOSITORY_HYGIENE', 'CONTROL_PLANE_OUTPUT', 'PLAN_INVALIDATED')) { exit 4 }
    exit 1
}
catch {
    Write-Error $_
    exit 3
}
