Set-StrictMode -Version Latest

function Get-WorkflowRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-WorkflowManifest {
    $manifestPath = Join-Path (Get-WorkflowRoot) 'workflow.manifest.json'
    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Get-WorkflowVersion {
    $version = (Get-Content -LiteralPath (Join-Path (Get-WorkflowRoot) 'VERSION') -Raw).Trim()
    if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
        throw "Invalid workflow version: $version"
    }
    return $version
}

function Get-TemplateRoot {
    $manifest = Get-WorkflowManifest
    return [System.IO.Path]::GetFullPath((Join-Path (Get-WorkflowRoot) $manifest.templatePath))
}

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the expected root: $pathFull"
    }
    return $pathFull.Substring($rootFull.Length + 1).Replace('\', '/')
}

function ConvertTo-NativeRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-TemplateFileRecords {
    $templateRoot = Get-TemplateRoot
    if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
        throw "Template directory not found: $templateRoot"
    }

    return @(
        Get-ChildItem -LiteralPath $templateRoot -Recurse -File |
            ForEach-Object {
                [pscustomobject]@{
                    Path = Get-NormalizedRelativePath -Root $templateRoot -Path $_.FullName
                    Source = $_.FullName
                    Sha256 = Get-FileSha256 -Path $_.FullName
                }
            } |
            Sort-Object Path
    )
}

function Resolve-WorkflowTarget {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [switch]$MustExist
    )

    $targetFull = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\', '/')
    $workflowRoot = (Get-WorkflowRoot).TrimEnd('\', '/')
    if ($targetFull -eq $workflowRoot -or $targetFull.StartsWith($workflowRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The target must be outside the workflow distribution repository.'
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $targetFull -PathType Container)) {
        throw "Target directory does not exist: $targetFull"
    }
    return $targetFull
}

function Get-InstallationMetadataPath {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)
    $manifest = Get-WorkflowManifest
    return Join-Path $TargetRoot (ConvertTo-NativeRelativePath -RelativePath $manifest.installationMetadata)
}

function Write-InstallationMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][array]$ManagedFiles
    )

    $metadataPath = Get-InstallationMetadataPath -TargetRoot $TargetRoot
    $metadataDirectory = Split-Path -Parent $metadataPath
    if (-not (Test-Path -LiteralPath $metadataDirectory)) {
        New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
    }

    $metadata = [ordered]@{
        schemaVersion = 1
        workflowName = 'ai-engineering-workflow'
        workflowVersion = Get-WorkflowVersion
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        managedFiles = @(
            $ManagedFiles |
                Sort-Object Path |
                ForEach-Object {
                    [ordered]@{
                        path = $_.Path
                        sha256 = $_.Sha256
                    }
                }
        )
    }

    $temporaryMetadataPath = $metadataPath + '.tmp'
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryMetadataPath -Encoding utf8
    Move-Item -LiteralPath $temporaryMetadataPath -Destination $metadataPath -Force
}

function Expand-WorkflowTokens {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][hashtable]$Tokens
    )

    $expanded = $Value
    foreach ($key in $Tokens.Keys) {
        $expanded = $expanded.Replace('{{' + $key + '}}', [string]$Tokens[$key])
    }
    return $expanded
}
