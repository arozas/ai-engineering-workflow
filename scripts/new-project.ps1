[CmdletBinding()]
param(
    [string]$Name,
    [string]$ParentPath,
    [string]$Preset = 'empty',
    [string]$Architecture,
    [switch]$InitializeGit,
    [switch]$DryRun,
    [switch]$ListPresets
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Workflow.Common.ps1')

$workflowRoot = Get-WorkflowRoot
$manifest = Get-WorkflowManifest
$projectPresetsRoot = Join-Path $workflowRoot $manifest.projectPresetsPath
$stackPresetsRoot = Join-Path $workflowRoot $manifest.stackPresetsPath
$architecturePresetsRoot = Join-Path $workflowRoot $manifest.architecturePresetsPath

if ($ListPresets) {
    Write-Host 'Project presets:'
    Get-ChildItem -LiteralPath $projectPresetsRoot -Directory | Sort-Object Name | ForEach-Object {
        $presetFile = Join-Path $_.FullName 'preset.json'
        if (Test-Path -LiteralPath $presetFile) {
            $item = Get-Content -LiteralPath $presetFile -Raw | ConvertFrom-Json
            Write-Host "  $($item.id) - $($item.description)"
        }
    }
    Write-Host 'Stack profiles:'
    Get-ChildItem -LiteralPath $stackPresetsRoot -File -Filter '*.json' | Sort-Object Name | ForEach-Object {
        $item = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        Write-Host "  $($item.id) - $($item.description)"
    }
    Write-Host 'Architecture presets:'
    Get-ChildItem -LiteralPath $architecturePresetsRoot -File -Filter '*.json' | Sort-Object Name | ForEach-Object {
        $item = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        Write-Host "  $($item.id) - $($item.description)"
    }
    return
}

if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($ParentPath)) {
    throw 'Name and ParentPath are required unless ListPresets is used.'
}
if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw 'Name may contain only letters, numbers, dot, underscore, and hyphen, and must start with a letter or number.'
}

$parentFull = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $parentFull -PathType Container)) {
    throw "Parent directory does not exist: $parentFull"
}
$targetRoot = Resolve-WorkflowTarget -TargetPath (Join-Path $parentFull $Name)
if (Test-Path -LiteralPath $targetRoot) {
    throw "Target already exists: $targetRoot"
}

$presetRoot = Join-Path $projectPresetsRoot $Preset
$presetFile = Join-Path $presetRoot 'preset.json'
if (-not (Test-Path -LiteralPath $presetFile -PathType Leaf)) {
    throw "Unknown project preset '$Preset'. Run with -ListPresets."
}
$presetDefinition = Get-Content -LiteralPath $presetFile -Raw | ConvertFrom-Json
if ($presetDefinition.id -ne $Preset) {
    throw "Preset ID does not match its directory: $Preset"
}

$architectureDefinition = $null
if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
    $architectureFile = Join-Path $architecturePresetsRoot ($Architecture + '.json')
    if (-not (Test-Path -LiteralPath $architectureFile -PathType Leaf)) {
        throw "Unknown architecture preset '$Architecture'. Run with -ListPresets."
    }
    $architectureDefinition = Get-Content -LiteralPath $architectureFile -Raw | ConvertFrom-Json
}

$packageName = $Name.ToLowerInvariant() -replace '[^a-z0-9._-]', '-'
$pythonPackage = $packageName.Replace('-', '_').Replace('.', '_')
$tokens = @{
    name = $Name
    packageName = $packageName
    pythonPackage = $pythonPackage
    target = $targetRoot
    parent = $parentFull
}

Write-Host "Project: $Name"
Write-Host "Target: $targetRoot"
Write-Host "Preset: $Preset"
Write-Host "Architecture: $(if ($architectureDefinition) { $architectureDefinition.id } else { 'not specified' })"
if ($presetDefinition.networkRequired) {
    Write-Host 'Network: required by this preset'
}

if ($DryRun) {
    Write-Host 'DRY RUN: target is available and preset validation passed.'
    foreach ($command in @($presetDefinition.commands)) {
        $arguments = @($command.arguments | ForEach-Object { Expand-WorkflowTokens -Value $_ -Tokens $tokens })
        Write-Host ('  ' + $command.executable + ' ' + ($arguments -join ' '))
    }
    return
}

New-Item -ItemType Directory -Path $targetRoot | Out-Null

$presetFilesRoot = Join-Path $presetRoot 'files'
if (Test-Path -LiteralPath $presetFilesRoot -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $presetFilesRoot -Recurse -File) {
        $relative = Get-NormalizedRelativePath -Root $presetFilesRoot -Path $file.FullName
        $expandedRelative = Expand-WorkflowTokens -Value $relative -Tokens $tokens
        $destination = Join-Path $targetRoot (ConvertTo-NativeRelativePath -RelativePath $expandedRelative)
        $destinationDirectory = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }
        $content = Get-Content -LiteralPath $file.FullName -Raw
        Expand-WorkflowTokens -Value $content -Tokens $tokens | Set-Content -LiteralPath $destination -Encoding utf8
    }
}

foreach ($command in @($presetDefinition.commands)) {
    $resolvedCommand = Get-Command $command.executable -ErrorAction SilentlyContinue
    if ($null -eq $resolvedCommand) {
        throw "Required command not found for preset '$Preset': $($command.executable). The partial project was left at $targetRoot"
    }
    $arguments = @($command.arguments | ForEach-Object { Expand-WorkflowTokens -Value $_ -Tokens $tokens })
    $workingDirectory = Expand-WorkflowTokens -Value $command.workingDirectory -Tokens $tokens
    $savedEnvironment = @{}
    try {
        if ($command.PSObject.Properties.Name -contains 'environment') {
            foreach ($property in $command.environment.PSObject.Properties) {
                $savedEnvironment[$property.Name] = [Environment]::GetEnvironmentVariable($property.Name, 'Process')
                [Environment]::SetEnvironmentVariable($property.Name, [string]$property.Value, 'Process')
            }
        }
        Push-Location -LiteralPath $workingDirectory
        try {
            & $resolvedCommand.Source @arguments
            if ($LASTEXITCODE -ne 0) {
                throw "Preset command failed with exit code $($LASTEXITCODE): $($command.executable)"
            }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        foreach ($key in $savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
        }
    }
}

& (Join-Path $PSScriptRoot 'install.ps1') -TargetPath $targetRoot

$bootstrapInput = [ordered]@{
    '$schema' = './bootstrap-input.schema.json'
    version = 1
    projectName = $Name
    projectPreset = $Preset
    requestedStacks = @($presetDefinition.stacks)
    requestedArchitectures = @(if ($architectureDefinition) { $architectureDefinition.id })
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
}
$bootstrapInput | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $targetRoot '.ai\bootstrap-input.json') -Encoding utf8

if ($InitializeGit) {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw "Git was requested but is not installed. The project is otherwise ready at $targetRoot"
    }
    & $gitCommand.Source -C $targetRoot init -b main
    if ($LASTEXITCODE -ne 0) {
        throw "Git initialization failed. The project is otherwise ready at $targetRoot"
    }
}

Write-Host "Project created: $targetRoot"
if ($Preset -eq 'empty') {
    Write-Host 'Note: the empty preset has no application module; add source/build evidence before /ai-bootstrap.'
}
Write-Host 'Next:'
Write-Host "  cd `"$targetRoot`""
Write-Host '  opencode2'
Write-Host '  /ai-bootstrap'
