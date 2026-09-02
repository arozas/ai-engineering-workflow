[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Workflow.Common.ps1')

$workflowRoot = Get-WorkflowRoot
$manifest = Get-WorkflowManifest
$version = Get-WorkflowVersion
$errors = @()

if ($manifest.version -ne $version) {
    $errors += "VERSION ($version) does not match workflow.manifest.json ($($manifest.version))."
}

foreach ($forbidden in @('AGENTS.md', 'opencode.json', '.ai', '.opencode')) {
    if (Test-Path -LiteralPath (Join-Path $workflowRoot $forbidden)) {
        $errors += "Distribution root must not contain active project configuration: $forbidden"
    }
}

foreach ($required in @(
    'scripts\Workflow.Common.ps1',
    'scripts\install.ps1',
    'scripts\new-project.ps1',
    'scripts\smoke-opencode.ps1',
    'scripts\update.ps1',
    'scripts\summarize-evaluations.ps1',
    'tests\Run-Tests.ps1',
    'docs\README.md',
    'docs\architecture.md',
    'docs\installation.md',
    'docs\workflows.md',
    'docs\project-context.md',
    'docs\security.md',
    'docs\models-and-efficiency.md',
    'docs\extending-and-validation.md',
    'docs\troubleshooting.md',
    '.github\workflows\validate.yml',
    'evaluations\benchmark.schema.json',
    'evaluations\README.md',
    'evaluations\benchmark-suite-playbook.md',
    'template\AGENTS.md',
    'template\opencode.json',
    'template\.ai\project.schema.json',
    'template\.ai\project-profile.schema.json',
    'template\.ai\generated-skills.schema.json',
    'template\.ai\bootstrap-input.schema.json',
    'template\.ai\workflow-installation.schema.json',
    'template\.ai\workflow-run.schema.json',
    'template\.ai\quality-gates.schema.json',
    'template\.ai\review-evidence.schema.json',
    'template\.ai\branch-evidence.schema.json',
    'template\.ai\commit-evidence.schema.json',
    'template\.ai\publish-evidence.schema.json',
    'template\.ai\pull-request-evidence.schema.json',
    'template\.ai\diagnosis.schema.json',
    'template\.ai\pull-request-template.md',
    'template\.ai\scripts\fast-path-check.ps1',
    'template\.ai\scripts\profile-project.ps1',
    'template\.ai\scripts\validate-project.ps1',
    'template\.ai\scripts\workflow-state.ps1',
    'template\.ai\scripts\run-quality-gates.ps1',
    'template\.ai\scripts\record-review.ps1',
    'template\.ai\scripts\validate-diagnosis.ps1',
    'template\.ai\scripts\validate-commit-message.ps1',
    'template\.ai\scripts\create-branch.ps1',
    'template\.ai\scripts\commit-approved.ps1',
    'template\.ai\scripts\publish-approved.ps1',
    'template\.ai\scripts\create-draft-pr.ps1',
    'template\.opencode\agents\orchestrator.md',
    'template\.opencode\agents\quick-fix.md',
    'template\.opencode\agents\quick-reviewer.md',
    'template\.opencode\agents\delivery.md',
    'template\.opencode\agents\diagnostician.md',
    'template\.opencode\tools\workflow.ts',
    'template\.opencode\commands\ai-bootstrap.md',
    'template\.opencode\commands\quick-fix.md',
    'template\.opencode\commands\small-task.md',
    'template\.opencode\commands\ai-refresh.md',
    'template\.opencode\commands\run-status.md',
    'template\.opencode\commands\diagnose.md',
    'template\.opencode\commands\commit.md',
    'template\.opencode\commands\pr-create.md',
    'template\.opencode\skills\repo-bootstrap\SKILL.md',
    'template\.opencode\skills\fast-path\SKILL.md',
    'template\.opencode\skills\workflow-state\SKILL.md',
    'template\.opencode\skills\production-diagnosis\SKILL.md',
    'template\.opencode\skills\project-profiler\SKILL.md',
    'template\.opencode\skills\project-skill-builder\SKILL.md',
    '.github\pull_request_template.md'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $workflowRoot $required) -PathType Leaf)) {
        $errors += "Missing required file: $required"
    }
}

