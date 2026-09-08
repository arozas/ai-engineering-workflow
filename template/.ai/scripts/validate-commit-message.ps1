[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

$normalized = $Message.Replace("`r`n", "`n").Trim()
$lines = @($normalized -split "`n")
$subject = $lines[0]
$subjectPattern = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9][a-z0-9._/-]*\))?!?: \S.*$'

if ($subject -notmatch $subjectPattern) {
    throw 'Commit subject must follow Conventional Commits: type(optional-scope)(optional-!): description.'
}
if ($subject.Length -gt 72) {
    throw "Commit subject exceeds 72 characters: $($subject.Length)"
}
if ($lines.Count -gt 1 -and $lines[1] -ne '') {
    throw 'A multi-line commit message requires a blank line between subject and body.'
}

$agentIdentity = '(claude|anthropic|codex|openai|chatgpt|copilot|gemini|cursor|opencode|ai[- ]?agent|artificial intelligence)'
$forbiddenAttribution = @(
    "(?im)^(co-authored-by|generated-by|created-by|authored-by)\s*:.*$agentIdentity",
    "(?i)\b(by\s*claude|byclaude|by\s*codex|bycodex|by\s*chatgpt|bychatgpt|by\s*copilot|bycopilot)\b",
    "(?i)generated\s+(with|by)\s+.*$agentIdentity"
)
foreach ($pattern in $forbiddenAttribution) {
    if ($normalized -match $pattern) {
        throw 'Commit messages must not attribute authorship or co-authorship to an AI agent.'
    }
}

Write-Output "VALID: $subject"
