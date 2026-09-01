[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('QuickFix', 'SmallTask')][string]$TaskType,
    [Parameter(Mandatory = $true)][ValidateSet('Estimate', 'Actual')][string]$Phase,
    [int]$ModuleCount = -1,
    [int]$FileCount = -1,
    [int]$LineCount = -1,
    [ValidateRange(1, 3)][int]$MaximumFiles = 3,
    [ValidateRange(1, 120)][int]$MaximumLines = 120,
    [string]$ProjectPath = '.ai/project.json',
    [string]$BaseRef = 'HEAD',
    [switch]$AcceptanceClear,
    [switch]$RootCauseKnown,
    [switch]$VerificationAvailable,
    [switch]$PublicContract,
    [switch]$NewDependency,
    [switch]$Migration,
    [switch]$SecuritySensitive,
    [switch]$Infrastructure,
    [switch]$DataIntegrity,
    [switch]$Concurrency,
    [switch]$CrossModule,
    [switch]$GeneratedCode
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$blockers = @()
$changedFiles = @()
$detectedRiskReasons = @()

function Get-RepositoryRoot {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) { throw 'Git is required for fast-path classification.' }
    $root = (& $git.Source rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        throw 'Fast-path classification requires an initialized Git repository.'
    }
    return [IO.Path]::GetFullPath($root.Trim()).TrimEnd('\', '/')
}

function Get-UntrackedLineCount([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Count -eq 0) { return 0 }
    if ($bytes -contains 0) { return -1 }
    $newLines = @($bytes | Where-Object { $_ -eq 10 }).Count
    if ($bytes[-1] -ne 10) { $newLines++ }
    return $newLines
}

function Test-PathPattern([string]$Path, [string[]]$Patterns) {
    foreach ($pattern in $Patterns) {
        if ($Path -match $pattern) { return $true }
    }
    return $false
}

$repositoryRoot = Get-RepositoryRoot
$resolvedProjectPath = if ([IO.Path]::IsPathRooted($ProjectPath)) { [IO.Path]::GetFullPath($ProjectPath) } else { [IO.Path]::GetFullPath((Join-Path $repositoryRoot $ProjectPath)) }
if (-not $resolvedProjectPath.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ProjectPath must be inside the repository.'
}
if (-not (Test-Path -LiteralPath $resolvedProjectPath -PathType Leaf)) { throw "Project configuration not found: $resolvedProjectPath" }
$project = Get-Content -LiteralPath $resolvedProjectPath -Raw | ConvertFrom-Json

if ($project.PSObject.Properties.Name -contains 'fastPath') {
    if ($project.fastPath.PSObject.Properties.Name -contains 'enabled' -and -not [bool]$project.fastPath.enabled) {
        $blockers += 'Fast path is disabled by project configuration.'
    }
    if ($project.fastPath.PSObject.Properties.Name -contains 'maximumFiles') {
        $MaximumFiles = [Math]::Min($MaximumFiles, [int]$project.fastPath.maximumFiles)
    }
    if ($project.fastPath.PSObject.Properties.Name -contains 'maximumLines') {
        $MaximumLines = [Math]::Min($MaximumLines, [int]$project.fastPath.maximumLines)
    }
}