$projectSchemaPath = Join-Path $workflowRoot 'template\.ai\project.schema.json'
if (Test-Path -LiteralPath $projectSchemaPath -PathType Leaf) {
    $projectSchemaJson = Get-Content -LiteralPath $projectSchemaPath -Raw
    $projectSchema = $projectSchemaJson | ConvertFrom-Json
    $fastPathSchema = $projectSchema.properties.fastPath
    if ($null -eq $fastPathSchema) {
        $errors += 'Project schema must define the optional fastPath policy.'
    }
    elseif ($fastPathSchema.properties.maximumFiles.maximum -ne 3 -or
        $fastPathSchema.properties.maximumLines.maximum -ne 120 -or
        $fastPathSchema.properties.maximumCorrectionIterations.const -ne 1) {
        $errors += 'Fast-path schema limits must remain bounded to 3 files, 120 lines, and one correction.'
    }
    $diagnosticsSchema = $projectSchema.properties.diagnostics
    if ($null -eq $diagnosticsSchema -or $diagnosticsSchema.properties.maxHypothesisIterations.maximum -ne 3) {
        $errors += 'Project schema must bound production diagnosis to at most three hypothesis iterations.'
    }
    $projectExamplePath = Join-Path $workflowRoot 'template\.ai\project.example.json'
    if (Test-Path -LiteralPath $projectExamplePath -PathType Leaf) {
        try {
            if (-not ((Get-Content -LiteralPath $projectExamplePath -Raw) | Test-Json -Schema $projectSchemaJson -ErrorAction Stop)) {
                $errors += 'project.example.json does not validate against project.schema.json.'
            }
        }
        catch { $errors += "Project example schema validation failed: $($_.Exception.Message)" }
    }
}

try {
    $manifestSchemaJson = Get-Content -LiteralPath (Join-Path $workflowRoot 'workflow.manifest.schema.json') -Raw
    $manifestJson = Get-Content -LiteralPath (Join-Path $workflowRoot 'workflow.manifest.json') -Raw
    if (-not ($manifestJson | Test-Json -Schema $manifestSchemaJson -ErrorAction Stop)) {
        $errors += 'workflow.manifest.json does not validate against workflow.manifest.schema.json.'
    }
}
catch { $errors += "Workflow manifest schema validation failed: $($_.Exception.Message)" }

$openCodeConfigContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\opencode.json') -Raw
if ($openCodeConfigContent -notmatch [regex]::Escape('"action": "workflow_*", "resource": "*", "effect": "deny"')) {
    $errors += 'opencode.json must deny custom workflow tools by default.'
}
foreach ($managedScript in @('delivery-check.ps1', 'fast-path-check.ps1', 'validate-project.ps1', 'workflow-state.ps1', 'profile-project.ps1', 'validate-diagnosis.ps1', 'run-quality-gates.ps1', 'record-review.ps1')) {
    $unsafePattern = '(?m)"action":\s*"shell"[^\r\n]*' + [regex]::Escape($managedScript) + '[^\r\n]*"effect":\s*"allow"'
    if ($openCodeConfigContent -match $unsafePattern) {
        $errors += "opencode.json must not automatically allow managed script $managedScript through a raw shell pattern."
    }
}
foreach ($sensitivePattern in @('*.npmrc', '*.pypirc', '*.pem', '*.key', '*credentials*.json', '*secrets*.json')) {
    $escaped = [regex]::Escape('"resource": "' + $sensitivePattern + '", "effect": "deny"')
    if ($openCodeConfigContent -notmatch $escaped) { $errors += "opencode.json must deny sensitive path pattern $sensitivePattern." }
}

$quickFixAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\quick-fix.md') -Raw
$developerAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\developer.md') -Raw
$quickReviewerAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\quick-reviewer.md') -Raw
$reviewerAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\reviewer.md') -Raw
$orchestratorAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\orchestrator.md') -Raw
$deliveryAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\delivery.md') -Raw
if ($quickFixAgentContent -notmatch '(?m)^steps:\s*16\s*$') {
    $errors += 'quick-fix agent must keep its bounded 16-step budget.'
}
if ($quickReviewerAgentContent -notmatch '(?m)^steps:\s*8\s*$') {
    $errors += 'quick-reviewer agent must keep its bounded 8-step budget.'
}
foreach ($agentDefinition in @{
    'developer' = $developerAgentContent
    'quick-fix' = $quickFixAgentContent
}.GetEnumerator()) {
    foreach ($protectedPath in @('.ai/*', '.opencode/*', '*AGENTS.md', '*opencode.json')) {
        $pattern = '(?ms)- action:\s*edit\s+resource:\s*"' + [regex]::Escape($protectedPath) + '"\s+effect:\s*deny'
        if ($agentDefinition.Value -notmatch $pattern) {
            $errors += "$($agentDefinition.Key) must deny direct edits to control-plane path $protectedPath."
        }
    }
}
if ($quickFixAgentContent -notmatch '(?ms)- action:\s*edit\s+resource:\s*"\.ai/runtime/\*/gates\.json"\s+effect:\s*deny') {
    $errors += 'quick-fix must not write deterministic gate evidence directly.'
}
if ($orchestratorAgentContent -notmatch '(?ms)- action:\s*edit\s+resource:\s*"\.ai/runtime/\*/gates\.json"\s+effect:\s*deny') {
    $errors += 'orchestrator must not write deterministic gate evidence directly.'
}
foreach ($agentDefinition in @{
    'orchestrator' = $orchestratorAgentContent
    'quick-fix' = $quickFixAgentContent
}.GetEnumerator()) {
    if ($agentDefinition.Value -notmatch '(?ms)- action:\s*edit\s+resource:\s*"\.ai/runtime/\*/review\.json"\s+effect:\s*deny') {
        $errors += "$($agentDefinition.Key) must not write independent review evidence directly."
    }
}
foreach ($deliveryArtifact in @('publish.json', 'pull-request.json')) {
    $pattern = '(?ms)- action:\s*edit\s+resource:\s*"\.ai/runtime/\*/' + [regex]::Escape($deliveryArtifact) + '"\s+effect:\s*allow'
    if ($deliveryAgentContent -notmatch $pattern) {
        $errors += "delivery must be able to stage its validated run-specific evidence file: $deliveryArtifact."
    }
}
$deliveryCommitEditPattern = '(?ms)- action:\s*edit\s+resource:\s*"\.ai/runtime/\*/commit\.json"\s+effect:\s*allow'
if ($deliveryAgentContent -match $deliveryCommitEditPattern) {
    $errors += 'delivery must not author commit evidence directly; commit-approved.ps1 owns it.'
}
$typedToolContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\tools\workflow.ts') -Raw
foreach ($toolExport in @('state', 'standard_review', 'quick_review', 'gate', 'fast_path', 'validate_project', 'profile_project', 'validate_diagnosis', 'delivery_check')) {
    if ($typedToolContent -notmatch [regex]::Escape("export const $toolExport = tool")) {
        $errors += "Typed workflow tool is missing export: $toolExport."
    }
}
if ($typedToolContent -notmatch [regex]::Escape('Bun.spawn(["pwsh", "-NoProfile", "-File", scriptPath, ...args]') -or
    $typedToolContent -match '(?m)Bun\.spawn\(`') {
    $errors += 'Typed workflow tools must invoke PowerShell with an argument vector, never an interpolated shell string.'
}
foreach ($agentToolRequirement in @{
    'orchestrator workflow_state' = @($orchestratorAgentContent, 'workflow_state')
    'orchestrator workflow_gate' = @($orchestratorAgentContent, 'workflow_gate')
    'developer workflow_gate' = @($developerAgentContent, 'workflow_gate')
    'quick-fix workflow_fast_path' = @($quickFixAgentContent, 'workflow_fast_path')
    'quick-fix workflow_state' = @($quickFixAgentContent, 'workflow_state')
    'reviewer workflow_standard_review' = @($reviewerAgentContent, 'workflow_standard_review')
    'quick-reviewer workflow_quick_review' = @($quickReviewerAgentContent, 'workflow_quick_review')
}.GetEnumerator()) {
    $content = $agentToolRequirement.Value[0]
    $action = $agentToolRequirement.Value[1]
    if ($content -notmatch ('(?ms)- action:\s*' + [regex]::Escape($action) + '\s+resource:\s*"\*"\s+effect:\s*allow')) {
        $errors += "$($agentToolRequirement.Key) must be explicitly allowed."
    }
}
if ($reviewerAgentContent -match '(?ms)- action:\s*(workflow_state|workflow_quick_review)\s+resource:\s*"\*"\s+effect:\s*allow') {
    $errors += 'reviewer must receive only the standard review transition capability.'
}
if ($quickReviewerAgentContent -match '(?ms)- action:\s*(workflow_state|workflow_standard_review)\s+resource:\s*"\*"\s+effect:\s*allow') {
    $errors += 'quick-reviewer must receive only the fast-path review transition capability.'
}
$qualityRunnerContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.ai\scripts\run-quality-gates.ps1') -Raw
$workflowStateContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.ai\scripts\workflow-state.ps1') -Raw
foreach ($requiredRunnerToken in @('quality-gates.schema.json', 'startedWorktreeFingerprint', 'runnerSha256', 'configuredCommandCount', 'qualityPlanSha256', 'workflow-run.schema.json', 'RunId')) {
    if ($qualityRunnerContent -notmatch [regex]::Escape($requiredRunnerToken)) {
        $errors += "Quality-gate runner is missing deterministic evidence field or check: $requiredRunnerToken."
    }
}
if ($qualityRunnerContent -notmatch [regex]::Escape('.ai\runtime\$RunId\gates.json')) {
    $errors += 'Quality-gate evidence must be isolated under the current run ID.'
}
$runnerPreamble = $qualityRunnerContent.Substring(0, $qualityRunnerContent.IndexOf('function '))
if ($runnerPreamble -match '\$ModuleId') {
    $errors += 'Quality-gate runner must derive modules from persisted run state, not caller-selected ModuleId input.'
}
foreach ($requiredStateToken in @('Resolve-RunRuntimeArtifact', 'Get-ValidatedGateEvidence', 'Get-ValidatedReviewEvidence', 'Get-ValidatedBranchEvidence', 'Get-ValidatedCommitEvidence', 'Get-ValidatedPublishEvidence', 'Get-ValidatedPullRequestEvidence', 'ls-remote', 'ghCommand.Source pr view', 'Get-ControlPlaneFingerprint', 'Assert-ControlPlane', 'affectedModuleIds', 'matrixSha256', 'Quality-gate command mismatch', 'validate-commit-message.ps1')) {
    if ($workflowStateContent -notmatch [regex]::Escape($requiredStateToken)) {
        $errors += "Workflow state is missing deterministic protection: $requiredStateToken."
    }
}
if ($typedToolContent -match '(?s)export const state = tool\(\{.*?action:\s*tool\.schema\.enum\(\[[^\]]*"RecordReview"') {
    $errors += 'Generic workflow_state must not expose RecordReview; only reviewer-scoped tools may persist review verdicts.'
}
$reviewRecorderContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.ai\scripts\record-review.ps1') -Raw
foreach ($reviewToken in @('review-evidence.schema.json', 'gateEvidenceSha256', 'severityCounts', 'acceptanceCriteriaCoverage', '-Action RecordReview', 'quick-reviewer')) {
    if ($reviewRecorderContent -notmatch [regex]::Escape($reviewToken)) {
        $errors += "Review recorder is missing a required identity or derived-verdict contract: $reviewToken."
    }
}
$branchScriptContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.ai\scripts\create-branch.ps1') -Raw
$commitScriptContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.ai\scripts\commit-approved.ps1') -Raw
foreach ($scriptContract in @{
    'create-branch RunId' = @($branchScriptContent, '[string]$RunId')
    'create-branch evidence' = @($branchScriptContent, '-Action RecordBranch')
    'commit-approved RunId' = @($commitScriptContent, '[string]$RunId')
    'commit-approved evidence' = @($commitScriptContent, '-Action RecordCommit')
}.GetEnumerator()) {
    if ($scriptContract.Value[0] -notmatch [regex]::Escape($scriptContract.Value[1])) {
        $errors += "$($scriptContract.Key) contract is missing."
    }
}

