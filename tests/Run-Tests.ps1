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

try {
    New-Item -ItemType Directory -Path $repositoryRoot -Force | Out-Null
    & git -C $repositoryRoot init -b main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize test repository.' }
    & git -C $repositoryRoot config user.email 'workflow-tests@example.invalid'
    & git -C $repositoryRoot config user.name 'Workflow Tests'

    $sourceRoot = Join-Path $repositoryRoot 'src\app'
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceRoot 'app.txt') -Value 'before' -Encoding utf8
    & git -C $repositoryRoot add -- 'src/app/app.txt'
    & git -C $repositoryRoot commit -m 'test: create fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to commit test fixture.' }

    Invoke-PowerShell -ScriptPath (Join-Path $distributionRoot 'scripts\validate.ps1') -Arguments @() | Out-Null
    Assert-True -Condition $true -Message 'Distribution validation runs.'

    Invoke-PowerShell -ScriptPath (Join-Path $distributionRoot 'scripts\install.ps1') -Arguments @('-TargetPath', $repositoryRoot, '-Mode', 'Local') | Out-Null
    Assert-True -Condition (@(& git -C $repositoryRoot status --porcelain).Count -eq 0) -Message 'Local installation remains invisible to Git.'
    $metadata = Get-Content -LiteralPath (Join-Path $repositoryRoot '.ai\workflow-installation.json') -Raw | ConvertFrom-Json
    Assert-True -Condition ($metadata.workflowVersion -eq '1.4.0') -Message 'Installed metadata records version 1.4.0.'

    $project = [ordered]@{
        '$schema' = './project.schema.json'
        version = 1
        name = 'workflow-test-consumer'
        fastPath = [ordered]@{ enabled = $true; maximumFiles = 3; maximumLines = 120; maximumProductionFilesForDiagnosis = 2; maximumTestFilesForDiagnosis = 2; maximumCorrectionIterations = 1 }
        review = [ordered]@{ maxIterations = 2; diffBudget = [ordered]@{ filesMultiplier = 2; linesMultiplier = 3 } }
        modules = @([ordered]@{
            id = 'app'
            path = 'src/app'
            languages = @('text')
            frameworks = @()
            architectures = @()
            contextSkills = @()
            quality = [ordered]@{ restore = @(); build = @(); lint = @(); typecheck = @(); test = @('pwsh -NoProfile -Command "exit 0"'); e2e = @() }
        })
    }
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repositoryRoot '.ai\project.json') -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-project.ps1') -Arguments @() -WorkingDirectory $repositoryRoot | Out-Null
    Assert-True -Condition $true -Message 'A valid project configuration passes deterministic schema validation.'

    $invalidProjectPath = Join-Path $repositoryRoot '.ai\invalid-project.json'
    $invalid = ($project | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable)
    $invalid.modules[0].path = '../outside'
    $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidProjectPath -Encoding utf8
    Invoke-PowerShell -ScriptPath (Join-Path $repositoryRoot '.ai\scripts\validate-project.ps1') -Arguments @('-ProjectPath', '.ai/invalid-project.json') -ExpectedExitCode 1 -WorkingDirectory $repositoryRoot | Out-Null
    Remove-Item -LiteralPath $invalidProjectPath -Force
    Assert-True -Condition $true -Message 'A module path escaping the repository is rejected.'

    $runtimeRoot = Join-Path $repositoryRoot '.ai\runtime'
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $runtimeRoot 'requirement.md') -Value 'Change the fixture text.' -Encoding utf8
    $stateScript = Join-Path $repositoryRoot '.ai\scripts\workflow-state.ps1'
    $runId = 'quick-fixture-change'
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Start', '-RunId', $runId, '-WorkflowPath', 'fast-path', '-TaskType', 'QuickFix', '-ArtifactPath', '.ai/runtime/requirement.md') -WorkingDirectory $repositoryRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $runtimeRoot 'plan.md') -Value 'Change src/app/app.txt and verify its content.' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'ApprovePlan', '-RunId', $runId, '-ArtifactPath', '.ai/runtime/plan.md') -WorkingDirectory $repositoryRoot | Out-Null
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'BeginImplementation', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceRoot 'app.txt') -Value 'after' -Encoding utf8

    $classifier = Join-Path $repositoryRoot '.ai\scripts\fast-path-check.ps1'
    $classification = Invoke-PowerShell -ScriptPath $classifier -Arguments @('-TaskType', 'QuickFix', '-Phase', 'Actual', '-BaseRef', 'HEAD', '-AcceptanceClear', '-RootCauseKnown', '-VerificationAvailable') -WorkingDirectory $repositoryRoot
    $classificationJson = ($classification -join "`n") | ConvertFrom-Json
    Assert-True -Condition ($classificationJson.verdict -eq 'FAST_PATH_ELIGIBLE' -and $classificationJson.observed.fileCount -eq 1 -and $classificationJson.observed.moduleCount -eq 1) -Message 'Actual fast-path scope is derived from Git and module configuration.'

    Set-Content -LiteralPath (Join-Path $runtimeRoot 'gates.json') -Value '{"overall":"PASS"}' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordGates', '-RunId', $runId, '-ArtifactPath', '.ai/runtime/gates.json', '-Verdict', 'PASS') -WorkingDirectory $repositoryRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $runtimeRoot 'review.md') -Value 'FAST REVIEW PASS' -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordReview', '-RunId', $runId, '-ArtifactPath', '.ai/runtime/review.md', '-Verdict', 'PASS') -WorkingDirectory $repositoryRoot | Out-Null
    $ready = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Validate', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($ready.status -eq 'READY_FOR_DELIVERY') -Message 'Approved plan, gates, and review reach READY_FOR_DELIVERY.'

    & git -C $repositoryRoot add -- 'src/app/app.txt'
    & git -C $repositoryRoot commit -m 'test: update fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create state-machine test commit.' }
    $commitSha = (& git -C $repositoryRoot rev-parse HEAD).Trim()
    Set-Content -LiteralPath (Join-Path $runtimeRoot 'commit.json') -Value ('{"sha":"' + $commitSha + '"}') -Encoding utf8
    Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'RecordCommit', '-RunId', $runId, '-ArtifactPath', '.ai/runtime/commit.json') -WorkingDirectory $repositoryRoot | Out-Null
    $committed = (Invoke-PowerShell -ScriptPath $stateScript -Arguments @('-Action', 'Show', '-RunId', $runId) -WorkingDirectory $repositoryRoot | Out-String) | ConvertFrom-Json
    Assert-True -Condition ($committed.status -eq 'COMMITTED' -and $committed.currentSha -eq $commitSha) -Message 'Only the exact reviewed diff can be recorded as committed.'

    Set-Content -LiteralPath (Join-Path $repositoryRoot 'package.json') -Value '{"name":"risk"}' -Encoding utf8
    Invoke-PowerShell -ScriptPath $classifier -Arguments @('-TaskType', 'SmallTask', '-Phase', 'Actual', '-BaseRef', 'HEAD', '-AcceptanceClear', '-VerificationAvailable') -ExpectedExitCode 3 -WorkingDirectory $repositoryRoot | Out-Null
    Remove-Item -LiteralPath (Join-Path $repositoryRoot 'package.json') -Force
    Assert-True -Condition $true -Message 'Dependency manifest changes escalate from the fast path.'

    $reviewer = Get-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\agents\reviewer.md') -Raw
    $quickReviewer = Get-Content -LiteralPath (Join-Path $repositoryRoot '.opencode\agents\quick-reviewer.md') -Raw
    Assert-True -Condition ($reviewer -notmatch 'resource:\s*"git ' -and $quickReviewer -notmatch 'resource:\s*"git ') -Message 'Review agents expose no shell exceptions.'

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
