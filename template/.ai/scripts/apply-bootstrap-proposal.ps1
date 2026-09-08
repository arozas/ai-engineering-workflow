[CmdletBinding()]
param(
    [string]$ProposalRoot = '.ai/bootstrap-proposal',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to apply a bootstrap proposal.' }

$repositoryRootOutput = @(& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or $repositoryRootOutput.Count -ne 1) {
    throw 'Bootstrap proposal application requires an initialized Git repository.'
}
$repositoryRoot = [IO.Path]::GetFullPath([string]$repositoryRootOutput[0]).TrimEnd('\', '/')

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [switch]$RequireFile,
        [switch]$RequireDirectory
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repositoryRoot $Path }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if ($resolved -ne $repositoryRoot -and
        -not $resolved.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description is outside the repository: $resolved"
    }
    if ($RequireFile -and -not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Description not found: $resolved"
    }
    if ($RequireDirectory -and -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "$Description not found: $resolved"
    }
    return $resolved
}

function Copy-FileCreatingParent {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Test-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$JsonPath,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $json = Get-Content -LiteralPath $JsonPath -Raw
    $schema = Get-Content -LiteralPath $SchemaPath -Raw
    if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) {
        throw "$Description does not validate against $([IO.Path]::GetRelativePath($repositoryRoot, $SchemaPath).Replace('\', '/'))."
    }
}

function Test-Rfc3339Timestamp($Value) {
    if ($Value -is [DateTime]) { $Value = $Value.ToString('o') }
    else { $Value = [string]$Value }
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$') { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)
}