foreach ($onboardingScript in @('scripts\install.ps1', 'scripts\new-project.ps1')) {
    $onboardingContent = Get-Content -LiteralPath (Join-Path $workflowRoot $onboardingScript) -Raw
    if ($onboardingContent -notmatch '(?m)^\s*Write-Host\s+''\s+opencode2''\s*$') {
        $errors += "$onboardingScript must invoke the OpenCode V2 executable name: opencode2."
    }
    if ($onboardingContent -match '(?m)^\s*Write-Host\s+''\s+opencode''\s*$') {
        $errors += "$onboardingScript must not point users to the V1 opencode executable."
    }
}
$openCodeSmokeContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'scripts\smoke-opencode.ps1') -Raw
foreach ($smokeToken in @('opencode2', 'AllowLegacyOpenCodeFallback', 'SelfTest', 'OpenCode smoke helper self-test passed', '/api/health', '/global/health', '/api/agent', '/api/command', '/api/experimental/tool/ids', 'directory=', 'Authorization', '<redacted>', 'workflow_state', 'workflow_standard_review', 'workflow_quick_review', 'workflow_gate')) {
    if ($openCodeSmokeContent -notmatch [regex]::Escape($smokeToken)) {
        $errors += "OpenCode smoke test is missing discovery check: $smokeToken."
    }
}
if ($openCodeSmokeContent -match [regex]::Escape("foreach (`$commandName in @('opencode2', 'opencode'))")) {
    $errors += 'OpenCode smoke test must not fall back to the V1 opencode executable by default.'
}
$ciContent = Get-Content -LiteralPath (Join-Path $workflowRoot '.github\workflows\validate.yml') -Raw
foreach ($ciToken in @('Validate distribution contracts', 'Run isolated workflow tests')) {
    if ($ciContent -notmatch [regex]::Escape($ciToken)) {
        $errors += "CI is missing deterministic validation contract: $ciToken."
    }
}
foreach ($ciToken in @('opencode-v2-smoke:', 'npm install --global', 'opencode2 --version', 'smoke-opencode.ps1')) {
    if ($ciContent -match [regex]::Escape($ciToken)) {
        $errors += "Required CI must not depend on OpenCode V2 beta smoke testing: $ciToken."
    }
}

