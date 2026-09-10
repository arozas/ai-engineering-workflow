[CmdletBinding()]
param(
    [ValidateRange(10, 180)][int]$StartupTimeoutSeconds = 90,
    [switch]$AllowLegacyOpenCodeFallback,
    [switch]$RequireRuntimeDiscovery,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AI Engineering Workflow requires PowerShell 7 or newer. Run this script with pwsh, not powershell.'
}

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
    param([bool]$AllowLegacyFallback = $false)

    $commands = @()
    $commandNames = if ($AllowLegacyFallback) { @('opencode2', 'opencode') } else { @('opencode2') }
    foreach ($commandName in $commandNames) {
        $commands += @(Get-Command $commandName -All -ErrorAction SilentlyContinue)
    }
    if (@($commands).Count -eq 0) {
        throw 'OpenCode V2 CLI was not found. Install @opencode-ai/cli@beta and verify opencode2 --version before running the smoke test.'
    }

    foreach ($command in $commands) {
        $source = [string]$command.Source
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        $commandName = [string]$command.Name
        if (-not $AllowLegacyFallback -and $commandName -ne 'opencode2') { continue }

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

function Assert-SmokeSelfTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw "SMOKE SELF-TEST FAILED: $Message" }
    $script:selfTestPassed++
}

function Get-WindowsCommandInvocation {
    param(
        [Parameter(Mandatory = $true)][string]$CommandSource,
        [Parameter(Mandatory = $true)][string[]]$CommandArguments
    )

    return ('""{0}" {1}"' -f $CommandSource, ($CommandArguments -join ' '))
}

function Get-WorkflowToolNamesFromSource {
    param([Parameter(Mandatory = $true)][string]$Source)

    return @(
        [regex]::Matches($Source, '(?m)^export\s+const\s+([a-z_]+)\s*=\s*tool\s*\(') |
            ForEach-Object { 'workflow_' + $_.Groups[1].Value } |
            Sort-Object -Unique
    )
}

function Get-StaticMarkdownDefinitionNames {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $RootPath -Recurse -File -Filter '*.md' |
            ForEach-Object {
                ([IO.Path]::GetRelativePath($RootPath, $_.FullName) -replace '\.md$', '').Replace('\', '/')
            } |
            Sort-Object -Unique
    )
}

function Invoke-SmokeSelfTest {
    $script:selfTestPassed = 0

    $nestedDefinitions = [ordered]@{
        data = @(
            [pscustomobject]@{ name = 'orchestrator'; description = 'primary' },
            [pscustomobject]@{ id = 'workflow_state' },
            [ordered]@{ 'ticket' = [pscustomobject]@{ name = 'ticket' } }
        )
    }
    $names = @(Get-DefinitionNames -Definitions $nestedDefinitions)
    Assert-SmokeSelfTest -Condition ($names -contains 'orchestrator' -and $names -contains 'workflow_state' -and $names -contains 'ticket') -Message 'Definition-name extraction handles nested dictionaries, name fields, and id fields.'

    $redacted = Hide-OpenCodeServerPassword -Value "server password secret-value`nother output"
    Assert-SmokeSelfTest -Condition ($redacted -match 'server password <redacted>' -and $redacted -notmatch 'secret-value') -Message 'Server password redaction removes sensitive values from diagnostics.'

    Assert-SmokeSelfTest -Condition ((Format-DiscoveredNames -Names @()) -eq '<none>') -Message 'Empty discovery lists render explicitly.'
    Assert-SmokeSelfTest -Condition ((Format-DiscoveredNames -Names @('b', '', 'a')) -eq 'b, a') -Message 'Discovery formatting removes empty values without inventing names.'
    $cmdInvocation = Get-WindowsCommandInvocation -CommandSource 'C:\Users\Test User\opencode2.cmd' -CommandArguments @('serve', '--port', '1234')
    Assert-SmokeSelfTest -Condition ($cmdInvocation -eq '""C:\Users\Test User\opencode2.cmd" serve --port 1234"') -Message 'CMD invocation preserves a shim path containing spaces after /s quote processing.'
    $sourceNames = @(Get-WorkflowToolNamesFromSource -Source "export const state = tool({})`nexport const next = tool({})")
    Assert-SmokeSelfTest -Condition ($sourceNames.Count -eq 2 -and $sourceNames -contains 'workflow_state' -and $sourceNames -contains 'workflow_next') -Message 'Static typed-tool fallback extracts only exported workflow tools.'

    Write-Host "OpenCode smoke helper self-test passed: $script:selfTestPassed assertions."
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
            $text = ([string]$definition).Trim()
            if (($text.StartsWith('{') -and $text.EndsWith('}')) -or ($text.StartsWith('[') -and $text.EndsWith(']'))) {
                try {
                    foreach ($nestedName in @(Get-DefinitionNames -Definitions ($text | ConvertFrom-Json))) { $names.Add($nestedName) }
                    continue
                }
                catch {
                    # Treat a non-JSON string as a literal discovered identifier.
                }
            }
            $names.Add($text)
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
        if (@($properties | Where-Object { $_.Name -eq 'name' }).Count -gt 0) { $names.Add([string]$definition.name) }
        if (@($properties | Where-Object { $_.Name -eq 'id' }).Count -gt 0) { $names.Add([string]$definition.id) }

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
    $healthDetails = if (@($HealthErrors).Count -gt 0) { " Health checks: $($HealthErrors -join '; ')" } else { '' }
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
            $response = Invoke-RestMethod -Uri $uri -Headers (Get-OpenCodeRequestHeaders) -TimeoutSec 10
            if ($response -is [string] -and ([string]$response).TrimStart().StartsWith('<!doctype html', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Endpoint returned the web application instead of API data.'
            }
            return $response
        }
        catch {
            $errors += Hide-OpenCodeServerPassword -Value "${path}: $($_.Exception.Message)"
        }
    }

    throw "Unable to load OpenCode $Description. Tried: $($errors -join '; ')"
}

