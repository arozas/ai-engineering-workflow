[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$RunId,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 900,
    [switch]$ContinueAfterFailure
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

function Get-QualityPlan([object]$Project, [string[]]$AffectedModuleIds, [string]$ProjectPath) {
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
        ProjectSha256 = Get-FileSha256 -Path $ProjectPath
        MatrixSha256 = Get-StringSha256 -Value $matrixJson
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
    $gateSchemaPath = Join-Path $repositoryRoot '.ai\quality-gates.schema.json'
    $runSchemaPath = Join-Path $repositoryRoot '.ai\workflow-run.schema.json'
    $statePath = Join-Path $repositoryRoot ".ai\runs\$RunId\state.json"
    $outputPath = Join-Path $repositoryRoot ".ai\runtime\$RunId\gates.json"
    $runnerPath = $MyInvocation.MyCommand.Path

    foreach ($requiredPath in @($projectPath, $projectSchemaPath, $gateSchemaPath, $runSchemaPath, $statePath, $runnerPath)) {
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
    $qualityPlan = Get-QualityPlan -Project $project -AffectedModuleIds @($state.qualityPlan.affectedModuleIds) -ProjectPath $projectPath
    if ([string]$state.qualityPlan.projectSha256 -ne $qualityPlan.ProjectSha256 -or
        [string]$state.qualityPlan.matrixSha256 -ne $qualityPlan.MatrixSha256) {
        throw "Run '$RunId' quality plan is stale or does not match .ai/project.json."
    }

    $generatedAt = [DateTime]::UtcNow.ToString('o')
    $startedFingerprint = Get-WorktreeFingerprint -RepositoryRoot $repositoryRoot
    $moduleResults = @()
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
    $worktreeStable = $startedFingerprint -eq $completedFingerprint
    $overall = if (-not $worktreeStable -or @($moduleResults | Where-Object { $_.overall -eq 'FAIL' }).Count -gt 0) {
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
    exit 1
}
catch {
    Write-Error $_
    exit 3
}