$readmePath = Join-Path $workflowRoot 'README.md'
if ((Get-Content -LiteralPath $readmePath).Count -gt 350) {
    $errors += 'README.md must remain a concise entry point; detailed guidance belongs under docs/.'
}
$diagnosticianAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\diagnostician.md') -Raw
foreach ($reviewDefinition in @{
    'reviewer' = $reviewerAgentContent
    'quick-reviewer' = $quickReviewerAgentContent
    'diagnostician' = $diagnosticianAgentContent
}.GetEnumerator()) {
    if ($reviewDefinition.Value -notmatch '(?ms)- action:\s*shell\s+resource:\s*"\*"\s+effect:\s*deny') {
        $errors += "$($reviewDefinition.Key) must deny all shell commands."
    }
    if ($reviewDefinition.Value -match '(?ms)- action:\s*shell\s+resource:\s*"(?!\*)[^"]+"\s+effect:\s*(allow|ask)') {
        $errors += "$($reviewDefinition.Key) must not reopen shell permissions after the deny rule."
    }
}
if ($diagnosticianAgentContent -notmatch '(?ms)- action:\s*edit\s+resource:\s*"\*"\s+effect:\s*deny' -or
    $diagnosticianAgentContent -notmatch '(?ms)- action:\s*subagent\s+resource:\s*"\*"\s+effect:\s*deny') {
    $errors += 'diagnostician must deny all edit and subagent access.'
}
foreach ($commandName in @('quick-fix', 'small-task')) {
    $commandContent = Get-Content -LiteralPath (Join-Path $workflowRoot "template\.opencode\commands\$commandName.md") -Raw
    if ($commandContent -notmatch '(?m)^agent:\s*quick-fix\s*$') {
        $errors += "$commandName command must run through the quick-fix agent."
    }
}
$diagnoseCommandContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\commands\diagnose.md') -Raw
if ($diagnoseCommandContent -notmatch '(?m)^agent:\s*orchestrator\s*$') {
    $errors += 'diagnose command must run through the orchestrator.'
}

