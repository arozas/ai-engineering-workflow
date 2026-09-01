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

function Get-GitRepositoryInfo {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw 'Local installation requires Git, but git was not found in PATH.'
    }

    $topLevelOutput = @(& $gitCommand.Source -C $TargetRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $topLevelOutput.Count -ne 1) {
        throw "Local installation requires an initialized Git repository: $TargetRoot"
    }

    $topLevel = [System.IO.Path]::GetFullPath([string]$topLevelOutput[0]).TrimEnd('\', '/')
    $targetFull = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd('\', '/')
    if ($topLevel -ne $targetFull) {
        throw "The local workflow must be installed at the Git repository root. Repository root: $topLevel"
    }

    $excludeOutput = @(& $gitCommand.Source -C $TargetRoot rev-parse --path-format=absolute --git-path info/exclude 2>$null)
    if ($LASTEXITCODE -ne 0 -or $excludeOutput.Count -ne 1) {
        throw 'Unable to resolve the repository-local Git exclude file.'
    }

    return [pscustomobject]@{
        Command = $gitCommand.Source
        Root = $topLevel
        ExcludePath = [System.IO.Path]::GetFullPath([string]$excludeOutput[0])
    }
}

function Get-LocalExcludePatterns {
    param(
        [Parameter(Mandatory = $true)][array]$ManagedFiles,
        [bool]$ShareProjectContext = $false
    )

    $sharedPaths = @('.ai/project-rules.md', '.ai/project.json')
    $generatedPaths = @(
        '.ai/bootstrap-input.json',
        '.ai/pr-draft.md',
        '.ai/project.json',
        '.ai/workflow-installation.json',
        '.ai/workflow-installation.json.tmp'
    )

    $paths = @(
        @($ManagedFiles | ForEach-Object { [string]$_.Path })
        $generatedPaths
    )

    return @(
        $paths |
            Where-Object {
                -not ($ShareProjectContext -and $sharedPaths -contains $_)
            } |
            ForEach-Object { '/' + $_.Replace('\', '/') } |
            Sort-Object -Unique
    )
}

function Get-WorkflowExcludeBlockState {
    param([Parameter(Mandatory = $true)][string]$ExcludePath)

    $beginMarker = '# BEGIN ai-engineering-workflow'
    $endMarker = '# END ai-engineering-workflow'
    $lines = if (Test-Path -LiteralPath $ExcludePath -PathType Leaf) {
        @(Get-Content -LiteralPath $ExcludePath)
    }
    else {
        @()
    }

    $beginIndexes = @(
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -eq $beginMarker) { $index }
        }
    )
    $endIndexes = @(
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -eq $endMarker) { $index }
        }
    )

    if ($beginIndexes.Count -eq 0 -and $endIndexes.Count -eq 0) {
        return [pscustomobject]@{
            State = 'Absent'
            Lines = $lines
            BeginIndex = -1
            EndIndex = -1
        }
    }

    if ($beginIndexes.Count -ne 1 -or $endIndexes.Count -ne 1 -or $beginIndexes[0] -ge $endIndexes[0]) {
        throw "Malformed ai-engineering-workflow block in Git exclude file: $ExcludePath"
    }

    return [pscustomobject]@{
        State = 'Present'
        Lines = $lines
        BeginIndex = [int]$beginIndexes[0]
        EndIndex = [int]$endIndexes[0]
    }
}

