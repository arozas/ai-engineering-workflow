[CmdletBinding()]
param(
    [string]$ProjectPath = '.ai/project.json',
    [string]$SchemaPath = '.ai/project.schema.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to validate repository-relative module paths.' }
$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'Project validation requires an initialized Git repository.'
}
$repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot.Trim()).TrimEnd('\', '/')

function Resolve-RepositoryFile([string]$Path, [string]$Description) {
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repositoryRoot $Path }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if ($resolved -ne $repositoryRoot -and
        -not $resolved.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description is outside the repository: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Description not found: $resolved" }
    return $resolved
}

$resolvedProjectPath = Resolve-RepositoryFile -Path $ProjectPath -Description 'Project configuration'
$resolvedSchemaPath = Resolve-RepositoryFile -Path $SchemaPath -Description 'Project schema'
$projectJson = Get-Content -LiteralPath $resolvedProjectPath -Raw
$schemaJson = Get-Content -LiteralPath $resolvedSchemaPath -Raw
if (-not ($projectJson | Test-Json -Schema $schemaJson -ErrorAction Stop)) {
    throw 'Project configuration does not validate against .ai/project.schema.json.'
}
$project = $projectJson | ConvertFrom-Json
$errors = @()
$moduleIds = @{}

foreach ($module in @($project.modules)) {
    if ($moduleIds.ContainsKey([string]$module.id)) { $errors += "Duplicate module ID: $($module.id)" }
    $moduleIds[[string]$module.id] = $true

    $modulePath = [string]$module.path
    if ([IO.Path]::IsPathRooted($modulePath)) {
        $errors += "Module '$($module.id)' path must be repository-relative: $modulePath"
    }
    else {
        $resolvedModule = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $modulePath))
        if ($resolvedModule -ne $repositoryRoot -and
            -not $resolvedModule.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            $errors += "Module '$($module.id)' path escapes the repository: $modulePath"
        }
        elseif (-not (Test-Path -LiteralPath $resolvedModule -PathType Container)) {
            $errors += "Module '$($module.id)' directory does not exist: $modulePath"
        }
    }

    foreach ($skillId in @($module.contextSkills)) {
        $skillPath = Join-Path $repositoryRoot ('.opencode\skills\' + [string]$skillId + '\SKILL.md')
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            $errors += "Module '$($module.id)' references missing context skill '$skillId'."
        }
    }

    foreach ($phase in @('restore', 'build', 'lint', 'typecheck', 'test', 'e2e')) {
        foreach ($command in @($module.quality.$phase)) {
            if ([string]$command -match '[\r\n]') {
                $errors += "Module '$($module.id)' phase '$phase' contains a multiline command."
            }
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Project validation failed with $($errors.Count) error(s)."
}

[ordered]@{
    verdict = 'PROJECT_VALID'
    projectPath = [IO.Path]::GetRelativePath($repositoryRoot, $resolvedProjectPath).Replace('\', '/')
    schemaPath = [IO.Path]::GetRelativePath($repositoryRoot, $resolvedSchemaPath).Replace('\', '/')
    projectName = [string]$project.name
    modules = @($project.modules | ForEach-Object { [string]$_.id })
} | ConvertTo-Json -Depth 4
exit 0
