[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

$resolvedCommands = @(
    Get-Command opencode2 -All -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Source) } |
        Group-Object Source |
        ForEach-Object { $_.Group[0] }
)
$selectedCommand = Get-Command opencode2 -ErrorAction SilentlyContinue
$selectedPath = if ($null -eq $selectedCommand) { $null } else { [string]$selectedCommand.Source }
$installations = @(
    foreach ($commandGroup in @($resolvedCommands | Group-Object { [IO.Path]::GetDirectoryName([string]$_.Source) })) {
        $sources = @($commandGroup.Group | ForEach-Object { [string]$_.Source } | Sort-Object -Unique)
        $probePath = @($sources | Where-Object { [IO.Path]::GetExtension($_) -in @('.cmd', '.bat') } | Select-Object -First 1)
        if ($probePath.Count -eq 0) { $probePath = @($sources | Where-Object { [IO.Path]::GetExtension($_) -eq '.ps1' } | Select-Object -First 1) }
        if ($probePath.Count -eq 0) { $probePath = @($sources | Select-Object -First 1) }
        $probePath = [string]$probePath[0]
        $versionOutput = @()
        $succeeded = $false
        try {
            $LASTEXITCODE = 0
            $extension = [IO.Path]::GetExtension($probePath).ToLowerInvariant()
            if ($extension -in @('.cmd', '.bat')) {
                $versionOutput = @(& $env:ComSpec /d /s /c "`"$probePath`" --version" 2>&1)
            }
            elseif ($extension -eq '.ps1') {
                $versionOutput = @(& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $probePath --version 2>&1)
            }
            else {
                $versionOutput = @(& $probePath --version 2>&1)
            }
            $succeeded = $? -and $LASTEXITCODE -eq 0
        }
        catch {
            $versionOutput = @($_.Exception.Message)
        }
        [ordered]@{
            directory = [string]$commandGroup.Name
            shims = $sources
            probePath = $probePath
            version = if ($succeeded) { (($versionOutput | ForEach-Object { [string]$_ }) -join ' ').Trim() } else { $null }
            callable = $succeeded
            selected = @($sources | Where-Object { [string]::Equals($_, $selectedPath, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        }
    }
)

$warnings = [Collections.Generic.List[string]]::new()
if ($installations.Count -eq 0) {
    $warnings.Add('opencode2 was not found in PATH.')
}
if ($installations.Count -gt 1) {
    $warnings.Add("Multiple opencode2 commands are visible in PATH; the selected command is '$selectedPath'.")
}
$versions = @($installations | Where-Object callable | ForEach-Object version | Sort-Object -Unique)
if ($versions.Count -gt 1) {
    $warnings.Add('Visible opencode2 commands report different versions. Fix PATH ordering before compatibility testing.')
}
if (@($installations | Where-Object { -not $_.callable }).Count -gt 0) {
    $warnings.Add('At least one visible opencode2 command could not be executed.')
}

[ordered]@{
    verdict = if ($installations.Count -eq 0) { 'RUNTIME_BLOCKED' } elseif ($warnings.Count -gt 0) { 'RUNTIME_WARNING' } else { 'RUNTIME_READY' }
    powerShell = [ordered]@{
        version = $PSVersionTable.PSVersion.ToString()
        executable = (Get-Process -Id $PID).Path
        minimumMajor = 7
    }
    selectedOpenCode = $selectedPath
    installations = $installations
    warnings = @($warnings)
    nextStep = if ($warnings.Count -gt 0) { 'Resolve runtime warnings, restart the terminal and OpenCode, then rerun this check.' } else { 'Runtime preflight passed.' }
} | ConvertTo-Json -Depth 6
