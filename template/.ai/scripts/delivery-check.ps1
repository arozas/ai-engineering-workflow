[CmdletBinding()]
param(
    [string]$Remote = 'origin'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) {
    throw 'Git is required for delivery checks.'
}
if ($Remote -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Invalid remote name: $Remote"
}

$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The current location is not inside a Git repository.'
}
$repositoryRoot = $repositoryRoot.Trim()

$branch = (& $gitCommand.Source -C $repositoryRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'Delivery requires a named branch; detached HEAD is not supported.'
}
$head = (& $gitCommand.Source -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve HEAD.' }

$status = @(& $gitCommand.Source -C $repositoryRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the working tree.' }
$staged = @(& $gitCommand.Source -C $repositoryRoot diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect staged changes.' }
$unstaged = @(& $gitCommand.Source -C $repositoryRoot diff --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect unstaged changes.' }
$untracked = @(& $gitCommand.Source -C $repositoryRoot ls-files --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect untracked files.' }

$upstream = (& $gitCommand.Source -C $repositoryRoot rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
if ($LASTEXITCODE -ne 0) { $upstream = $null } else { $upstream = $upstream.Trim() }
$remoteUrl = (& $gitCommand.Source -C $repositoryRoot remote get-url $Remote 2>$null)
if ($LASTEXITCODE -ne 0) { $remoteUrl = $null } else { $remoteUrl = $remoteUrl.Trim() }

[ordered]@{
    repositoryRoot = $repositoryRoot
    branch = $branch
    head = $head
    remote = $Remote
    remoteUrl = $remoteUrl
    upstream = $upstream
    clean = ($status.Count -eq 0)
    staged = @($staged)
    unstaged = @($unstaged)
    untracked = @($untracked)
    porcelain = @($status)
} | ConvertTo-Json -Depth 5
