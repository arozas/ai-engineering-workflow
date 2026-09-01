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
$referencedProjectSkills = @{}

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
        $skillName = [string]$skillId
        $skillPath = Join-Path $repositoryRoot ('.opencode\skills\' + $skillName + '\SKILL.md')
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            $errors += "Module '$($module.id)' references missing context skill '$skillId'."
        }
        else {
            $skillContent = Get-Content -LiteralPath $skillPath -Raw
            if ($skillContent -notmatch ('(?m)^name:\s*' + [regex]::Escape($skillName) + '\s*$')) {
                $errors += "Context skill '$skillName' frontmatter name does not match its directory."
            }
        }
        if ($skillName -match '^project-') { $referencedProjectSkills[$skillName] = [string]$module.id }
    }

    foreach ($phase in @('restore', 'build', 'lint', 'typecheck', 'test', 'e2e')) {
        foreach ($command in @($module.quality.$phase)) {
            if ([string]$command -match '[\r\n]') {
                $errors += "Module '$($module.id)' phase '$phase' contains a multiline command."
            }
        }
    }
}

if ($project.PSObject.Properties.Name -contains 'profile') {
    try {
        $profilePath = Resolve-RepositoryFile -Path ([string]$project.profile.source) -Description 'Persisted project profile'
        $profileSchemaPath = Resolve-RepositoryFile -Path '.ai/project-profile.schema.json' -Description 'Project profile schema'
        $profileJson = Get-Content -LiteralPath $profilePath -Raw
        $profileSchemaJson = Get-Content -LiteralPath $profileSchemaPath -Raw
        if (-not ($profileJson | Test-Json -Schema $profileSchemaJson -ErrorAction Stop)) {
            $errors += 'Persisted project profile does not validate against its schema.'
        }
        $profile = $profileJson | ConvertFrom-Json
        if ([string]$profile.structureFingerprint -ne [string]$project.profile.repositoryFingerprint) {
            $errors += 'Project configuration fingerprint does not match .ai/project-profile.json.'
        }

        $profilerPath = Resolve-RepositoryFile -Path '.ai/scripts/profile-project.ps1' -Description 'Project profiler'
        $freshProfileOutput = @(& $profilerPath)
        if ($LASTEXITCODE -ne 0) { $errors += 'Unable to calculate the current repository profile.' }
        else {
            $freshProfile = ($freshProfileOutput -join "`n") | ConvertFrom-Json
            if ([string]$freshProfile.structureFingerprint -ne [string]$profile.structureFingerprint) {
                $errors += 'Repository structure has drifted from the approved profile; run /ai-refresh.'
            }
        }

        $generatedManifestPath = Resolve-RepositoryFile -Path ([string]$project.profile.generatedSkillsManifest) -Description 'Generated skills manifest'
        $generatedSchemaPath = Resolve-RepositoryFile -Path '.ai/generated-skills.schema.json' -Description 'Generated skills schema'
        $generatedJson = Get-Content -LiteralPath $generatedManifestPath -Raw
        $generatedSchemaJson = Get-Content -LiteralPath $generatedSchemaPath -Raw
        if (-not ($generatedJson | Test-Json -Schema $generatedSchemaJson -ErrorAction Stop)) {
            $errors += 'Generated skills manifest does not validate against its schema.'
        }
        $generated = $generatedJson | ConvertFrom-Json
        if ([string]$generated.repositoryFingerprint -ne [string]$profile.structureFingerprint) {
            $errors += 'Generated skills manifest fingerprint does not match the persisted profile.'
        }

        $generatedIds = @{}
        foreach ($record in @($generated.skills)) {
            $id = [string]$record.id
            if ($generatedIds.ContainsKey($id)) { $errors += "Duplicate generated skill ID: $id" }
            $generatedIds[$id] = $true
            if (-not $moduleIds.ContainsKey([string]$record.moduleId)) {
                $errors += "Generated skill '$id' references unknown module '$($record.moduleId)'."
            }
            if (-not $referencedProjectSkills.ContainsKey($id) -or $referencedProjectSkills[$id] -ne [string]$record.moduleId) {
                $errors += "Generated skill '$id' is not referenced by its declared module."
            }

            $expectedPath = ".opencode/skills/$id/SKILL.md"
            if ([string]$record.path -ne $expectedPath) { $errors += "Generated skill '$id' must use path '$expectedPath'." }
            $generatedSkillPath = Resolve-RepositoryFile -Path $expectedPath -Description "Generated skill '$id'"
            $generatedSkillContent = Get-Content -LiteralPath $generatedSkillPath -Raw
            foreach ($heading in @('## Scope', '## Evidence', '## Rules', '## Quality and testing', '## Unknowns')) {
                if ($generatedSkillContent -notmatch ('(?m)^' + [regex]::Escape($heading) + '\s*$')) {
                    $errors += "Generated skill '$id' is missing required section '$heading'."
                }
            }
            foreach ($evidence in @($record.evidence)) {
                try { Resolve-RepositoryFile -Path ([string]$evidence.path) -Description "Evidence for generated skill '$id'" | Out-Null }
                catch { $errors += $_.Exception.Message }
            }
        }
        foreach ($id in $referencedProjectSkills.Keys) {
            if (-not $generatedIds.ContainsKey($id)) { $errors += "Project skill '$id' is missing from .ai/generated-skills.json." }
        }
    }
    catch {
        $errors += $_.Exception.Message
    }
}
elseif ($referencedProjectSkills.Count -gt 0) {
    $errors += 'Project-specific skills require the profile block and generated-skills manifest.'
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
    profileFingerprint = if ($project.PSObject.Properties.Name -contains 'profile') { [string]$project.profile.repositoryFingerprint } else { $null }
} | ConvertTo-Json -Depth 4
exit 0
