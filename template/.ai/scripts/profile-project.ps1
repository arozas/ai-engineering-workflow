[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RepositoryRoot {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) { throw 'Git is required for deterministic project profiling.' }
    $root = (& $git.Source rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        throw 'Project profiling requires an initialized Git repository.'
    }
    return [IO.Path]::GetFullPath($root.Trim()).TrimEnd('\', '/')
}

function Get-ManifestKind([string]$Path) {
    $name = [IO.Path]::GetFileName($Path).ToLowerInvariant()
    if ($name -eq 'package.json') { return 'node-package' }
    if ($name -eq 'pnpm-workspace.yaml') { return 'pnpm-workspace' }
    if ($name -eq 'pyproject.toml') { return 'python-project' }
    if ($name -match '^requirements.*\.txt$') { return 'python-requirements' }
    if ($name -eq 'pom.xml') { return 'maven-project' }
    if ($name -match '^build\.gradle(?:\.kts)?$') { return 'gradle-project' }
    if ($name -eq 'go.mod') { return 'go-module' }
    if ($name -eq 'cargo.toml') { return 'rust-package' }
    if ($name -match '\.(sln|slnx)$') { return 'dotnet-solution' }
    if ($name -match '\.(csproj|fsproj|vbproj)$') { return 'dotnet-project' }
    return 'build-manifest'
}

function Get-LanguageId([string]$Path) {
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $language = switch ($extension) {
        '.cs' { 'csharp' }
        '.fs' { 'fsharp' }
        '.vb' { 'visual-basic' }
        '.java' { 'java' }
        '.kt' { 'kotlin' }
        '.kts' { 'kotlin' }
        '.js' { 'javascript' }
        '.jsx' { 'javascript' }
        '.mjs' { 'javascript' }
        '.cjs' { 'javascript' }
        '.ts' { 'typescript' }
        '.tsx' { 'typescript' }
        '.mts' { 'typescript' }
        '.cts' { 'typescript' }
        '.py' { 'python' }
        '.go' { 'go' }
        '.rs' { 'rust' }
        '.rb' { 'ruby' }
        '.php' { 'php' }
        '.swift' { 'swift' }
        default { $null }
    }
    return $language
}

function Resolve-OutputFile([string]$RepositoryRoot, [string]$Path) {
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepositoryRoot $Path }
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not $resolved.StartsWith($RepositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputPath must be inside the repository: $resolved"
    }
    $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $resolved).Replace('\', '/')
    if ($relative -ne '.ai/project-profile.json') {
        throw 'OutputPath is restricted to .ai/project-profile.json.'
    }
    return $resolved
}

