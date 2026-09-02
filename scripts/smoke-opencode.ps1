[CmdletBinding()]
param(
    [ValidateRange(10, 180)][int]$StartupTimeoutSeconds = 90
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
    'OPENCODE_SERVER_USERNAME',
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

function Get-DefinitionNames {
    param([AllowNull()][object]$Definitions)

    $names = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Definitions) { return @() }

    foreach ($definition in @($Definitions)) {
        if ($null -eq $definition) { continue }
        if ($definition -is [string]) {
            $names.Add([string]$definition)
            continue
        }

        if ($definition -is [System.Collections.IDictionary]) {
            foreach ($key in $definition.Keys) {
                $names.Add([string]$key)
                foreach ($nestedName in @(Get-DefinitionNames -Definitions $definition[$key])) { $names.Add($nestedName) }
            }
            continue
        }

        $properties = @($definition.PSObject.Properties)
        if (($properties | Where-Object { $_.Name -eq 'name' }).Count -gt 0) { $names.Add([string]$definition.name) }
        if (($properties | Where-Object { $_.Name -eq 'id' }).Count -gt 0) { $names.Add([string]$definition.id) }

        foreach ($property in $properties) {
            if ($property.Name -notin @('name', 'id', 'description')) { $names.Add([string]$property.Name) }
        }

        foreach ($collectionProperty in @('data', 'items', 'list')) {
            $property = $properties | Where-Object { $_.Name -eq $collectionProperty } | Select-Object -First 1
            if ($null -ne $property) {
                foreach ($nestedName in @(Get-DefinitionNames -Definitions $property.Value)) { $names.Add($nestedName) }
            }
        }
    }

    return @($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-TextFileContent {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $content = Get-Content -LiteralPath $Path -Raw
        if ($null -ne $content) { return [string]$content }
    }
    return ''
}

function Get-OpenCodeServerFailureDetails {
    param(
        [AllowNull()][System.Diagnostics.Process]$ServerProcess,
        [string[]]$HealthErrors = @()
    )

    $exitStatus = if ($null -eq $ServerProcess) {
        'not started'
    }
    elseif ($ServerProcess.HasExited) {
        "exited with code $($ServerProcess.ExitCode)"
    }
    else {
        "still running with PID $($ServerProcess.Id)"
    }
    $stdout = Hide-OpenCodeServerPassword -Value ([string](Get-TextFileContent -Path $stdoutPath)).Trim()
    $stderr = Hide-OpenCodeServerPassword -Value ([string](Get-TextFileContent -Path $stderrPath)).Trim()
    $healthDetails = if ($HealthErrors.Count -gt 0) { " Health checks: $($HealthErrors -join '; ')" } else { '' }
    return "Process: $exitStatus. Stdout: $stdout Stderr: $stderr$healthDetails"
}

function Hide-OpenCodeServerPassword {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return '' }
    return ($Value -replace '(?i)(server password\s+)\S+', '${1}<redacted>')
}

function Get-OpenCodeServerPassword {
    $stdout = Get-TextFileContent -Path $stdoutPath
    $match = [regex]::Match($stdout, '(?im)^server password\s+(\S+)\s*$')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-OpenCodeRequestHeaders {
    $password = Get-OpenCodeServerPassword
    if ([string]::IsNullOrWhiteSpace($password)) { return @{} }

    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("opencode:$password"))
    return @{ Authorization = "Basic $token" }
}

function Invoke-OpenCodeEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Description,
        [string]$Directory
    )

    $errors = @()
    foreach ($path in $Paths) {
        try {
            $uri = "$BaseUrl$path"
            if (-not [string]::IsNullOrWhiteSpace($Directory)) {
                $separator = if ($path.Contains('?')) { '&' } else { '?' }
                $uri = "$uri${separator}directory=$([uri]::EscapeDataString($Directory))"
            }
            return Invoke-RestMethod -Uri $uri -Headers (Get-OpenCodeRequestHeaders) -TimeoutSec 10
        }
        catch {
            $errors += Hide-OpenCodeServerPassword -Value "${path}: $($_.Exception.Message)"
        }
    }

    throw "Unable to load OpenCode $Description. Tried: $($errors -join '; ')"
}

function Format-DiscoveredNames {
    param([string[]]$Names)

    if ($Names.Count -eq 0) { return '<none>' }
    return ($Names | Select-Object -First 30) -join ', '
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
    foreach ($name in @('OPENCODE_CONFIG', 'OPENCODE_CONFIG_CONTENT', 'OPENCODE_CONFIG_DIR', 'OPENCODE_SERVER_USERNAME', 'OPENCODE_SERVER_PASSWORD')) {
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
    $healthErrors = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) { break }
        foreach ($healthPath in $healthPaths) {
            try {
                $health = Invoke-RestMethod -Uri "$baseUrl$healthPath" -Headers (Get-OpenCodeRequestHeaders) -TimeoutSec 2
                if ($health.healthy -eq $true) { $healthy = $true; break }
            }
            catch {
                $healthErrors += Hide-OpenCodeServerPassword -Value "${healthPath}: $($_.Exception.Message)"
                if ($healthErrors.Count -gt 8) { $healthErrors = @($healthErrors | Select-Object -Last 8) }
            }
        }
        if ($healthy) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) {
        throw "OpenCode server did not become healthy. $(Get-OpenCodeServerFailureDetails -ServerProcess $process -HealthErrors $healthErrors)"
    }

    $agents = Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/api/agent', '/agent') -Description 'agents' -Directory $consumerRoot
    $commands = Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/api/command', '/command') -Description 'commands' -Directory $consumerRoot
    $toolIds = @(Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/api/experimental/tool/ids', '/experimental/tool/ids') -Description 'typed tool IDs' -Directory $consumerRoot)
    $agentNames = Get-DefinitionNames -Definitions $agents
    $commandNames = Get-DefinitionNames -Definitions $commands
    $toolNames = Get-DefinitionNames -Definitions $toolIds

    $expectedAgents = @('orchestrator', 'developer', 'reviewer', 'tester', 'delivery', 'diagnostician', 'quick-fix', 'quick-reviewer')
    $expectedCommands = @('ai-bootstrap', 'ai-refresh', 'branch', 'commit', 'delivery-check', 'diagnose', 'explain', 'implement', 'pr', 'pr-create', 'publish', 'quick-fix', 'review', 'run-status', 'small-task', 'test', 'ticket')
    $expectedTools = @('workflow_state', 'workflow_standard_review', 'workflow_quick_review', 'workflow_gate', 'workflow_fast_path', 'workflow_validate_project', 'workflow_profile_project', 'workflow_validate_diagnosis', 'workflow_delivery_check')
    $missingAgents = @($expectedAgents | Where-Object { $agentNames -notcontains $_ })
    $missingCommands = @($expectedCommands | Where-Object { $commandNames -notcontains $_ })
    $missingTools = @($expectedTools | Where-Object { $toolNames -notcontains $_ })
    if ($missingAgents.Count -gt 0) { throw "OpenCode did not discover workflow agents: $($missingAgents -join ', '). Discovered: $(Format-DiscoveredNames -Names $agentNames)." }
    if ($missingCommands.Count -gt 0) { throw "OpenCode did not discover workflow commands: $($missingCommands -join ', '). Discovered: $(Format-DiscoveredNames -Names $commandNames)." }
    if ($missingTools.Count -gt 0) { throw "OpenCode did not load typed workflow tools: $($missingTools -join ', '). Discovered: $(Format-DiscoveredNames -Names $toolNames)." }

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
