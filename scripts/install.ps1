[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Workflow.Common.ps1')

$targetRoot = Resolve-WorkflowTarget -TargetPath $TargetPath -MustExist
$entries = @(Get-TemplateFileRecords)
$metadataPath = Get-InstallationMetadataPath -TargetRoot $targetRoot

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
Write-Host "Template files: $($entries.Count)"

if ($conflicts.Count -gt 0) {
    Write-Host 'Conflicts:'
    $conflicts | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" }
    throw 'Installation aborted before copying; no files were overwritten.'
}

if ($DryRun) {
    Write-Host 'DRY RUN: installation can proceed without conflicts.'
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

Write-InstallationMetadata -TargetRoot $targetRoot -ManagedFiles $entries

Write-Host "Installed $($entries.Count) template files in $targetRoot"
Write-Host 'Next:'
Write-Host "  cd `"$targetRoot`""
Write-Host '  opencode2'
Write-Host 'Then run /ai-bootstrap inside OpenCode.'