function Set-WorkflowGitExclude {
    param(
        [Parameter(Mandatory = $true)][string]$ExcludePath,
        [Parameter(Mandatory = $true)][ValidateSet('Local', 'Shared')][string]$Mode,
        [string[]]$Patterns = @()
    )

    $state = Get-WorkflowExcludeBlockState -ExcludePath $ExcludePath
    $remainingLines = @($state.Lines)
    if ($state.State -eq 'Present') {
        $remainingLines = @(
            if ($state.BeginIndex -gt 0) {
                $state.Lines[0..($state.BeginIndex - 1)]
            }
            if ($state.EndIndex + 1 -lt $state.Lines.Count) {
                $state.Lines[($state.EndIndex + 1)..($state.Lines.Count - 1)]
            }
        )
    }

    $newLines = @($remainingLines)
    if ($Mode -eq 'Local') {
        if ($Patterns.Count -eq 0) {
            throw 'Local installation requires at least one Git exclude pattern.'
        }
        if ($newLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$newLines[-1])) {
            $newLines += ''
        }
        $newLines += '# BEGIN ai-engineering-workflow'
        $newLines += @($Patterns | Sort-Object -Unique)
        $newLines += '# END ai-engineering-workflow'
    }

    $excludeDirectory = Split-Path -Parent $ExcludePath
    if (-not (Test-Path -LiteralPath $excludeDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $excludeDirectory -Force | Out-Null
    }
    $temporaryPath = $ExcludePath + '.ai-engineering-workflow.tmp'
    try {
        if ($newLines.Count -eq 0) {
            Set-Content -LiteralPath $temporaryPath -Value '' -Encoding utf8
        }
        else {
            Set-Content -LiteralPath $temporaryPath -Value $newLines -Encoding utf8
        }
        Move-Item -LiteralPath $temporaryPath -Destination $ExcludePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Test-LocalPathsAreUntracked {
    param(
        [Parameter(Mandatory = $true)]$GitRepository,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    $tracked = @()
    foreach ($relativePath in $RelativePaths) {
        & $GitRepository.Command -C $GitRepository.Root ls-files --error-unmatch -- $relativePath *> $null
        if ($LASTEXITCODE -eq 0) {
            $tracked += $relativePath
        }
    }
    return @($tracked | Sort-Object -Unique)
}

function Get-GitStatusSnapshot {
    param([Parameter(Mandatory = $true)]$GitRepository)
    return (@(& $GitRepository.Command -C $GitRepository.Root status --porcelain=v1 --untracked-files=all) -join "`n")
}

function Assert-LocalPathsIgnored {
    param(
        [Parameter(Mandatory = $true)]$GitRepository,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    $notIgnored = @()
    foreach ($relativePath in $RelativePaths) {
        $absolutePath = Join-Path $GitRepository.Root (ConvertTo-NativeRelativePath -RelativePath $relativePath)
        if (-not (Test-Path -LiteralPath $absolutePath)) { continue }
        & $GitRepository.Command -C $GitRepository.Root check-ignore --no-index --quiet -- $relativePath
        if ($LASTEXITCODE -ne 0) {
            $notIgnored += $relativePath
        }
    }
    if ($notIgnored.Count -gt 0) {
        throw "Local installation paths are not ignored by Git: $($notIgnored -join ', ')"
    }
}

function Write-InstallationMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][array]$ManagedFiles,
        [Parameter(Mandatory = $true)][ValidateSet('Local', 'Shared')][string]$InstallationMode,
        [bool]$ShareProjectContext = $false,
        [string[]]$LocalExcludedPaths = @()
    )

    $metadataPath = Get-InstallationMetadataPath -TargetRoot $TargetRoot
    $metadataDirectory = Split-Path -Parent $metadataPath
    if (-not (Test-Path -LiteralPath $metadataDirectory)) {
        New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
    }

    $metadata = [ordered]@{
        schemaVersion = 2
        workflowName = 'ai-engineering-workflow'
        workflowVersion = Get-WorkflowVersion
        installationMode = $InstallationMode.ToLowerInvariant()
        shareProjectContext = [bool]$ShareProjectContext
        localExcludedPaths = @(
            if ($InstallationMode -eq 'Local') {
                $LocalExcludedPaths |
                    ForEach-Object { $_.Replace('\', '/').TrimStart('/') } |
                    Sort-Object -Unique
            }
        )
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
