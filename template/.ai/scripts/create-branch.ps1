[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'Git is required to create a branch.' }

$repositoryRoot = (& $gitCommand.Source rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The current location is not inside a Git repository.'
}
$repositoryRoot = $repositoryRoot.Trim()

& $gitCommand.Source check-ref-format --branch $Name *> $null
if ($LASTEXITCODE -ne 0) { throw "Invalid branch name: $Name" }
if ($Name -match '^(main|master|develop|development|trunk|release)(/|$)') {
    throw "Refusing to create a protected or shared branch name: $Name"
}

$status = @(& $gitCommand.Source -C $repositoryRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the working tree.' }
if ($status.Count -gt 0) {
    throw 'Branch creation requires a clean working tree.'
}

& $gitCommand.Source -C $repositoryRoot show-ref --verify --quiet ("refs/heads/" + $Name)
if ($LASTEXITCODE -eq 0) { throw "Local branch already exists: $Name" }

& $gitCommand.Source -C $repositoryRoot switch -c $Name
if ($LASTEXITCODE -ne 0) { throw "Git failed to create branch: $Name" }

$head = (& $gitCommand.Source -C $repositoryRoot rev-parse HEAD).Trim()
Write-Output "Created branch '$Name' at $head."