$resolvedProposalRoot = Resolve-RepositoryPath -Path $ProposalRoot -Description 'Bootstrap proposal directory' -RequireDirectory
$proposalRelativeRoot = [IO.Path]::GetRelativePath($repositoryRoot, $resolvedProposalRoot).Replace('\', '/')
if ($proposalRelativeRoot -ne '.ai/bootstrap-proposal') {
    throw "Bootstrap proposals must be applied from .ai/bootstrap-proposal, not $proposalRelativeRoot."
}

$proposalProjectPath = Resolve-RepositoryPath -Path '.ai/bootstrap-proposal/project.json' -Description 'Proposed project configuration' -RequireFile
$proposalRulesPath = Resolve-RepositoryPath -Path '.ai/bootstrap-proposal/project-rules.md' -Description 'Proposed project rules' -RequireFile
$proposalGeneratedSkillsPath = Resolve-RepositoryPath -Path '.ai/bootstrap-proposal/generated-skills.json' -Description 'Proposed generated skills manifest' -RequireFile
$proposalProfilePath = Resolve-RepositoryPath -Path '.ai/bootstrap-proposal/project-profile.json' -Description 'Proposed project profile' -RequireFile

$projectSchemaPath = Resolve-RepositoryPath -Path '.ai/project.schema.json' -Description 'Project schema' -RequireFile
$generatedSkillsSchemaPath = Resolve-RepositoryPath -Path '.ai/generated-skills.schema.json' -Description 'Generated skills schema' -RequireFile
$profileSchemaPath = Resolve-RepositoryPath -Path '.ai/project-profile.schema.json' -Description 'Project profile schema' -RequireFile
$profilerPath = Resolve-RepositoryPath -Path '.ai/scripts/profile-project.ps1' -Description 'Project profiler' -RequireFile
$validatorPath = Resolve-RepositoryPath -Path '.ai/scripts/validate-project.ps1' -Description 'Project validator' -RequireFile

Test-JsonFile -JsonPath $proposalProjectPath -SchemaPath $projectSchemaPath -Description 'Proposed project configuration'
Test-JsonFile -JsonPath $proposalGeneratedSkillsPath -SchemaPath $generatedSkillsSchemaPath -Description 'Proposed generated skills manifest'
Test-JsonFile -JsonPath $proposalProfilePath -SchemaPath $profileSchemaPath -Description 'Proposed project profile'

$project = Get-Content -LiteralPath $proposalProjectPath -Raw | ConvertFrom-Json
$generatedSkills = Get-Content -LiteralPath $proposalGeneratedSkillsPath -Raw | ConvertFrom-Json
$proposalProfile = Get-Content -LiteralPath $proposalProfilePath -Raw | ConvertFrom-Json
$errors = @()

$projectAnalyzedAt = if ($project.PSObject.Properties.Name -contains 'profile') { $project.profile.analyzedAtUtc } else { '' }
foreach ($timestamp in @(
    [pscustomobject]@{ Name = 'project.profile.analyzedAtUtc'; Value = $projectAnalyzedAt },
    [pscustomobject]@{ Name = 'generated-skills.generatedAtUtc'; Value = $generatedSkills.generatedAtUtc },
    [pscustomobject]@{ Name = 'project-profile.scannedAtUtc'; Value = $proposalProfile.scannedAtUtc }
)) {
    if (-not (Test-Rfc3339Timestamp -Value $timestamp.Value)) {
        $errors += "$($timestamp.Name) must be an RFC 3339 timestamp."
    }
}

if (-not ($project.PSObject.Properties.Name -contains 'profile')) {
    $errors += 'Proposed project configuration must include a profile block.'
}
else {
    if ([string]$project.profile.repositoryFingerprint -ne [string]$proposalProfile.structureFingerprint) {
        $errors += 'Proposed project fingerprint does not match bootstrap-proposal/project-profile.json.'
    }
    if ([string]$generatedSkills.repositoryFingerprint -ne [string]$proposalProfile.structureFingerprint) {
        $errors += 'Proposed generated-skills fingerprint does not match bootstrap-proposal/project-profile.json.'
    }
}

$freshProfileOutput = @(& $profilerPath)
if ($LASTEXITCODE -ne 0) {
    $errors += 'Unable to calculate the current repository profile.'
}
else {
    try {
        $freshProfile = ($freshProfileOutput -join "`n") | ConvertFrom-Json
        if ([string]$freshProfile.structureFingerprint -ne [string]$proposalProfile.structureFingerprint) {
            $errors += 'Repository structure has drifted from the bootstrap proposal; rerun /ai-bootstrap.'
        }
    }
    catch {
        $errors += "Current repository profile is not valid JSON: $($_.Exception.Message)"
    }
}

$moduleIds = @{}
$referencedProjectSkills = @{}
foreach ($module in @($project.modules)) {
    $moduleId = [string]$module.id
    if ($moduleIds.ContainsKey($moduleId)) { $errors += "Duplicate module ID: $moduleId" }
    $moduleIds[$moduleId] = $true

    $modulePath = [string]$module.path
    if ([IO.Path]::IsPathRooted($modulePath)) {
        $errors += "Module '$moduleId' path must be repository-relative: $modulePath"
    }
    else {
        $resolvedModule = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $modulePath))
        if ($resolvedModule -ne $repositoryRoot -and
            -not $resolvedModule.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            $errors += "Module '$moduleId' path escapes the repository: $modulePath"
        }
        elseif (-not (Test-Path -LiteralPath $resolvedModule -PathType Container)) {
            $errors += "Module '$moduleId' directory does not exist: $modulePath"
        }
    }

    foreach ($skillId in @($module.contextSkills)) {
        $skillName = [string]$skillId
        if ($skillName -match '^project-') {
            $referencedProjectSkills[$skillName] = $moduleId
            continue
        }

        $builtInSkillPath = Join-Path $repositoryRoot ('.opencode\skills\' + $skillName + '\SKILL.md')
        if (-not (Test-Path -LiteralPath $builtInSkillPath -PathType Leaf)) {
            $errors += "Module '$moduleId' references missing built-in context skill '$skillName'."
        }
    }
}

