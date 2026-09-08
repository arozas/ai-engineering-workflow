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
    foreach ($group in $records | Group-Object WorkflowPath | Sort-Object Name) {
        $items = @($group.Group)
        [pscustomobject]@{
            WorkflowPath = $group.Name
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

$lines = @(
    "# Benchmark summary: $($benchmark.suiteName)",
    '',
    "Runs: $($records.Count)",
    '',
    '| Workflow path | Runs | Avg. tokens | Avg. cost USD | Avg. seconds | Avg. corrections | Avg. tool calls | Avg. delegations | Duplicate calls | Protocol violations | Step-limit runs | Success rate | Escaped defects |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
)
foreach ($row in $summary) {
    $lines += "| $($row.WorkflowPath) | $($row.Runs) | $($row.AverageTokens) | $($row.AverageCostUsd) | $($row.AverageDurationSeconds) | $($row.AverageCorrections) | $($row.AverageToolCalls) | $($row.AverageDelegations) | $($row.DuplicateToolCalls) | $($row.ProtocolViolations) | $($row.StepLimitRuns) | $($row.SuccessRatePercent)% | $($row.EscapedDefects) |"
}

$standard = $summary | Where-Object WorkflowPath -eq 'standard' | Select-Object -First 1
$fast = $summary | Where-Object WorkflowPath -eq 'fast-path' | Select-Object -First 1
if ($null -ne $standard -and $null -ne $fast -and $standard.AverageTokens -gt 0) {
    $savings = [Math]::Round((1 - ($fast.AverageTokens / $standard.AverageTokens)) * 100, 1)
    $lines += @('', "Fast-path average token change versus standard: $savings% savings.")
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
