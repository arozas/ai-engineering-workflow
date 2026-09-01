[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
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
if ($metadata.schemaVersion -ne 1 -or $metadata.workflowName -ne 'ai-engineering-workflow') {
    throw 'Unsupported or invalid workflow installation metadata.'
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
            $conflicts += "$($entry.Path) (locally modified)"
            continue
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

Write-Host "Installed version: $($metadata.workflowVersion)"
Write-Host "Available version: $(Get-WorkflowVersion)"
Write-Host "Files to add or update: $($changes.Count)"
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

if ($DryRun) {
    Write-Host 'DRY RUN: update can proceed without conflicts.'
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

Write-InstallationMetadata -TargetRoot $targetRoot -ManagedFiles $newEntries
Write-Host "Workflow updated to version $(Get-WorkflowVersion)."
