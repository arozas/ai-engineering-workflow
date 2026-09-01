[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [ValidateSet('Local', 'Shared')][string]$Mode = 'Local',
    [switch]$ShareProjectContext,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Workflow.Common.ps1')

$targetRoot = Resolve-WorkflowTarget -TargetPath $TargetPath -MustExist
$entries = @(Get-TemplateFileRecords)
$metadataPath = Get-InstallationMetadataPath -TargetRoot $targetRoot
$gitRepository = $null
$excludePatterns = @()
$localPaths = @()
$gitStatusBefore = $null

if ($Mode -eq 'Shared' -and $ShareProjectContext) {
    throw 'ShareProjectContext is valid only with Mode Local.'
}

if ($Mode -eq 'Local') {
    $gitRepository = Get-GitRepositoryInfo -TargetRoot $targetRoot
    $excludePatterns = @(Get-LocalExcludePatterns -ManagedFiles $entries -ShareProjectContext $ShareProjectContext.IsPresent)
    $localPaths = @($excludePatterns | ForEach-Object { $_.TrimStart('/') })
    $trackedLocalPaths = @(Test-LocalPathsAreUntracked -GitRepository $gitRepository -RelativePaths $localPaths)
    if ($trackedLocalPaths.Count -gt 0) {
        Write-Host 'Tracked paths cannot be hidden by a local installation:'
        $trackedLocalPaths | ForEach-Object { Write-Host "  - $_" }
        throw 'Local installation aborted. Use Mode Shared or untrack the listed paths deliberately.'
    }
    Get-WorkflowExcludeBlockState -ExcludePath $gitRepository.ExcludePath | Out-Null
    $gitStatusBefore = Get-GitStatusSnapshot -GitRepository $gitRepository
}

$conflicts = @()
foreach ($entry in $entries) {
    $destination = Join-Path $targetRoot (ConvertTo-NativeRelativePath -RelativePath $entry.Path)
    if (Test-Path -LiteralPath $destination) {
        $conflicts += $entry.Path
    }
}
if (Test-Path -LiteralPath $metadataPath) {
    $conflicts += (Get-WorkflowManifest).installationMetadata
}

Write-Host "Workflow version: $(Get-WorkflowVersion)"
Write-Host "Target: $targetRoot"
Write-Host "Installation mode: $Mode"
Write-Host "Share project context: $($Mode -eq 'Local' -and $ShareProjectContext.IsPresent)"
Write-Host "Template files: $($entries.Count)"

if ($conflicts.Count -gt 0) {
    Write-Host 'Conflicts:'
    $conflicts | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" }
    throw 'Installation aborted before copying; no files were overwritten.'
}

if ($DryRun) {
    Write-Host 'DRY RUN: installation can proceed without conflicts.'
    if ($Mode -eq 'Local') {
        Write-Host "Git exclude file: $($gitRepository.ExcludePath)"
        Write-Host "Locally excluded paths: $($excludePatterns.Count)"
    }
    return
}

foreach ($entry in $entries) {
    $destination = Join-Path $targetRoot (ConvertTo-NativeRelativePath -RelativePath $entry.Path)
    $destinationDirectory = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $entry.Source -Destination $destination
}

if ($Mode -eq 'Local') {
    Set-WorkflowGitExclude -ExcludePath $gitRepository.ExcludePath -Mode Local -Patterns $excludePatterns
}

Write-InstallationMetadata `
    -TargetRoot $targetRoot `
    -ManagedFiles $entries `
    -InstallationMode $Mode `
    -ShareProjectContext ($Mode -eq 'Local' -and $ShareProjectContext.IsPresent) `
    -LocalExcludedPaths $localPaths

$writtenMetadataJson = Get-Content -LiteralPath $metadataPath -Raw
$writtenMetadataSchema = Get-Content -LiteralPath (Join-Path (Get-TemplateRoot) '.ai\workflow-installation.schema.json') -Raw
if (-not ($writtenMetadataJson | Test-Json -Schema $writtenMetadataSchema -ErrorAction Stop)) {
    throw 'Installation metadata failed deterministic schema validation.'
}

if ($Mode -eq 'Local') {
    Assert-LocalPathsIgnored -GitRepository $gitRepository -RelativePaths $localPaths
    $gitStatusAfter = Get-GitStatusSnapshot -GitRepository $gitRepository
    if (-not $ShareProjectContext -and $gitStatusAfter -ne $gitStatusBefore) {
        throw 'Local installation changed the Git-visible working-tree status unexpectedly. Inspect the target before continuing.'
    }
}

Write-Host "Installed $($entries.Count) template files in $targetRoot"
if ($Mode -eq 'Local') {
    Write-Host 'Workflow files are available to OpenCode but excluded only in this Git clone.'
    if ($ShareProjectContext) {
        Write-Host 'Project context sharing is enabled: .ai/project-rules.md and generated .ai/project.json remain Git-visible.'
    }
}
else {
    Write-Host 'Shared mode selected: workflow files remain Git-visible for optional version control.'
}
Write-Host 'Next:'
Write-Host "  cd `"$targetRoot`""
Write-Host '  opencode2'
Write-Host 'Then run /ai-bootstrap inside OpenCode to profile and personalize the repository.'
