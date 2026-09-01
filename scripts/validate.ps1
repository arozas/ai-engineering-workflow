[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Workflow.Common.ps1')

$workflowRoot = Get-WorkflowRoot
$manifest = Get-WorkflowManifest
$version = Get-WorkflowVersion
$errors = @()

if ($manifest.version -ne $version) {
    $errors += "VERSION ($version) does not match workflow.manifest.json ($($manifest.version))."
}

foreach ($forbidden in @('AGENTS.md', 'opencode.json', '.ai', '.opencode')) {
    if (Test-Path -LiteralPath (Join-Path $workflowRoot $forbidden)) {
        $errors += "Distribution root must not contain active project configuration: $forbidden"
    }
}

foreach ($required in @(
    'template\AGENTS.md',
    'template\opencode.json',
    'template\.ai\project.schema.json',
    'template\.ai\bootstrap-input.schema.json',
    'template\.ai\workflow-installation.schema.json',
    'template\.ai\pull-request-template.md',
    'template\.ai\scripts\validate-commit-message.ps1',
    'template\.ai\scripts\commit-approved.ps1',
    'template\.ai\scripts\publish-approved.ps1',
    'template\.ai\scripts\create-draft-pr.ps1',
    'template\.opencode\agents\orchestrator.md',
    'template\.opencode\agents\delivery.md',
    'template\.opencode\commands\ai-bootstrap.md',
    'template\.opencode\commands\commit.md',
    'template\.opencode\commands\pr-create.md',
    'template\.opencode\skills\repo-bootstrap\SKILL.md'
    '.github\pull_request_template.md'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $workflowRoot $required) -PathType Leaf)) {
        $errors += "Missing required file: $required"
    }
}

foreach ($jsonFile in Get-ChildItem -LiteralPath $workflowRoot -Recurse -File -Filter '*.json') {
    try {
        Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        $errors += "Invalid JSON: $(Get-NormalizedRelativePath -Root $workflowRoot -Path $jsonFile.FullName)"
    }
}

foreach ($scriptRoot in @('scripts', 'template\.ai\scripts')) {
    foreach ($scriptFile in Get-ChildItem -LiteralPath (Join-Path $workflowRoot $scriptRoot) -File -Filter '*.ps1') {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($parseError in @($parseErrors)) {
            $errors += "PowerShell parse error in $(Get-NormalizedRelativePath -Root $workflowRoot -Path $scriptFile.FullName): $($parseError.Message)"
        }
    }
}

$repositoryPrTemplate = Join-Path $workflowRoot '.github\pull_request_template.md'
$consumerPrTemplate = Join-Path $workflowRoot 'template\.ai\pull-request-template.md'
if ((Test-Path -LiteralPath $repositoryPrTemplate) -and (Test-Path -LiteralPath $consumerPrTemplate)) {
    if ((Get-FileSha256 -Path $repositoryPrTemplate) -ne (Get-FileSha256 -Path $consumerPrTemplate)) {
        $errors += 'Repository and consumer pull-request templates must remain identical.'
    }
}

$skillsRoot = Join-Path $workflowRoot 'template\.opencode\skills'
if (Test-Path -LiteralPath $skillsRoot) {
    foreach ($skillDirectory in Get-ChildItem -LiteralPath $skillsRoot -Directory) {
        $skillFile = Join-Path $skillDirectory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            $errors += "Missing SKILL.md: $($skillDirectory.Name)"
            continue
        }
        $nameLine = Get-Content -LiteralPath $skillFile | Where-Object { $_ -match '^name:\s+' } | Select-Object -First 1
        if ($nameLine -ne ('name: ' + $skillDirectory.Name)) {
            $errors += "Skill name mismatch: $($skillDirectory.Name)"
        }
    }
}

foreach ($definitionRoot in @('template\.opencode\agents', 'template\.opencode\commands')) {
    $fullRoot = Join-Path $workflowRoot $definitionRoot
    foreach ($definition in Get-ChildItem -LiteralPath $fullRoot -File -Filter '*.md') {
        $lines = @(Get-Content -LiteralPath $definition.FullName)
        if ($lines.Count -lt 4 -or $lines[0] -ne '---' -or @($lines | Where-Object { $_ -eq '---' }).Count -lt 2) {
            $errors += "Invalid frontmatter: $(Get-NormalizedRelativePath -Root $workflowRoot -Path $definition.FullName)"
        }
    }
}

$projectPresetsRoot = Join-Path $workflowRoot $manifest.projectPresetsPath
$stackPresetsRoot = Join-Path $workflowRoot $manifest.stackPresetsPath
$architecturePresetsRoot = Join-Path $workflowRoot $manifest.architecturePresetsPath
$stackIds = @{}
foreach ($stackFile in Get-ChildItem -LiteralPath $stackPresetsRoot -File -Filter '*.json') {
    $stack = Get-Content -LiteralPath $stackFile.FullName -Raw | ConvertFrom-Json
    if ($stack.id -ne $stackFile.BaseName) {
        $errors += "Stack preset ID mismatch: $($stackFile.Name)"
    }
    if ($stackIds.ContainsKey([string]$stack.id)) {
        $errors += "Duplicate stack preset ID: $($stack.id)"
    }
    $stackIds[[string]$stack.id] = $true
}

foreach ($architectureFile in Get-ChildItem -LiteralPath $architecturePresetsRoot -File -Filter '*.json') {
    $architecture = Get-Content -LiteralPath $architectureFile.FullName -Raw | ConvertFrom-Json
    if ($architecture.id -ne $architectureFile.BaseName) {
        $errors += "Architecture preset ID mismatch: $($architectureFile.Name)"
    }
}

foreach ($presetDirectory in Get-ChildItem -LiteralPath $projectPresetsRoot -Directory) {
    $presetFile = Join-Path $presetDirectory.FullName 'preset.json'
    if (-not (Test-Path -LiteralPath $presetFile -PathType Leaf)) {
        $errors += "Missing preset.json: $($presetDirectory.Name)"
        continue
    }
    $preset = Get-Content -LiteralPath $presetFile -Raw | ConvertFrom-Json
    if ($preset.id -ne $presetDirectory.Name) {
        $errors += "Project preset ID mismatch: $($presetDirectory.Name)"
    }
    foreach ($stackId in @($preset.stacks)) {
        if (-not $stackIds.ContainsKey([string]$stackId)) {
            $errors += "Project preset '$($preset.id)' references unknown stack '$stackId'."
        }
    }
}

$templateFiles = @(Get-TemplateFileRecords)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Distribution validation failed with $($errors.Count) error(s)."
}

Write-Host 'Distribution validation passed.'
Write-Host "Version: $version"
Write-Host "Template files: $($templateFiles.Count)"
Write-Host "Agents: $(@(Get-ChildItem -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents') -File -Filter '*.md').Count)"
Write-Host "Commands: $(@(Get-ChildItem -LiteralPath (Join-Path $workflowRoot 'template\.opencode\commands') -File -Filter '*.md').Count)"
Write-Host "Skills: $(@(Get-ChildItem -LiteralPath $skillsRoot -Directory).Count)"
Write-Host "Project presets: $(@(Get-ChildItem -LiteralPath $projectPresetsRoot -Directory).Count)"
Write-Host "Stack profiles: $(@(Get-ChildItem -LiteralPath $stackPresetsRoot -File -Filter '*.json').Count)"
Write-Host "Architecture presets: $(@(Get-ChildItem -LiteralPath $architecturePresetsRoot -File -Filter '*.json').Count)"
