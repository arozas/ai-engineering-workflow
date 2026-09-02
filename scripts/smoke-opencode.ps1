[CmdletBinding()]
param(
    [ValidateRange(10, 120)][int]$StartupTimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$distributionRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$opencodeCommand = Get-Command opencode -ErrorAction SilentlyContinue
if ($null -eq $opencodeCommand) { throw 'OpenCode CLI was not found. Install opencode-ai before running the smoke test.' }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ai-engineering-workflow-opencode-smoke-' + [Guid]::NewGuid().ToString('N'))
$consumerRoot = Join-Path $testRoot 'consumer'
$stdoutPath = Join-Path $testRoot 'opencode.stdout.log'
$stderrPath = Join-Path $testRoot 'opencode.stderr.log'
$process = $null
$environmentNames = @(
    'NO_COLOR',
    'OPENCODE_CONFIG',
    'OPENCODE_CONFIG_CONTENT',
    'OPENCODE_CONFIG_DIR',
    'OPENCODE_SERVER_PASSWORD',
    'OPENCODE_DISABLE_AUTOUPDATE',
    'OPENCODE_DISABLE_DEFAULT_PLUGINS',
    'OPENCODE_DISABLE_LSP_DOWNLOAD',
    'OPENCODE_DISABLE_MODELS_FETCH'
)
$previousEnvironment = @{}

function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally { $listener.Stop() }
}

function Get-DefinitionNames([object[]]$Definitions) {
    return @(
        foreach ($definition in @($Definitions)) {
            if ($definition -is [string]) { [string]$definition; continue }
            if ($definition.PSObject.Properties.Name -contains 'name') { [string]$definition.name; continue }
            if ($definition.PSObject.Properties.Name -contains 'id') { [string]$definition.id }
        }
    )
}

try {
    New-Item -ItemType Directory -Path $consumerRoot -Force | Out-Null
    & git -C $consumerRoot init -b main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the OpenCode smoke-test repository.' }
    & git -C $consumerRoot config user.email 'opencode-smoke@example.invalid'
    & git -C $consumerRoot config user.name 'OpenCode Smoke Test'
    Set-Content -LiteralPath (Join-Path $consumerRoot 'README.md') -Value '# OpenCode smoke fixture' -Encoding utf8
    & git -C $consumerRoot add -- README.md
    & git -C $consumerRoot commit -m 'test: create opencode smoke fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the OpenCode smoke-test fixture.' }

    & pwsh -NoProfile -File (Join-Path $distributionRoot 'scripts\install.ps1') -TargetPath $consumerRoot -Mode Local | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to install the workflow for the OpenCode smoke test.' }

    foreach ($name in $environmentNames) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    [Environment]::SetEnvironmentVariable('NO_COLOR', '1', 'Process')
    foreach ($name in @('OPENCODE_CONFIG', 'OPENCODE_CONFIG_CONTENT', 'OPENCODE_CONFIG_DIR', 'OPENCODE_SERVER_PASSWORD')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    foreach ($name in @('OPENCODE_DISABLE_AUTOUPDATE', 'OPENCODE_DISABLE_DEFAULT_PLUGINS', 'OPENCODE_DISABLE_LSP_DOWNLOAD', 'OPENCODE_DISABLE_MODELS_FETCH')) {
        [Environment]::SetEnvironmentVariable($name, 'true', 'Process')
    }

    $port = Get-FreeTcpPort
    $process = Start-Process -FilePath $opencodeCommand.Source `
        -ArgumentList @('serve', '--hostname', '127.0.0.1', '--port', [string]$port) `
        -WorkingDirectory $consumerRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    $baseUrl = "http://127.0.0.1:$port"
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $healthy = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) { break }
        try {
            $health = Invoke-RestMethod -Uri "$baseUrl/global/health" -TimeoutSec 2
            if ($health.healthy -eq $true) { $healthy = $true; break }
        }
        catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $healthy) {
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
        throw "OpenCode server did not become healthy. $stderr"
    }

    $agents = @(Invoke-RestMethod -Uri "$baseUrl/agent" -TimeoutSec 10)
    $commands = @(Invoke-RestMethod -Uri "$baseUrl/command" -TimeoutSec 10)
    $toolIds = @(Invoke-RestMethod -Uri "$baseUrl/experimental/tool/ids" -TimeoutSec 10)
    $agentNames = Get-DefinitionNames -Definitions $agents
    $commandNames = Get-DefinitionNames -Definitions $commands

    $expectedAgents = @('orchestrator', 'developer', 'reviewer', 'tester', 'delivery', 'diagnostician', 'quick-fix', 'quick-reviewer')
    $expectedCommands = @('ai-bootstrap', 'ai-refresh', 'branch', 'commit', 'delivery-check', 'diagnose', 'explain', 'implement', 'pr', 'pr-create', 'publish', 'quick-fix', 'review', 'run-status', 'small-task', 'test', 'ticket')
    $expectedTools = @('workflow_state', 'workflow_gate', 'workflow_fast_path', 'workflow_validate_project', 'workflow_profile_project', 'workflow_validate_diagnosis', 'workflow_delivery_check')
    $missingAgents = @($expectedAgents | Where-Object { $agentNames -notcontains $_ })
    $missingCommands = @($expectedCommands | Where-Object { $commandNames -notcontains $_ })
    $missingTools = @($expectedTools | Where-Object { $toolIds -notcontains $_ })
    if ($missingAgents.Count -gt 0) { throw "OpenCode did not discover workflow agents: $($missingAgents -join ', ')." }
    if ($missingCommands.Count -gt 0) { throw "OpenCode did not discover workflow commands: $($missingCommands -join ', ')." }
    if ($missingTools.Count -gt 0) { throw "OpenCode did not load typed workflow tools: $($missingTools -join ', ')." }

    Write-Host "OpenCode smoke test passed: $($expectedAgents.Count) agents, $($expectedCommands.Count) commands, and $($expectedTools.Count) typed tools discovered."
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
    }
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolved)).StartsWith('ai-engineering-workflow-opencode-smoke-', [StringComparison]::Ordinal)) {
            throw "Unsafe smoke-test cleanup target: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
