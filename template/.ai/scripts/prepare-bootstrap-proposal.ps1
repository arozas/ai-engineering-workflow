[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to prepare a bootstrap proposal.' }

$repositoryRootOutput = @(& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or $repositoryRootOutput.Count -ne 1) {
    throw 'Bootstrap proposal preparation requires an initialized Git repository.'
}
$repositoryRoot = [IO.Path]::GetFullPath([string]$repositoryRootOutput[0]).TrimEnd('\', '/')

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [switch]$RequireFile
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
    return $resolved
}

function ConvertTo-RepoPath([string]$Path) {
    return ([IO.Path]::GetRelativePath($repositoryRoot, [IO.Path]::GetFullPath($Path))).Replace('\', '/')
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 10
    )

    $resolved = Resolve-RepositoryPath -Path $Path -Description 'JSON output'
    $directory = Split-Path -Parent $resolved
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $resolved -Encoding utf8
}

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $resolved = Resolve-RepositoryPath -Path $Path -Description 'Text output'
    $directory = Split-Path -Parent $resolved
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Set-Content -LiteralPath $resolved -Value $Value -Encoding utf8
}

function Get-FirstManifest {
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $matches = @($Candidate.evidence | Where-Object { [string]$_ -match $Pattern } | Select-Object -First 1)
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Test-FileContains {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $resolved = Join-Path $repositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { return $false }
    return ((Get-Content -LiteralPath $resolved -Raw) -match $Pattern)
}

function Get-ModuleFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ModulePath,
        [Parameter(Mandatory = $true)][string[]]$Files
    )

    if ($ModulePath -eq '.') { return @($Files) }
    $prefix = $ModulePath.TrimEnd('/') + '/'
    return @($Files | Where-Object { ([string]$_).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
}

function Get-Frameworks {
    param(
        [Parameter(Mandatory = $true)]$Candidate
    )

    $frameworks = [System.Collections.Generic.List[string]]::new()
    $csproj = Get-FirstManifest -Candidate $Candidate -Pattern '\.(csproj|fsproj|vbproj)$'
    if ($null -ne $csproj -and (Test-FileContains -RelativePath $csproj -Pattern '<Project\s+Sdk="Microsoft\.NET\.Sdk\.Web"|Microsoft\.AspNetCore')) {
        $frameworks.Add('aspnetcore')
    }
    $package = Get-FirstManifest -Candidate $Candidate -Pattern '(^|/)package\.json$'
    if ($null -ne $package) {
        $content = Get-Content -LiteralPath (Join-Path $repositoryRoot $package) -Raw
        if ($content -match '"react"') { $frameworks.Add('react') }
        elseif ($content -match '"express"') { $frameworks.Add('express') }
        elseif ($content -match '"next"') { $frameworks.Add('nextjs') }
        elseif ($content -match '"vite"') { $frameworks.Add('vite') }
        else { $frameworks.Add('node') }
    }
    return @($frameworks | Sort-Object -Unique)
}

function Get-StackSkills {
    param(
        [Parameter(Mandatory = $true)][string[]]$Languages,
        [Parameter(Mandatory = $true)][string[]]$Frameworks
    )

    $skills = [System.Collections.Generic.List[string]]::new()
    if ($Languages -contains 'csharp' -or $Languages -contains 'fsharp' -or $Languages -contains 'visual-basic') { $skills.Add('stack-dotnet') }
    if ($Languages -contains 'java' -or $Languages -contains 'kotlin') { $skills.Add('stack-java') }
    if ($Languages -contains 'javascript' -or $Languages -contains 'typescript') { $skills.Add('stack-node') }
    if ($Frameworks -contains 'react') { $skills.Add('stack-react') }
    if ($Languages -contains 'python') { $skills.Add('stack-python') }
    return @($skills | Sort-Object -Unique)
}

function Get-Architecture {
    param(
        [Parameter(Mandatory = $true)][string[]]$ModuleFiles
    )

    $hasControllers = @($ModuleFiles | Where-Object { $_ -match '(?i)(^|/)Controllers?/' }).Count -gt 0
    $hasModels = @($ModuleFiles | Where-Object { $_ -match '(?i)(^|/)Models?/' }).Count -gt 0
    $hasRepositories = @($ModuleFiles | Where-Object { $_ -match '(?i)(^|/)(Repositories|Repository)/' }).Count -gt 0
    $hasPersistence = @($ModuleFiles | Where-Object { $_ -match '(?i)(DbContext|Migrations/|database|persistence)' }).Count -gt 0
    if ($hasControllers -and ($hasModels -or $hasRepositories -or $hasPersistence)) {
        return [ordered]@{
            architectures = @('architecture-simple-layered')
            contextSkills = @('architecture-simple-layered')
            confidence = 'HIGH'
            rationale = 'Conventional controllers/models/repositories/persistence evidence exists; stronger Clean/hexagonal/vertical-slice/event-driven boundaries were not proven.'
        }
    }
    return [ordered]@{
        architectures = @()
        contextSkills = @()
        confidence = 'LOW'
        rationale = 'No supported architecture pattern was proven by repository evidence.'
    }
}

function Get-Quality {
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)][string[]]$ModuleFiles,
        [Parameter(Mandatory = $true)]$Profile
    )

    $hasDotnet = @($Candidate.evidence | Where-Object { $_ -match '\.(sln|slnx|csproj|fsproj|vbproj)$' }).Count -gt 0
    $hasNode = @($Candidate.evidence | Where-Object { $_ -match '(^|/)package\.json$' }).Count -gt 0
    $hasTestEvidence = @($Profile.testFiles).Count -gt 0 -or @($ModuleFiles | Where-Object { $_ -match '(?i)(^|/)(test|tests|spec|specs)(/|$)|Tests?\.(csproj|fsproj|vbproj)$' }).Count -gt 0
    $hasDotnetFormattingEvidence = @($Profile.conventionFiles | Where-Object { $_ -match '(?i)(^|/)(\.editorconfig|Directory\.Build\.(props|targets)|global\.json)$' }).Count -gt 0

    if ($hasDotnet) {
        return [ordered]@{
            restore = @('dotnet restore')
            build = @('dotnet build --no-restore')
            lint = @(if ($hasDotnetFormattingEvidence) { 'dotnet format --verify-no-changes' })
            typecheck = @()
            test = @(if ($hasTestEvidence) { 'dotnet test --no-build' })
            e2e = @()
        }
    }
    if ($hasNode) {
        return [ordered]@{
            restore = @('npm install')
            build = @()
            lint = @()
            typecheck = @()
            test = @(if ($hasTestEvidence) { 'npm test' })
            e2e = @()
        }
    }
    return [ordered]@{ restore = @(); build = @(); lint = @(); typecheck = @(); test = @(); e2e = @() }
}

