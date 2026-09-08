[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [string]$SchemaPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$distributionRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $distributionRoot 'evaluations\benchmark.schema.json'
}
$resolvedInput = [IO.Path]::GetFullPath($InputPath)
$resolvedSchema = [IO.Path]::GetFullPath($SchemaPath)
if (-not (Test-Path -LiteralPath $resolvedInput -PathType Leaf)) { throw "Benchmark input not found: $resolvedInput" }
if (-not (Test-Path -LiteralPath $resolvedSchema -PathType Leaf)) { throw "Benchmark schema not found: $resolvedSchema" }

$inputJson = Get-Content -LiteralPath $resolvedInput -Raw
$schemaJson = Get-Content -LiteralPath $resolvedSchema -Raw
if (-not ($inputJson | Test-Json -Schema $schemaJson -ErrorAction Stop)) {
    throw 'Benchmark input does not validate against evaluations/benchmark.schema.json.'
}
$benchmark = $inputJson | ConvertFrom-Json
$records = @(
    foreach ($scenario in $benchmark.scenarios) {
        foreach ($run in $scenario.runs) {
            [pscustomobject]@{
                Scenario = [string]$scenario.id
                Category = [string]$scenario.category
                WorkflowPath = [string]$run.workflowPath
                ModelProfile = [string]$run.modelProfile
                TotalTokens = [int64]$run.inputTokens + [int64]$run.outputTokens
                CostUsd = [double]$run.costUsd
                DurationSeconds = [double]$run.durationSeconds
                CorrectionCycles = [int]$run.correctionCycles
                ToolCalls = if ($run.PSObject.Properties.Name -contains 'toolCalls') { [int]$run.toolCalls } else { 0 }
                DuplicateToolCalls = if ($run.PSObject.Properties.Name -contains 'duplicateToolCalls') { [int]$run.duplicateToolCalls } else { 0 }
                SubagentDelegations = if ($run.PSObject.Properties.Name -contains 'subagentDelegations') { [int]$run.subagentDelegations } else { 0 }
                ProtocolViolations = if ($run.PSObject.Properties.Name -contains 'protocolViolations') { [int]$run.protocolViolations } else { 0 }
                StepLimitReached = if ($run.PSObject.Properties.Name -contains 'stepLimitReached') { [bool]$run.stepLimitReached } else { $false }
                Passed = [string]$run.result -eq 'PASS'
                EscapedDefects = [int]$run.escapedDefects
            }
        }
    }
)
if ($records.Count -eq 0) { throw 'Benchmark contains no runs.' }

$summary = @(
    foreach ($group in $records | Group-Object ModelProfile, WorkflowPath | Sort-Object Name) {
        $items = @($group.Group)
        [pscustomobject]@{
            ModelProfile = [string]$items[0].ModelProfile
            WorkflowPath = [string]$items[0].WorkflowPath
            Runs = $items.Count
            AverageTokens = [Math]::Round(($items.TotalTokens | Measure-Object -Average).Average, 0)
            AverageCostUsd = [Math]::Round(($items.CostUsd | Measure-Object -Average).Average, 4)
            AverageDurationSeconds = [Math]::Round(($items.DurationSeconds | Measure-Object -Average).Average, 1)
            AverageCorrections = [Math]::Round(($items.CorrectionCycles | Measure-Object -Average).Average, 2)
            AverageToolCalls = [Math]::Round(($items.ToolCalls | Measure-Object -Average).Average, 1)
            AverageDelegations = [Math]::Round(($items.SubagentDelegations | Measure-Object -Average).Average, 1)
            DuplicateToolCalls = ($items.DuplicateToolCalls | Measure-Object -Sum).Sum
            ProtocolViolations = ($items.ProtocolViolations | Measure-Object -Sum).Sum
            StepLimitRuns = @($items | Where-Object StepLimitReached).Count
            SuccessRatePercent = [Math]::Round((@($items | Where-Object Passed).Count / $items.Count) * 100, 1)
            EscapedDefects = ($items.EscapedDefects | Measure-Object -Sum).Sum
        }
    }
)