$installationSchemaPath = Join-Path $workflowRoot 'template\.ai\workflow-installation.schema.json'
if (Test-Path -LiteralPath $installationSchemaPath -PathType Leaf) {
    $installationSchema = Get-Content -LiteralPath $installationSchemaPath -Raw | ConvertFrom-Json
    if ($installationSchema.properties.schemaVersion.const -ne 2) {
        $errors += 'Installation metadata schema must require schemaVersion 2.'
    }
    foreach ($propertyName in @('installationMode', 'shareProjectContext', 'localExcludedPaths')) {
        if ($installationSchema.required -notcontains $propertyName) {
            $errors += "Installation metadata schema must require '$propertyName'."
        }
    }
}

$installScriptContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'scripts\install.ps1') -Raw
if ($installScriptContent -notmatch "\[ValidateSet\('Local', 'Shared'\)\]\[string\]\`$Mode = 'Local'") {
    $errors += 'install.ps1 must default to Local and explicitly support Shared mode.'
}
if ($installScriptContent -notmatch 'Get-WorkflowExcludeBlockState' -or
    $installScriptContent -notmatch 'Test-LocalPathsAreUntracked' -or
    $installScriptContent -notmatch 'Assert-LocalPathsIgnored') {
    $errors += 'install.ps1 must enforce the repository-local Git exclusion preflight and verification.'
}

foreach ($jsonFile in Get-ChildItem -LiteralPath $workflowRoot -Recurse -File -Filter '*.json') {
    try {
        Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        $errors += "Invalid JSON: $(Get-NormalizedRelativePath -Root $workflowRoot -Path $jsonFile.FullName)"
    }
}

foreach ($scriptRoot in @('scripts', 'template\.ai\scripts')) {
    foreach ($scriptFile in Get-ChildItem -LiteralPath (Join-Path $workflowRoot $scriptRoot) -File -Filter '*.ps1') {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($parseError in @($parseErrors)) {
            $errors += "PowerShell parse error in $(Get-NormalizedRelativePath -Root $workflowRoot -Path $scriptFile.FullName): $($parseError.Message)"
        }
    }
}

$repositoryPrTemplate = Join-Path $workflowRoot '.github\pull_request_template.md'
$consumerPrTemplate = Join-Path $workflowRoot 'template\.ai\pull-request-template.md'
if ((Test-Path -LiteralPath $repositoryPrTemplate) -and (Test-Path -LiteralPath $consumerPrTemplate)) {
    if ((Get-FileSha256 -Path $repositoryPrTemplate) -ne (Get-FileSha256 -Path $consumerPrTemplate)) {
        $errors += 'Repository and consumer pull-request templates must remain identical.'
    }
}

$skillsRoot = Join-Path $workflowRoot 'template\.opencode\skills'
if (Test-Path -LiteralPath $skillsRoot) {
    foreach ($skillDirectory in Get-ChildItem -LiteralPath $skillsRoot -Directory) {
        $skillFile = Join-Path $skillDirectory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            $errors += "Missing SKILL.md: $($skillDirectory.Name)"
            continue
        }
        $nameLine = Get-Content -LiteralPath $skillFile | Where-Object { $_ -match '^name:\s+' } | Select-Object -First 1
        if ($nameLine -ne ('name: ' + $skillDirectory.Name)) {
            $errors += "Skill name mismatch: $($skillDirectory.Name)"
        }
    }
}