function Get-DiagnosticsCommands {
    param([Parameter(Mandatory = $true)]$Quality)

    if (@($Quality.build).Count -gt 0) { return @($Quality.build[0]) }
    return @()
}

function Get-ModuleId {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Index
    )

    if ($Path -eq '.') { return 'app' }
    $name = [IO.Path]::GetFileName($Path.TrimEnd('/', '\')).ToLowerInvariant()
    $id = ($name -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($id)) { return "module-$Index" }
    return $id
}

if ((Test-Path -LiteralPath (Join-Path $repositoryRoot 'workflow.manifest.json') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $repositoryRoot 'template') -PathType Container) -and
    (Test-Path -LiteralPath (Join-Path $repositoryRoot 'presets') -PathType Container) -and
    (Test-Path -LiteralPath (Join-Path $repositoryRoot 'scripts') -PathType Container)) {
    throw 'BOOTSTRAP NOT APPLICABLE'
}

$profilerPath = Resolve-RepositoryPath -Path '.ai/scripts/profile-project.ps1' -Description 'Project profiler' -RequireFile
$profileOutput = @(& $profilerPath)
if ($LASTEXITCODE -ne 0) {
    throw "BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE`n$($profileOutput -join "`n")"
}
$profile = ($profileOutput -join "`n") | ConvertFrom-Json
if (@($profile.moduleCandidates).Count -eq 0) { throw 'NO PROJECT MODULES DETECTED' }

$rawFiles = @(& $gitCommand.Source -C $repositoryRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the repository inventory.' }
$files = @(
    $rawFiles |
        ForEach-Object { ([string]$_).Replace('\', '/') } |
        Where-Object { $_ -notmatch '^(?:AGENTS\.md|opencode\.json|\.ai(?:/|$)|\.opencode(?:/|$))' } |
        Sort-Object -Unique
)
if ($files.Count -eq 0) { throw 'NO PROJECT MODULES DETECTED' }

$bootstrapInputPath = Join-Path $repositoryRoot '.ai\bootstrap-input.json'
$bootstrapInput = $null
if (Test-Path -LiteralPath $bootstrapInputPath -PathType Leaf) {
    $bootstrapInput = Get-Content -LiteralPath $bootstrapInputPath -Raw | ConvertFrom-Json
}

$projectName = if ($null -ne $bootstrapInput -and $bootstrapInput.PSObject.Properties.Name -contains 'projectName' -and -not [string]::IsNullOrWhiteSpace([string]$bootstrapInput.projectName)) {
    [string]$bootstrapInput.projectName
}
else {
    [IO.Path]::GetFileName($repositoryRoot)
}

$modules = [System.Collections.Generic.List[object]]::new()
$moduleEvidence = [System.Collections.Generic.List[string]]::new()
$index = 0
foreach ($candidate in @($profile.moduleCandidates)) {
    $index++
    $modulePath = [string]$candidate.path
    $moduleFiles = @(Get-ModuleFiles -ModulePath $modulePath -Files $files)
    $languages = @(
        foreach ($language in @($profile.languages)) {
            $samplePaths = @($language.samplePaths | Where-Object {
                $modulePath -eq '.' -or ([string]$_).StartsWith($modulePath.TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase)
            })
            if ($modulePath -eq '.' -or @($samplePaths).Count -gt 0) { [string]$language.id }
        }
    ) | Sort-Object -Unique
    if (@($languages).Count -eq 0) { $languages = @('unknown') }
    $frameworks = @(Get-Frameworks -Candidate $candidate)
    $stackSkills = @(Get-StackSkills -Languages $languages -Frameworks $frameworks)
    $architecture = Get-Architecture -ModuleFiles $moduleFiles
    $quality = Get-Quality -Candidate $candidate -ModuleFiles $moduleFiles -Profile $profile
    $contextSkills = @($stackSkills + @($architecture.contextSkills) | Sort-Object -Unique)
    if (@($contextSkills).Count -eq 0) { $contextSkills = @('project-' + (Get-ModuleId -Path $modulePath -Index $index)) }

    $moduleId = Get-ModuleId -Path $modulePath -Index $index
    $modules.Add([ordered]@{
        id = $moduleId
        path = $modulePath
        languages = @($languages)
        frameworks = @($frameworks)
        architectures = @($architecture.architectures)
        contextSkills = @($contextSkills)
        quality = $quality
    })
    $moduleEvidence.Add("- `$moduleId` at `$modulePath`: manifests $(@($candidate.evidence) -join ', '); languages $(@($languages) -join ', '); frameworks $(if (@($frameworks).Count -gt 0) { @($frameworks) -join ', ' } else { 'none proven' }); architecture $($architecture.rationale)")
}

$diagnosticCommands = @()
foreach ($module in @($modules)) {
    $diagnosticCommands += @(Get-DiagnosticsCommands -Quality $module.quality)
}
$diagnosticCommands = @($diagnosticCommands | Sort-Object -Unique)

$project = [ordered]@{
    '$schema' = './project.schema.json'
    version = 1
    name = $projectName
    fastPath = [ordered]@{
        enabled = $true
        maximumFiles = 3
        maximumLines = 120
        maximumProductionFilesForDiagnosis = 2
        maximumTestFilesForDiagnosis = 2
        maximumCorrectionIterations = 1
    }
    review = [ordered]@{
        maxIterations = 3
        diffBudget = [ordered]@{ filesMultiplier = 2; linesMultiplier = 3 }
    }
    diagnostics = [ordered]@{
        maxHypothesisIterations = 3
        requireReproduction = $false
        commands = @($diagnosticCommands)
    }
    profile = [ordered]@{
        repositoryFingerprint = [string]$profile.structureFingerprint
        analyzedAtUtc = [string]$profile.scannedAtUtc
        source = '.ai/project-profile.json'
        generatedSkillsManifest = '.ai/generated-skills.json'
    }
    modules = @($modules)
}

$generatedSkills = [ordered]@{
    version = 1
    repositoryFingerprint = [string]$profile.structureFingerprint
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    skills = @()
}

$rules = @"
# Project rules

This file is a draft generated by `/ai-bootstrap`. Edit it before `/ai-bootstrap-apply` if any rule is incorrect.

## Project overview

- Project: $projectName
- Repository shape: inferred from deterministic profile and build manifests.
- Profile fingerprint: $($profile.structureFingerprint)

## Module boundaries

$($moduleEvidence -join "`n")

## Local conventions

- Follow existing naming, directory layout, error handling, and test placement.
- Do not add dependencies, migrations, CI/CD, infrastructure, public API changes, or generated-code changes without explicit approval.
- Leave unknown conventions unknown until repository evidence or explicit user direction establishes them.

## Quality gates

- Run only commands listed in `.ai/project.json` for affected modules.
- Empty quality phases mean no repository-evidenced command was detected for that phase.

## Production incidents

- Unknown causes use `/diagnose`; urgency does not authorize `/quick-fix` or speculative implementation.
- Supply only sanitized incident evidence. Production access, mitigation, rollback, restart, deployment, data repair, and cloud mutation remain outside diagnosis.

## Definition of done

Work is done only when acceptance criteria are mapped to evidence, configured quality commands pass, review has no BLOCKER or HIGH findings, changes remain within approved scope, and residual risks are reported.
"@

$evidence = @"
# Bootstrap evidence

PROFILE FALLBACK USED: proposal prepared by `.ai/scripts/prepare-bootstrap-proposal.ps1`, which invokes `.ai/scripts/profile-project.ps1` directly.

## Deterministic profile

- Fingerprint: `$($profile.structureFingerprint)`
- Head SHA: `$($profile.headSha)`
- File count: $($profile.fileCount)
- Languages: $(@($profile.languages | ForEach-Object { "$($_.id) ($($_.fileCount))" }) -join ', ')
- Module candidates: $(@($profile.moduleCandidates | ForEach-Object { "$($_.path) [$(@($_.evidence) -join ', ')]" }) -join '; ')
- Architecture markers: $(if (@($profile.architectureMarkers).Count -gt 0) { @($profile.architectureMarkers | ForEach-Object { "$($_.marker): $(@($_.paths) -join ', ')" }) -join '; ' } else { 'none' })
- CI files: $(if (@($profile.ciFiles).Count -gt 0) { @($profile.ciFiles) -join ', ' } else { 'none' })
- Test files: $(if (@($profile.testFiles).Count -gt 0) { @($profile.testFiles) -join ', ' } else { 'none' })
- Convention files: $(if (@($profile.conventionFiles).Count -gt 0) { @($profile.conventionFiles) -join ', ' } else { 'none' })

## Proposed modules

$($moduleEvidence -join "`n")

## Conservative inference policy

- Build and restore commands are proposed only when build manifests exist.
- Test commands are empty unless test files or test projects are detected.
- Lint commands are empty unless convention evidence is detected.
- `architecture-simple-layered` is used for conventional controller/model/repository applications.
- Clean, hexagonal, vertical-slice, and event-driven architectures are not inferred from directory names alone.

## Review instructions

Edit these draft files before applying:

- `.ai/bootstrap-proposal/project.json`
- `.ai/bootstrap-proposal/project-rules.md`
- `.ai/bootstrap-proposal/generated-skills.json`
- `.ai/bootstrap-proposal/skills/project-<module-id>/SKILL.md` when present

Then run `/ai-bootstrap-apply`.
"@

$approval = @"
# Bootstrap approval

Review and edit the files in this directory.

Run `/ai-bootstrap-apply` only after the proposal is correct.

The apply step validates this draft, reruns the repository profiler, blocks on structural drift, writes the approved final files, and requires `PROJECT_VALID`.
"@

$proposalRoot = Resolve-RepositoryPath -Path '.ai/bootstrap-proposal' -Description 'Bootstrap proposal directory'
if (-not (Test-Path -LiteralPath $proposalRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $proposalRoot -Force | Out-Null
}

Write-JsonFile -Value $profile -Path '.ai/bootstrap-proposal/project-profile.json'
Write-JsonFile -Value $project -Path '.ai/bootstrap-proposal/project.json'
Write-JsonFile -Value $generatedSkills -Path '.ai/bootstrap-proposal/generated-skills.json'
Write-TextFile -Value $rules -Path '.ai/bootstrap-proposal/project-rules.md'
Write-TextFile -Value $evidence -Path '.ai/bootstrap-proposal/evidence.md'
Write-TextFile -Value $approval -Path '.ai/bootstrap-proposal/approval.md'

$applyPath = Resolve-RepositoryPath -Path '.ai/scripts/apply-bootstrap-proposal.ps1' -Description 'Bootstrap proposal validator' -RequireFile
$dryRunOutput = @(& $applyPath -DryRun)
if ($LASTEXITCODE -ne 0) {
    throw "Prepared bootstrap proposal failed dry-run validation.`n$($dryRunOutput -join "`n")"
}
$dryRun = ($dryRunOutput -join "`n") | ConvertFrom-Json

[ordered]@{
    verdict = 'BOOTSTRAP_PROPOSAL_READY'
    proposalRoot = '.ai/bootstrap-proposal'
    dryRunVerdict = [string]$dryRun.verdict
    repositoryFingerprint = [string]$profile.structureFingerprint
    projectName = $projectName
    modules = @($modules | ForEach-Object { [string]$_.id })
    files = @(
        '.ai/bootstrap-proposal/project-profile.json',
        '.ai/bootstrap-proposal/project.json',
        '.ai/bootstrap-proposal/project-rules.md',
        '.ai/bootstrap-proposal/generated-skills.json',
        '.ai/bootstrap-proposal/evidence.md',
        '.ai/bootstrap-proposal/approval.md'
    )
    risks = @(
        if (@($profile.testFiles).Count -eq 0) { 'No test files were detected; test quality phases remain empty unless you add or approve evidence.' }
        if (@($profile.ciFiles).Count -eq 0) { 'No CI/CD files were detected.' }
        if (@($profile.conventionFiles).Count -eq 0) { 'No convention files were detected; lint/format commands remain empty unless explicit evidence is added.' }
    )
    next = 'Review or edit .ai/bootstrap-proposal/, then run /ai-bootstrap-apply.'
} | ConvertTo-Json -Depth 6
exit 0