$repositoryRoot = Get-RepositoryRoot
$rawFiles = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the repository inventory.' }
$files = @(
    $rawFiles |
        ForEach-Object { ([string]$_).Replace('\', '/') } |
        Where-Object { $_ -notmatch '^(?:AGENTS\.md|opencode\.json|\.ai(?:/|$)|\.opencode(?:/|$))' } |
        Sort-Object -Unique
)
if ($files.Count -eq 0) { throw 'NO PROJECT MODULES DETECTED' }

$manifestPattern = '(?i)(^|/)(package\.json|pnpm-workspace\.yaml|pyproject\.toml|requirements[^/]*\.txt|pom\.xml|build\.gradle(?:\.kts)?|go\.mod|cargo\.toml|[^/]+\.(?:sln|slnx|csproj|fsproj|vbproj))$'
$manifestPaths = @($files | Where-Object { $_ -match $manifestPattern })
$manifests = @(
    foreach ($path in $manifestPaths) {
        $full = Join-Path $repositoryRoot $path
        [ordered]@{
            path = $path
            kind = Get-ManifestKind -Path $path
            sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
)

$languageGroups = @{}
foreach ($path in $files) {
    $language = Get-LanguageId -Path $path
    if ($null -eq $language) { continue }
    if (-not $languageGroups.ContainsKey($language)) { $languageGroups[$language] = [System.Collections.Generic.List[string]]::new() }
    $languageGroups[$language].Add($path)
}
$languages = @(
    foreach ($language in @($languageGroups.Keys | Sort-Object)) {
        $paths = @($languageGroups[$language] | Sort-Object)
        [ordered]@{ id = $language; fileCount = $paths.Count; samplePaths = @($paths | Select-Object -First 5) }
    }
)

$candidateMap = @{}
foreach ($manifest in $manifests) {
    $parent = [IO.Path]::GetDirectoryName(([string]$manifest.path).Replace('/', [IO.Path]::DirectorySeparatorChar))
    $candidate = if ([string]::IsNullOrWhiteSpace($parent)) { '.' } else { $parent.Replace('\', '/') }
    if (-not $candidateMap.ContainsKey($candidate)) { $candidateMap[$candidate] = [System.Collections.Generic.List[string]]::new() }
    $candidateMap[$candidate].Add([string]$manifest.path)
}
$moduleCandidates = @(
    foreach ($candidate in @($candidateMap.Keys | Sort-Object)) {
        [ordered]@{ path = $candidate; evidence = @($candidateMap[$candidate] | Sort-Object -Unique) }
    }
)

$markerNames = @('domain', 'application', 'infrastructure', 'ports', 'adapters', 'features', 'events')
$architectureMarkers = @(
    foreach ($marker in $markerNames) {
        $matches = @($files | Where-Object { $_ -match "(?i)(^|/)$marker(/|$)" } | Select-Object -First 10)
        if ($matches.Count -gt 0) { [ordered]@{ marker = $marker; paths = $matches } }
    }
)

$ciFiles = @($files | Where-Object { $_ -match '(?i)(^\.github/workflows/|^\.gitlab-ci\.ya?ml$|(^|/)azure-pipelines[^/]*\.ya?ml$|(^|/)Jenkinsfile$)' })
$testFiles = @($files | Where-Object { $_ -match '(?i)(^|/)(test|tests|spec|specs|__tests__)(/|$)|(?:Tests?|Specs?)\.(?:cs|fs|vb)$|\.(test|tests|spec)\.[^/]+$' } | Select-Object -First 50)
$conventionFiles = @($files | Where-Object { $_ -match '(?i)(^|/)(\.editorconfig|Directory\.Build\.(props|targets)|global\.json|tsconfig[^/]*\.json|eslint[^/]*|\.eslintrc[^/]*|prettier[^/]*|\.prettierrc[^/]*|ruff\.toml|mypy\.ini|pytest\.ini)$' })

$fingerprintParts = [System.Collections.Generic.List[string]]::new()
foreach ($evidence in $manifests) { $fingerprintParts.Add("MANIFEST=$($evidence.path):$($evidence.sha256)") }
foreach ($language in $languages) { $fingerprintParts.Add("LANGUAGE=$($language.id)") }
foreach ($candidate in $moduleCandidates) { $fingerprintParts.Add("MODULE=$($candidate.path)") }
foreach ($marker in $architectureMarkers) { $fingerprintParts.Add("ARCHITECTURE-MARKER=$($marker.marker)") }
foreach ($path in @($ciFiles + $conventionFiles | Sort-Object -Unique)) {
    $full = Join-Path $repositoryRoot $path
    $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    $fingerprintParts.Add("CONTEXT=${path}:$hash")
}
$fingerprintBytes = [Text.Encoding]::UTF8.GetBytes(($fingerprintParts -join "`n"))
$structureFingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($fingerprintBytes)).ToLowerInvariant()
$head = (& git -C $repositoryRoot rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) { $head = 'UNBORN' } else { $head = $head.Trim().ToLowerInvariant() }

$profile = [ordered]@{
    version = 1
    structureFingerprint = $structureFingerprint
    scannedAtUtc = [DateTime]::UtcNow.ToString('o')
    headSha = $head
    fileCount = $files.Count
    languages = $languages
    manifests = $manifests
    moduleCandidates = $moduleCandidates
    architectureMarkers = $architectureMarkers
    ciFiles = @($ciFiles)
    testFiles = @($testFiles)
    conventionFiles = @($conventionFiles)
}
$json = $profile | ConvertTo-Json -Depth 8
$schemaPath = Join-Path $repositoryRoot '.ai\project-profile.schema.json'
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Project profile schema not found: $schemaPath" }
$schema = Get-Content -LiteralPath $schemaPath -Raw
if (-not ($json | Test-Json -Schema $schema -ErrorAction Stop)) { throw 'Generated project profile failed schema validation.' }

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = Resolve-OutputFile -RepositoryRoot $repositoryRoot -Path $OutputPath
    $directory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporary = $resolvedOutput + '.tmp'
    try {
        Set-Content -LiteralPath $temporary -Value $json -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination $resolvedOutput -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

$json