foreach ($definitionRoot in @('template\.opencode\agents', 'template\.opencode\commands')) {
    $fullRoot = Join-Path $workflowRoot $definitionRoot
    foreach ($definition in Get-ChildItem -LiteralPath $fullRoot -File -Filter '*.md') {
        $lines = @(Get-Content -LiteralPath $definition.FullName)
        if ($lines.Count -lt 4 -or $lines[0] -ne '---' -or @($lines | Where-Object { $_ -eq '---' }).Count -lt 2) {
            $errors += "Invalid frontmatter: $(Get-NormalizedRelativePath -Root $workflowRoot -Path $definition.FullName)"
        }
    }
}

$projectPresetsRoot = Join-Path $workflowRoot $manifest.projectPresetsPath
$stackPresetsRoot = Join-Path $workflowRoot $manifest.stackPresetsPath
$architecturePresetsRoot = Join-Path $workflowRoot $manifest.architecturePresetsPath
$stackIds = @{}
foreach ($stackFile in Get-ChildItem -LiteralPath $stackPresetsRoot -File -Filter '*.json') {
    $stack = Get-Content -LiteralPath $stackFile.FullName -Raw | ConvertFrom-Json
    if ($stack.id -ne $stackFile.BaseName) {
        $errors += "Stack preset ID mismatch: $($stackFile.Name)"
    }
    if ($stackIds.ContainsKey([string]$stack.id)) {
        $errors += "Duplicate stack preset ID: $($stack.id)"
    }
    $stackIds[[string]$stack.id] = $true
}

foreach ($architectureFile in Get-ChildItem -LiteralPath $architecturePresetsRoot -File -Filter '*.json') {
    $architecture = Get-Content -LiteralPath $architectureFile.FullName -Raw | ConvertFrom-Json
    if ($architecture.id -ne $architectureFile.BaseName) {
        $errors += "Architecture preset ID mismatch: $($architectureFile.Name)"
    }
}

foreach ($presetDirectory in Get-ChildItem -LiteralPath $projectPresetsRoot -Directory) {
    $presetFile = Join-Path $presetDirectory.FullName 'preset.json'
    if (-not (Test-Path -LiteralPath $presetFile -PathType Leaf)) {
        $errors += "Missing preset.json: $($presetDirectory.Name)"
        continue
    }
    $preset = Get-Content -LiteralPath $presetFile -Raw | ConvertFrom-Json
    if ($preset.id -ne $presetDirectory.Name) {
        $errors += "Project preset ID mismatch: $($presetDirectory.Name)"
    }
    foreach ($stackId in @($preset.stacks)) {
        if (-not $stackIds.ContainsKey([string]$stackId)) {
            $errors += "Project preset '$($preset.id)' references unknown stack '$stackId'."
        }
    }
}

$templateFiles = @(Get-TemplateFileRecords)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Distribution validation failed with $($errors.Count) error(s)."
}

Write-Host 'Distribution validation passed.'
Write-Host "Version: $version"
Write-Host "Template files: $($templateFiles.Count)"
Write-Host "Agents: $(@(Get-ChildItem -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents') -File -Filter '*.md').Count)"
Write-Host "Commands: $(@(Get-ChildItem -LiteralPath (Join-Path $workflowRoot 'template\.opencode\commands') -File -Filter '*.md').Count)"
Write-Host "Skills: $(@(Get-ChildItem -LiteralPath $skillsRoot -Directory).Count)"
Write-Host "Project presets: $(@(Get-ChildItem -LiteralPath $projectPresetsRoot -Directory).Count)"
Write-Host "Stack profiles: $(@(Get-ChildItem -LiteralPath $stackPresetsRoot -File -Filter '*.json').Count)"
Write-Host "Architecture presets: $(@(Get-ChildItem -LiteralPath $architecturePresetsRoot -File -Filter '*.json').Count)"