if ($Phase -eq 'Actual') {
    $numstat = @(& git -C $repositoryRoot diff --numstat --no-renames $BaseRef -- 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to calculate actual diff from base ref '$BaseRef'." }
    $fileLines = @{}
    foreach ($line in $numstat) {
        $parts = @($line -split "`t", 3)
        if ($parts.Count -ne 3) { continue }
        $path = ([string]$parts[2]).Replace('\', '/')
        if ($parts[0] -eq '-' -or $parts[1] -eq '-') {
            $blockers += "Binary diff cannot be measured safely: $path"
            $fileLines[$path] = 0
        }
        else {
            $fileLines[$path] = [int]$parts[0] + [int]$parts[1]
        }
    }
    $untracked = @(& git -C $repositoryRoot ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect untracked files for actual fast-path scope.' }
    foreach ($pathValue in $untracked) {
        $path = ([string]$pathValue).Replace('\', '/')
        $full = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $path))
        if (-not $full.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Untracked path escapes repository: $path"
        }
        $lines = Get-UntrackedLineCount -Path $full
        if ($lines -lt 0) {
            $blockers += "Untracked binary file cannot be measured safely: $path"
            $lines = 0
        }
        $fileLines[$path] = $lines
    }
    $changedFiles = @($fileLines.Keys | Sort-Object)
    $FileCount = $changedFiles.Count
    $LineCount = [int](($fileLines.Values | Measure-Object -Sum).Sum)

    $affectedModuleIds = @()
    foreach ($module in @($project.modules)) {
        $modulePath = ([string]$module.path).Replace('\', '/').Trim('/')
        $matches = if ($modulePath -in @('', '.')) {
            $changedFiles.Count -gt 0
        }
        else {
            @($changedFiles | Where-Object { $_ -eq $modulePath -or $_.StartsWith($modulePath + '/', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        }
        if ($matches) { $affectedModuleIds += [string]$module.id }
    }
    $ModuleCount = @($affectedModuleIds | Sort-Object -Unique).Count
    if ($ModuleCount -gt 1) { $CrossModule = $true }

    $dependencyPatterns = @('(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|poetry\.lock|Pipfile\.lock|packages\.lock\.json|go\.sum|Cargo\.lock)$', '(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt|pom\.xml|build\.gradle(?:\.kts)?|[^/]+\.csproj)$')
    $migrationPatterns = @('(^|/)(migrations?|database/migrations?)(/|$)', '\.migration\.')
    $infrastructurePatterns = @('(^|/)\.github/workflows/', '(^|/)(azure-pipelines[^/]*\.ya?ml|Dockerfile[^/]*|docker-compose[^/]*\.ya?ml)$', '(^|/)(terraform|infra|infrastructure|k8s|helm)(/|$)')
    $generatedPatterns = @('(^|/)(generated|dist|coverage)(/|$)', '\.(g|generated|designer)\.[^/]+$')
    $securityPatterns = @('(^|/)(auth|authentication|authorization|identity|security|secrets?|credentials?|crypto)(/|$)')
    $contractPatterns = @('(^|/)(openapi|swagger|public-api)(/|\.)', '\.(proto|wsdl)$')

    foreach ($path in $changedFiles) {
        if (Test-PathPattern -Path $path -Patterns $dependencyPatterns) { $NewDependency = $true; $detectedRiskReasons += "dependency manifest or lockfile: $path" }
        if (Test-PathPattern -Path $path -Patterns $migrationPatterns) { $Migration = $true; $detectedRiskReasons += "migration path: $path" }
        if (Test-PathPattern -Path $path -Patterns $infrastructurePatterns) { $Infrastructure = $true; $detectedRiskReasons += "infrastructure or CI path: $path" }
        if (Test-PathPattern -Path $path -Patterns $generatedPatterns) { $GeneratedCode = $true; $detectedRiskReasons += "generated output path: $path" }
        if (Test-PathPattern -Path $path -Patterns $securityPatterns) { $SecuritySensitive = $true; $detectedRiskReasons += "security-sensitive path: $path" }
        if (Test-PathPattern -Path $path -Patterns $contractPatterns) { $PublicContract = $true; $detectedRiskReasons += "public contract path: $path" }
    }
}
elseif ($ModuleCount -lt 0 -or $FileCount -lt 0 -or $LineCount -lt 0) {
    throw 'Estimate phase requires non-negative ModuleCount, FileCount, and LineCount.'
}

if (-not $AcceptanceClear) { $blockers += 'Acceptance criteria are not clear and observable.' }
if (-not $VerificationAvailable) { $blockers += 'No deterministic verification or regression test is available.' }
if ($TaskType -eq 'QuickFix') {
    if ($ModuleCount -ne 1) { $blockers += 'A quick fix must affect exactly one configured module.' }
    if (-not $RootCauseKnown) { $blockers += 'The root cause is not established by bounded evidence.' }
}
elseif ($ModuleCount -gt 1) {
    $blockers += 'A small task may affect at most one configured module.'
}
if ($FileCount -lt 1) { $blockers += 'Fast path requires at least one changed file.' }
if ($FileCount -gt $MaximumFiles) { $blockers += "File count $FileCount exceeds the fast-path maximum of $MaximumFiles." }
if ($LineCount -lt 1) { $blockers += 'Fast path requires at least one added or deleted line.' }
if ($LineCount -gt $MaximumLines) { $blockers += "Line count $LineCount exceeds the fast-path maximum of $MaximumLines." }

$riskFlags = [ordered]@{
    publicContract = [bool]$PublicContract
    newDependency = [bool]$NewDependency
    migration = [bool]$Migration
    securitySensitive = [bool]$SecuritySensitive
    infrastructure = [bool]$Infrastructure
    dataIntegrity = [bool]$DataIntegrity
    concurrency = [bool]$Concurrency
    crossModule = [bool]$CrossModule
    generatedCode = [bool]$GeneratedCode
}
$riskMessages = @{
    publicContract = 'Public API or external contract changes require the standard workflow.'
    newDependency = 'New or replaced dependencies require the standard workflow.'
    migration = 'Database or data migrations require the standard workflow.'
    securitySensitive = 'Authentication, authorization, secrets, or other security-sensitive changes require the critical workflow.'
    infrastructure = 'CI/CD, infrastructure, deployment, or cloud changes require the critical workflow.'
    dataIntegrity = 'Data-integrity-sensitive changes require the standard or critical workflow.'
    concurrency = 'Concurrency-sensitive changes require the standard or critical workflow.'
    crossModule = 'Cross-module behavior requires the standard workflow.'
    generatedCode = 'Generated-code or generator changes require the standard workflow.'
}
foreach ($riskName in $riskFlags.Keys) {
    if ($riskFlags[$riskName]) { $blockers += $riskMessages[$riskName] }
}

$eligible = $blockers.Count -eq 0
[ordered]@{
    taskType = $TaskType
    phase = $Phase
    verdict = if ($eligible) { 'FAST_PATH_ELIGIBLE' } else { 'ESCALATE_STANDARD' }
    eligible = $eligible
    baseRef = if ($Phase -eq 'Actual') { $BaseRef } else { $null }
    thresholds = [ordered]@{ maximumModules = 1; maximumFiles = $MaximumFiles; maximumLines = $MaximumLines; maximumCorrectionIterations = 1 }
    observed = [ordered]@{
        moduleCount = $ModuleCount
        fileCount = $FileCount
        lineCount = $LineCount
        changedFiles = @($changedFiles)
        acceptanceClear = [bool]$AcceptanceClear
        rootCauseKnown = [bool]$RootCauseKnown
        verificationAvailable = [bool]$VerificationAvailable
        riskFlags = $riskFlags
        detectedRiskReasons = @($detectedRiskReasons | Sort-Object -Unique)
    }
    blockers = @($blockers | Sort-Object -Unique)
} | ConvertTo-Json -Depth 7

if (-not $eligible) { exit 3 }
exit 0
