[CmdletBinding()]
param(
    [string]$Remote = 'origin'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to publish a branch.' }
if ($Remote -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid remote name: $Remote" }

$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The current location is not inside a Git repository.'
}
$repositoryRoot = $repositoryRoot.Trim()
$branch = (& $gitCommand.Source -C $repositoryRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'Publishing requires a named branch; detached HEAD is not supported.'
}
if ($branch -match '^(main|master|develop|development|trunk|release)(/|$)') {
    throw "Refusing to push protected or shared branch '$branch'."
}

$status = @(& $gitCommand.Source -C $repositoryRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the working tree.' }
if ($status.Count -gt 0) { throw 'Publishing requires a completely clean working tree.' }

$remoteUrl = (& $gitCommand.Source -C $repositoryRoot remote get-url $Remote 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
    throw "Remote '$Remote' is not configured."
}
$head = (& $gitCommand.Source -C $repositoryRoot rev-parse HEAD).Trim()

Write-Output "Publishing $head from '$branch' to '$Remote' ($($remoteUrl.Trim()))."
& $gitCommand.Source -C $repositoryRoot push --set-upstream $Remote ("HEAD:refs/heads/" + $branch)
if ($LASTEXITCODE -ne 0) {
    throw 'Normal push failed. The workflow will not retry with force or force-with-lease.'
}
Write-Output "Published '$branch' without force."
