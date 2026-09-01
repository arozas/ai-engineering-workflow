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
    '| Workflow path | Runs | Avg. tokens | Avg. cost USD | Avg. seconds | Avg. corrections | Success rate | Escaped defects |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
)
foreach ($row in $summary) {
    $lines += "| $($row.WorkflowPath) | $($row.Runs) | $($row.AverageTokens) | $($row.AverageCostUsd) | $($row.AverageDurationSeconds) | $($row.AverageCorrections) | $($row.SuccessRatePercent)% | $($row.EscapedDefects) |"
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