function Get-PairedComparisons {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$BaselinePath,
        [Parameter(Mandatory = $true)][string]$CandidatePath
    )

    $comparisons = @()
    foreach ($modelProfile in @($Records.ModelProfile | Sort-Object -Unique)) {
        $profileRecords = @($Records | Where-Object ModelProfile -eq $modelProfile)
        $baselineIds = @($profileRecords | Where-Object WorkflowPath -eq $BaselinePath | ForEach-Object Scenario | Sort-Object -Unique)
        $candidateIds = @($profileRecords | Where-Object WorkflowPath -eq $CandidatePath | ForEach-Object Scenario | Sort-Object -Unique)
        $pairedIds = @($baselineIds | Where-Object { $candidateIds -contains $_ })
        if ($pairedIds.Count -eq 0) { continue }

        $baselineTokens = @()
        $candidateTokens = @()
        $baselineCosts = @()
        $candidateCosts = @()
        foreach ($scenarioId in $pairedIds) {
            $baselineRuns = @($profileRecords | Where-Object { $_.Scenario -eq $scenarioId -and $_.WorkflowPath -eq $BaselinePath })
            $candidateRuns = @($profileRecords | Where-Object { $_.Scenario -eq $scenarioId -and $_.WorkflowPath -eq $CandidatePath })
            $baselineTokens += [double](($baselineRuns.TotalTokens | Measure-Object -Average).Average)
            $candidateTokens += [double](($candidateRuns.TotalTokens | Measure-Object -Average).Average)
            $baselineCosts += [double](($baselineRuns.CostUsd | Measure-Object -Average).Average)
            $candidateCosts += [double](($candidateRuns.CostUsd | Measure-Object -Average).Average)
        }

        $baselineAverageTokens = [double](($baselineTokens | Measure-Object -Average).Average)
        $candidateAverageTokens = [double](($candidateTokens | Measure-Object -Average).Average)
        $comparisons += [pscustomobject]@{
            ModelProfile = $modelProfile
            BaselinePath = $BaselinePath
            CandidatePath = $CandidatePath
            PairedScenarios = $pairedIds.Count
            BaselineAverageTokens = [Math]::Round($baselineAverageTokens, 0)
            CandidateAverageTokens = [Math]::Round($candidateAverageTokens, 0)
            TokenSavingsPercent = if ($baselineAverageTokens -gt 0) { [Math]::Round((1 - ($candidateAverageTokens / $baselineAverageTokens)) * 100, 1) } else { $null }
            BaselineAverageCostUsd = [Math]::Round((($baselineCosts | Measure-Object -Average).Average), 4)
            CandidateAverageCostUsd = [Math]::Round((($candidateCosts | Measure-Object -Average).Average), 4)
        }
    }
    return @($comparisons)
}

$lines = @(
    "# Benchmark summary: $($benchmark.suiteName)",
    '',
    "Runs: $($records.Count)",
    '',
    '| Model profile | Workflow path | Runs | Avg. tokens | Avg. cost USD | Avg. seconds | Avg. corrections | Avg. tool calls | Avg. delegations | Duplicate calls | Protocol violations | Step-limit runs | Success rate | Escaped defects |',
    '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
)
foreach ($row in $summary) {
    $lines += "| $($row.ModelProfile) | $($row.WorkflowPath) | $($row.Runs) | $($row.AverageTokens) | $($row.AverageCostUsd) | $($row.AverageDurationSeconds) | $($row.AverageCorrections) | $($row.AverageToolCalls) | $($row.AverageDelegations) | $($row.DuplicateToolCalls) | $($row.ProtocolViolations) | $($row.StepLimitRuns) | $($row.SuccessRatePercent)% | $($row.EscapedDefects) |"
}

$pairedComparisons = @(
    @(Get-PairedComparisons -Records $records -BaselinePath 'manual' -CandidatePath 'standard')
    @(Get-PairedComparisons -Records $records -BaselinePath 'standard' -CandidatePath 'fast-path')
)
if ($pairedComparisons.Count -gt 0) {
    $lines += @(
        '',
        '## Paired token comparisons',
        '',
        'Only identical scenario IDs within the same model profile are compared. Unpaired runs remain in the summary above but never influence these savings.',
        '',
        '| Model profile | Comparison | Paired scenarios | Baseline avg. tokens | Candidate avg. tokens | Token change | Baseline avg. cost USD | Candidate avg. cost USD |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |'
    )
    foreach ($comparison in $pairedComparisons) {
        $tokenChange = if ($null -eq $comparison.TokenSavingsPercent) { 'not comparable' } else { "$($comparison.TokenSavingsPercent)% savings" }
        $lines += "| $($comparison.ModelProfile) | $($comparison.CandidatePath) vs $($comparison.BaselinePath) | $($comparison.PairedScenarios) | $($comparison.BaselineAverageTokens) | $($comparison.CandidateAverageTokens) | $tokenChange | $($comparison.BaselineAverageCostUsd) | $($comparison.CandidateAverageCostUsd) |"
    }
}

$result = $lines -join [Environment]::NewLine
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        throw "Output directory does not exist: $outputDirectory"
    }
    Set-Content -LiteralPath $resolvedOutput -Value $result -Encoding utf8
    Write-Host "Wrote benchmark summary: $resolvedOutput"
}
else {
    $result
}