$generatedIds = @{}
foreach ($record in @($generatedSkills.skills)) {
    $id = [string]$record.id
    $generatedIds[$id] = $true

    if (-not $moduleIds.ContainsKey([string]$record.moduleId)) {
        $errors += "Generated skill '$id' references unknown module '$($record.moduleId)'."
    }
    if (-not $referencedProjectSkills.ContainsKey($id) -or $referencedProjectSkills[$id] -ne [string]$record.moduleId) {
        $errors += "Generated skill '$id' is not referenced by its declared module."
    }

    $expectedFinalPath = ".opencode/skills/$id/SKILL.md"
    if ([string]$record.path -ne $expectedFinalPath) {
        $errors += "Generated skill '$id' must use path '$expectedFinalPath'."
    }

    $proposalSkillPath = Resolve-RepositoryPath -Path ".ai/bootstrap-proposal/skills/$id/SKILL.md" -Description "Proposed generated skill '$id'" -RequireFile
    $skillContent = Get-Content -LiteralPath $proposalSkillPath -Raw
    if ($skillContent -notmatch ('(?m)^name:\s*' + [regex]::Escape($id) + '\s*$')) {
        $errors += "Proposed generated skill '$id' frontmatter name does not match its directory."
    }
    foreach ($heading in @('## Scope', '## Evidence', '## Rules', '## Quality and testing', '## Unknowns')) {
        if ($skillContent -notmatch ('(?m)^' + [regex]::Escape($heading) + '\s*$')) {
            $errors += "Proposed generated skill '$id' is missing required section '$heading'."
        }
    }
    foreach ($evidence in @($record.evidence)) {
        try { Resolve-RepositoryPath -Path ([string]$evidence.path) -Description "Evidence for generated skill '$id'" -RequireFile | Out-Null }
        catch { $errors += $_.Exception.Message }
    }
}
foreach ($id in $referencedProjectSkills.Keys) {
    if (-not $generatedIds.ContainsKey($id)) {
        $errors += "Project skill '$id' is referenced by project.json but missing from bootstrap-proposal/generated-skills.json."
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Bootstrap proposal validation failed with $($errors.Count) error(s)."
}

$filesToApply = @(
    '.ai/project-profile.json',
    '.ai/project.json',
    '.ai/project-rules.md',
    '.ai/generated-skills.json'
)
$filesToApply += @($generatedSkills.skills | ForEach-Object { [string]$_.path })

if ($DryRun) {
    [ordered]@{
        verdict = 'BOOTSTRAP_PROPOSAL_VALID'
        proposalRoot = '.ai/bootstrap-proposal'
        repositoryFingerprint = [string]$proposalProfile.structureFingerprint
        projectName = [string]$project.name
        modules = @($project.modules | ForEach-Object { [string]$_.id })
        filesToApply = @($filesToApply | Sort-Object -Unique)
    } | ConvertTo-Json -Depth 5
    exit 0
}

& $profilerPath -OutputPath '.ai/project-profile.json' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to persist the approved project profile.'
}

Copy-FileCreatingParent -Source $proposalProjectPath -Destination (Resolve-RepositoryPath -Path '.ai/project.json' -Description 'Project configuration destination')
Copy-FileCreatingParent -Source $proposalRulesPath -Destination (Resolve-RepositoryPath -Path '.ai/project-rules.md' -Description 'Project rules destination')
Copy-FileCreatingParent -Source $proposalGeneratedSkillsPath -Destination (Resolve-RepositoryPath -Path '.ai/generated-skills.json' -Description 'Generated skills destination')
foreach ($record in @($generatedSkills.skills)) {
    $id = [string]$record.id
    $source = Resolve-RepositoryPath -Path ".ai/bootstrap-proposal/skills/$id/SKILL.md" -Description "Proposed generated skill '$id'" -RequireFile
    $destination = Resolve-RepositoryPath -Path ([string]$record.path) -Description "Generated skill '$id' destination"
    Copy-FileCreatingParent -Source $source -Destination $destination
}

$validationOutput = @(& $validatorPath)
if ($LASTEXITCODE -ne 0) {
    throw "Applied bootstrap proposal failed project validation.`n$($validationOutput -join "`n")"
}

$validation = ($validationOutput -join "`n") | ConvertFrom-Json
[ordered]@{
    verdict = 'PROJECT_VALID'
    proposalRoot = '.ai/bootstrap-proposal'
    repositoryFingerprint = [string]$proposalProfile.structureFingerprint
    projectName = [string]$project.name
    modules = @($project.modules | ForEach-Object { [string]$_.id })
    filesApplied = @($filesToApply | Sort-Object -Unique)
    validation = $validation
} | ConvertTo-Json -Depth 6
exit 0