function Format-DiscoveredNames {
    param([AllowNull()][object]$Names)

    $nameList = @(@($Names) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($nameList.Count -eq 0) { return '<none>' }
    return ($nameList | Select-Object -First 30) -join ', '
}

function Format-DiscoveryShape {
    param([AllowNull()][object]$Payload)

    if ($null -eq $Payload) { return 'null' }
    if ($Payload -is [string]) { return "string(length=$(([string]$Payload).Length))" }
    if ($Payload -is [System.Collections.IDictionary]) {
        return "dictionary(keys=$(@($Payload.Keys) -join ','))"
    }
    $properties = @($Payload.PSObject.Properties.Name)
    $dataProperty = $Payload.PSObject.Properties | Where-Object Name -eq 'data' | Select-Object -First 1
    $dataShape = if ($null -eq $dataProperty -or $null -eq $dataProperty.Value) { 'none' } else { "type=$($dataProperty.Value.GetType().Name),count=$(@($dataProperty.Value).Count)" }
    return "type=$($Payload.GetType().Name);properties=$($properties -join ',');data=$dataShape"
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
            $argumentList = @('/d', '/s', '/c', (Get-WindowsCommandInvocation -CommandSource $CommandSource -CommandArguments $serverArguments))
        }
        '.bat' {
            $filePath = (Get-Command cmd.exe -ErrorAction Stop).Source
            $argumentList = @('/d', '/s', '/c', (Get-WindowsCommandInvocation -CommandSource $CommandSource -CommandArguments $serverArguments))
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
            & $taskkillCommand.Source /PID $ServerProcess.Id /T /F 2>&1 | Out-Null
            $ServerProcess.WaitForExit(5000) | Out-Null
            $ServerProcess.Refresh()
            if ($ServerProcess.HasExited) { return }
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
    if ($SelfTest) {
        Invoke-SmokeSelfTest
        return
    }

    $opencodeCommandSource = Resolve-OpenCodeCommandSource -AllowLegacyFallback:$AllowLegacyOpenCodeFallback.IsPresent

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
    $healthPaths = @('/global/health', '/api/health')
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
                if (@($healthErrors).Count -gt 8) { $healthErrors = @($healthErrors | Select-Object -Last 8) }
            }
        }
        if ($healthy) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) {
        throw "OpenCode server did not become healthy. $(Get-OpenCodeServerFailureDetails -ServerProcess $process -HealthErrors $healthErrors)"
    }

    $expectedAgents = @('orchestrator', 'developer', 'reviewer', 'tester', 'delivery', 'diagnostician', 'quick-fix', 'quick-reviewer', 'bootstrap-enricher', 'evidence-reader')
    $expectedCommands = @('ai-bootstrap', 'ai-bootstrap-apply', 'ai-bootstrap-enhance', 'ai-refresh', 'branch', 'commit', 'delivery-check', 'diagnose', 'explain', 'implement', 'pr', 'pr-create', 'publish', 'quick-fix', 'review', 'run-status', 'small-task', 'test', 'ticket', 'workflow-doctor')
    $expectedTools = @('workflow_state', 'workflow_next', 'workflow_standard_review', 'workflow_quick_review', 'workflow_gate', 'workflow_dotnet_solution_add', 'workflow_fast_path', 'workflow_validate_project', 'workflow_profile_project', 'workflow_bootstrap_prepare', 'workflow_bootstrap_apply', 'workflow_validate_diagnosis', 'workflow_delivery_check')

    $agents = Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/agent', '/api/agent') -Description 'agents' -Directory $consumerRoot
    $commands = Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/command', '/api/command') -Description 'commands' -Directory $consumerRoot
    $toolDiscovery = 'runtime endpoint'
    try {
        $toolIds = @(Invoke-OpenCodeEndpoint -BaseUrl $baseUrl -Paths @('/experimental/tool/ids', '/api/experimental/tool/ids') -Description 'typed tool IDs' -Directory $consumerRoot)
        $toolNames = Get-DefinitionNames -Definitions $toolIds
        if (@($expectedTools | Where-Object { $toolNames -notcontains $_ }).Count -gt 0) {
            $toolSourcePath = Join-Path $consumerRoot '.opencode\tools\workflow.ts'
            $toolNames = @(Get-WorkflowToolNamesFromSource -Source (Get-Content -LiteralPath $toolSourcePath -Raw))
            $toolDiscovery = 'static export fallback because this OpenCode V2 beta returned an incomplete typed-tool payload'
        }
    }
    catch {
        $toolSourcePath = Join-Path $consumerRoot '.opencode\tools\workflow.ts'
        $toolNames = @(Get-WorkflowToolNamesFromSource -Source (Get-Content -LiteralPath $toolSourcePath -Raw))
        $toolDiscovery = 'static export fallback because this OpenCode V2 beta exposes no typed-tool discovery endpoint'
    }
    $agentNames = Get-DefinitionNames -Definitions $agents
    $commandNames = Get-DefinitionNames -Definitions $commands

    $agentDiscovery = 'runtime endpoint'
    $commandDiscovery = 'runtime endpoint'
    if (@($expectedAgents | Where-Object { $agentNames -notcontains $_ }).Count -gt 0) {
        $agentNames = @(Get-StaticMarkdownDefinitionNames -RootPath (Join-Path $consumerRoot '.opencode\agents'))
        $agentDiscovery = 'static definition fallback because this OpenCode V2 beta returned an incomplete agent payload'
    }
    if (@($expectedCommands | Where-Object { $commandNames -notcontains $_ }).Count -gt 0) {
        $commandNames = @(Get-StaticMarkdownDefinitionNames -RootPath (Join-Path $consumerRoot '.opencode\commands'))
        $commandDiscovery = 'static definition fallback because this OpenCode V2 beta returned an incomplete command payload'
    }
    $fallbackDiscoveries = @($agentDiscovery, $commandDiscovery, $toolDiscovery) | Where-Object { $_ -ne 'runtime endpoint' }
    if ($RequireRuntimeDiscovery -and @($fallbackDiscoveries).Count -gt 0) {
        throw "OpenCode runtime discovery is required, but at least one definition class needed a static fallback. Agents: $agentDiscovery. Commands: $commandDiscovery. Tools: $toolDiscovery."
    }
    $missingAgents = @($expectedAgents | Where-Object { $agentNames -notcontains $_ })
    $missingCommands = @($expectedCommands | Where-Object { $commandNames -notcontains $_ })
    $missingTools = @($expectedTools | Where-Object { $toolNames -notcontains $_ })
    if (@($missingAgents).Count -gt 0) { throw "OpenCode did not discover workflow agents: $($missingAgents -join ', '). Discovered: $(Format-DiscoveredNames -Names $agentNames). Shape: $(Format-DiscoveryShape -Payload $agents)." }
    if (@($missingCommands).Count -gt 0) { throw "OpenCode did not discover workflow commands: $($missingCommands -join ', '). Discovered: $(Format-DiscoveredNames -Names $commandNames). Shape: $(Format-DiscoveryShape -Payload $commands)." }
    if (@($missingTools).Count -gt 0) { throw "OpenCode did not load typed workflow tools: $($missingTools -join ', '). Discovered: $(Format-DiscoveredNames -Names $toolNames)." }

    Write-Host "OpenCode smoke test passed: $($expectedAgents.Count) agents verified via $agentDiscovery; $($expectedCommands.Count) commands verified via $commandDiscovery; $($expectedTools.Count) typed tools verified via $toolDiscovery."
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
