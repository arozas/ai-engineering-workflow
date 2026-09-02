[CmdletBinding()]
param(
    [ValidateRange(10, 120)][int]$StartupTimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$distributionRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)

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

function Resolve-OpenCodeCommandSource {
    $commands = @()
    foreach ($commandName in @('opencode2', 'opencode')) {
        $commands += @(Get-Command $commandName -All -ErrorAction SilentlyContinue)
    }
    if ($commands.Count -eq 0) { throw 'OpenCode CLI was not found. Install @opencode-ai/cli@beta before running the smoke test.' }

    foreach ($command in $commands) {
        $source = [string]$command.Source
        if ([string]::IsNullOrWhiteSpace($source)) { continue }

        $extension = [IO.Path]::GetExtension($source)
        if ($isWindowsPlatform -and [string]::IsNullOrEmpty($extension)) {
            foreach ($candidateExtension in @('.cmd', '.ps1', '.exe', '.bat')) {
                $candidate = "$source$candidateExtension"
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
            continue
        }

        return $source
    }

    throw 'OpenCode CLI was found, but no executable Windows shim could be resolved.'
}

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

function Get-TextFileContent {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-Content -LiteralPath $Path -Raw)
    }
    return ''
}

function Get-OpenCodeServerFailureDetails {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$ServerProcess)

    $exitStatus = if ($ServerProcess.HasExited) { "exited with code $($ServerProcess.ExitCode)" } else { 'still running' }
    $stdout = (Get-TextFileContent -Path $stdoutPath).Trim()
    $stderr = (Get-TextFileContent -Path $stderrPath).Trim()
    return "Process: $exitStatus. Stdout: $stdout Stderr: $stderr"
}

function Invoke-OpenCodeEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $errors = @()
    foreach ($path in $Paths) {
        try {
            return Invoke-RestMethod -Uri "$BaseUrl$path" -TimeoutSec 10
        }
        catch {
            $errors += "${path}: $($_.Exception.Message)"
        }
    }

    throw "Unable to load OpenCode $Description. Tried: $($errors -join '; ')"
}

function Start-OpenCodeServer {
    param(
        [Parameter(Mandatory = $true)][string]$CommandSource,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$StandardOutputPath,
        [Parameter(Mandatory = $true)][string]$StandardErrorPath
    )

    $serverArguments = @('serve', '--hostname', '127.0.0.1', '--port', [string]$Port)
    $extension = [IO.Path]::GetExtension($CommandSource).ToLowerInvariant()

    switch ($extension) {
        '.cmd' {
            $filePath = (Get-Command cmd.exe -ErrorAction Stop).Source
            $argumentList = @('/d', '/s', '/c', "`"$CommandSource`" $($serverArguments -join ' ')")
        }
        '.bat' {
            $filePath = (Get-Command cmd.exe -ErrorAction Stop).Source
            $argumentList = @('/d', '/s', '/c', "`"$CommandSource`" $($serverArguments -join ' ')")
        }
        '.ps1' {
            $filePath = (Get-Command pwsh -ErrorAction Stop).Source
            $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $CommandSource) + $serverArguments
        }
        default {
            $filePath = $CommandSource
            $argumentList = $serverArguments
        }
    }

    return Start-Process -FilePath $filePath `
        -ArgumentList $argumentList `
        -WorkingDirectory $WorkingDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $StandardOutputPath `
        -RedirectStandardError $StandardErrorPath `
        -PassThru
}

function Stop-OpenCodeServer {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$ServerProcess)

    if ($ServerProcess.HasExited) { return }

    if ($isWindowsPlatform) {
        $taskkillCommand = Get-Command taskkill.exe -ErrorAction SilentlyContinue
        if ($null -ne $taskkillCommand) {
            & $taskkillCommand.Source /PID $ServerProcess.Id /T /F | Out-Null
            $ServerProcess.WaitForExit(5000) | Out-Null
            return
        }
    }

    Stop-Process -Id $ServerProcess.Id -Force -ErrorAction SilentlyContinue
    $ServerProcess.WaitForExit(5000) | Out-Null
}

function Remove-SmokeTestRoot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath)) { return }

    $resolved = [IO.Path]::GetFullPath($RootPath)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($resolved)).StartsWith('ai-engineering-workflow-opencode-smoke-', [StringComparison]::Ordinal)) {
        throw "Unsafe smoke-test cleanup target: $resolved"
    }

    foreach ($attempt in 1..5) {
        try {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if ($attempt -eq 5) {
                Write-Warning "Unable to remove smoke-test temporary directory '$resolved': $($_.Exception.Message)"
                return
            }
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }
}

try {
    $opencodeCommandSource = Resolve-OpenCodeCommandSource

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
    $process = Start-OpenCodeServer `
        -CommandSource $opencodeCommandSource `
        -WorkingDirectory $consumerRoot `
        -Port $port `
        -StandardOutputPath $stdoutPath `
        -StandardErrorPath $stderrPath

    $baseUrl = "http://127.0.0.1:$port"
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $healthy = $false
    $healthPaths = @('/api/health', '/global/health')
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) { break }
        foreach ($healthPath in $healthPaths) {
            try {
                $health = Invoke-RestMethod -Uri "$baseUrl$healthPath" -TimeoutSec 2
                if ($health.healthy -eq $true) { $healthy = $true; break }
            }
            catch { }
        }
        if ($healthy) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) {
        throw "OpenCode server did not become healthy. $(Get-OpenCodeServerFailureDetails -ServerProcess $process)"
    }

    $agents = @(Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/agent', '/api/agent') -Description 'agents')
    $commands = @(Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/command', '/api/command') -Description 'commands')
    $toolIds = @(Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/experimental/tool/ids', '/api/experimental/tool/ids') -Description 'typed tool IDs')
    $agentNames = Get-DefinitionNames -Definitions $agents
    $commandNames = Get-DefinitionNames -Definitions $commands

    $expectedAgents = @('orchestrator', 'developer', 'reviewer', 'tester', 'delivery', 'diagnostician', 'quick-fix', 'quick-reviewer')
    $expectedCommands = @('ai-bootstrap', 'ai-refresh', 'branch', 'commit', 'delivery-check', 'diagnose', 'explain', 'implement', 'pr', 'pr-create', 'publish', 'quick-fix', 'review', 'run-status', 'small-task', 'test', 'ticket')
    $expectedTools = @('workflow_state', 'workflow_standard_review', 'workflow_quick_review', 'workflow_gate', 'workflow_fast_path', 'workflow_validate_project', 'workflow_profile_project', 'workflow_validate_diagnosis', 'workflow_delivery_check')
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
        Stop-OpenCodeServer -ServerProcess $process
    }
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    Remove-SmokeTestRoot -RootPath $testRoot
}
