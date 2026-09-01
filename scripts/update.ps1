[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [ValidateSet('Local', 'Shared')][string]$Mode,
    [switch]$ShareProjectContext,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Workflow.Common.ps1')

$targetRoot = Resolve-WorkflowTarget -TargetPath $TargetPath -MustExist
$metadataPath = Get-InstallationMetadataPath -TargetRoot $targetRoot
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Workflow installation metadata not found: $metadataPath"
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if (@(1, 2) -notcontains [int]$metadata.schemaVersion -or $metadata.workflowName -ne 'ai-engineering-workflow') {
    throw 'Unsupported or invalid workflow installation metadata.'
}

$installedMode = if ([int]$metadata.schemaVersion -eq 2) {
    ([string]$metadata.installationMode).ToLowerInvariant()
}
else {
    'shared'
}
if (@('local', 'shared') -notcontains $installedMode) {
    throw "Unsupported installation mode in metadata: $installedMode"
}
$requestedMode = if ($PSBoundParameters.ContainsKey('Mode')) { $Mode } else { $installedMode }
$requestedShareProjectContext = if ($PSBoundParameters.ContainsKey('ShareProjectContext')) {
    $ShareProjectContext.IsPresent
}
elseif ([int]$metadata.schemaVersion -eq 2) {
    [bool]$metadata.shareProjectContext
}
else {
    $false
}
if ($requestedMode -eq 'Shared') {
    if ($PSBoundParameters.ContainsKey('ShareProjectContext') -and $ShareProjectContext.IsPresent) {
        throw 'ShareProjectContext is valid only with Mode Local.'
    }
    $requestedShareProjectContext = $false
}

$oldFiles = @{}
foreach ($record in @($metadata.managedFiles)) {
    $oldFiles[[string]$record.path] = [string]$record.sha256
}

$newEntries = @(Get-TemplateFileRecords)
$newFiles = @{}
foreach ($entry in $newEntries) {
    $newFiles[$entry.Path] = $entry
}

$conflicts = @()
$changes = @()
$preserved = @()
$mutableManagedPaths = @('.ai/project-rules.md')
foreach ($entry in $newEntries) {
    $destination = Join-Path $targetRoot (ConvertTo-NativeRelativePath -RelativePath $entry.Path)
    $oldHash = $oldFiles[$entry.Path]
    if ($oldHash) {
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            $conflicts += "$($entry.Path) (managed file is missing)"
            continue
        }
        $targetHash = Get-FileSha256 -Path $destination
        if ($targetHash -ne $oldHash -and $targetHash -ne $entry.Sha256) {
            if ($mutableManagedPaths -contains $entry.Path) {
                $preserved += $entry.Path
                continue
            }
            else {
                $conflicts += "$($entry.Path) (locally modified)"
                continue
            }
        }
        if ($targetHash -ne $entry.Sha256) {
            $changes += $entry.Path
        }
    }
    else {
        if (Test-Path -LiteralPath $destination) {
            if ((Get-FileSha256 -Path $destination) -ne $entry.Sha256) {
                $conflicts += "$($entry.Path) (new template path already exists)"
                continue
            }
        }
        else {
            $changes += $entry.Path
        }
    }
}

$stale = @($oldFiles.Keys | Where-Object { -not $newFiles.ContainsKey($_) } | Sort-Object)
$gitRepository = $null
$excludePatterns = @()
$localPaths = @()

if ($requestedMode -eq 'Local' -or $installedMode -eq 'local') {
    $gitRepository = Get-GitRepositoryInfo -TargetRoot $targetRoot
    Get-WorkflowExcludeBlockState -ExcludePath $gitRepository.ExcludePath | Out-Null
}

if ($requestedMode -eq 'Local') {
    $currentPatterns = @(Get-LocalExcludePatterns -ManagedFiles $newEntries -ShareProjectContext $requestedShareProjectContext)
    $legacyLocalPaths = if ([int]$metadata.schemaVersion -eq 2 -and $metadata.PSObject.Properties.Name -contains 'localExcludedPaths') {
        @($metadata.localExcludedPaths | ForEach-Object { [string]$_ })
    }
    else {
        @($oldFiles.Keys)
    }
    $localPaths = @(
        @($currentPatterns | ForEach-Object { $_.TrimStart('/') })
        $legacyLocalPaths
    ) | Sort-Object -Unique
    if ($requestedShareProjectContext) {
        $localPaths = @($localPaths | Where-Object { $_ -notin @('.ai/project-rules.md', '.ai/project.json') })
    }
    $excludePatterns = @($localPaths | ForEach-Object { '/' + $_.Replace('\', '/') })
    $trackedLocalPaths = @(Test-LocalPathsAreUntracked -GitRepository $gitRepository -RelativePaths $localPaths)
    if ($trackedLocalPaths.Count -gt 0) {
        Write-Host 'Tracked paths cannot be hidden by a local installation:'
        $trackedLocalPaths | ForEach-Object { Write-Host "  - $_" }
        throw 'Update to local mode aborted. Keep Shared mode or untrack the listed paths deliberately.'
    }
}

Write-Host "Installed version: $($metadata.workflowVersion)"
Write-Host "Available version: $(Get-WorkflowVersion)"
Write-Host "Installed mode: $installedMode"
Write-Host "Requested mode: $requestedMode"
Write-Host "Share project context: $requestedShareProjectContext"
Write-Host "Files to add or update: $($changes.Count)"
Write-Host "Locally customized mutable files preserved: $($preserved.Count)"
Write-Host "Retired files kept in target: $($stale.Count)"

if ($conflicts.Count -gt 0) {
    Write-Host 'Conflicts:'
    $conflicts | Sort-Object | ForEach-Object { Write-Host "  - $_" }
    throw 'Update aborted before copying; resolve conflicts or preserve the current installation.'
}

if ($stale.Count -gt 0) {
    Write-Host 'Retired template paths left untouched:'
    $stale | ForEach-Object { Write-Host "  - $_" }
}

if ($preserved.Count -gt 0) {
    Write-Host 'Locally customized project context preserved:'
    $preserved | Sort-Object | ForEach-Object { Write-Host "  - $_" }
}

if ($DryRun) {
    Write-Host 'DRY RUN: update can proceed without conflicts.'
    if ($requestedMode -eq 'Local') {
        Write-Host "Git exclude file: $($gitRepository.ExcludePath)"
        Write-Host "Locally excluded paths: $($excludePatterns.Count)"
    }
    return
}

foreach ($entry in $newEntries) {
    if ($changes -notcontains $entry.Path) { continue }
    $destination = Join-Path $targetRoot (ConvertTo-NativeRelativePath -RelativePath $entry.Path)
    $destinationDirectory = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $entry.Source -Destination $destination -Force
}

if ($requestedMode -eq 'Local') {
    Set-WorkflowGitExclude -ExcludePath $gitRepository.ExcludePath -Mode Local -Patterns $excludePatterns
}
elseif ($installedMode -eq 'local') {
    Set-WorkflowGitExclude -ExcludePath $gitRepository.ExcludePath -Mode Shared
}

Write-InstallationMetadata `
    -TargetRoot $targetRoot `
    -ManagedFiles $newEntries `
    -InstallationMode $requestedMode `
    -ShareProjectContext $requestedShareProjectContext `
    -LocalExcludedPaths $localPaths

if ($requestedMode -eq 'Local') {
    Assert-LocalPathsIgnored -GitRepository $gitRepository -RelativePaths $localPaths
}
Write-Host "Workflow updated to version $(Get-WorkflowVersion)."
Write-Host "Installation mode: $requestedMode"
