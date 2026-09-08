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
    'template\.ai\scripts\prepare-bootstrap-proposal.ps1',
    'template\.ai\scripts\apply-bootstrap-proposal.ps1',
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
    'template\.opencode\agents\bootstrap-enricher.md',
    'template\.opencode\agents\evidence-reader.md',
    'template\.opencode\tools\workflow.ts',
    'template\.opencode\commands\ai-bootstrap.md',
    'template\.opencode\commands\ai-bootstrap-apply.md',
    'template\.opencode\commands\ai-bootstrap-enhance.md',
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
    'template\.opencode\skills\architecture-simple-layered\SKILL.md',
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
$bootstrapEnricherAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\bootstrap-enricher.md') -Raw
$evidenceReaderAgentContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\agents\evidence-reader.md') -Raw
$rootAgentsContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\AGENTS.md') -Raw
$bootstrapCommandContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\commands\ai-bootstrap.md') -Raw
$projectContextSkillContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\skills\project-context\SKILL.md') -Raw
$repoBootstrapSkillContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\skills\repo-bootstrap\SKILL.md') -Raw
$projectProfilerSkillContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\skills\project-profiler\SKILL.md') -Raw
$projectSkillBuilderContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\skills\project-skill-builder\SKILL.md') -Raw
$cleanArchitectureSkillContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\skills\architecture-clean\SKILL.md') -Raw
$simpleLayeredSkillContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'template\.opencode\skills\architecture-simple-layered\SKILL.md') -Raw
if ($quickFixAgentContent -notmatch '(?m)^steps:\s*16\s*$') {
    $errors += 'quick-fix agent must keep its bounded 16-step budget.'
}
if ($quickReviewerAgentContent -notmatch '(?m)^steps:\s*8\s*$') {
    $errors += 'quick-reviewer agent must keep its bounded 8-step budget.'
}
if ($bootstrapEnricherAgentContent -notmatch '(?m)^steps:\s*8\s*$' -or
    $evidenceReaderAgentContent -notmatch '(?m)^steps:\s*8\s*$') {
    $errors += 'Bootstrap enrichment and evidence reading must keep bounded 8-step budgets.'
}
foreach ($boundedReadOnlyAgent in @{
    'bootstrap-enricher' = $bootstrapEnricherAgentContent
    'evidence-reader' = $evidenceReaderAgentContent
}.GetEnumerator()) {
    if ($boundedReadOnlyAgent.Value -notmatch '(?ms)- action:\s*shell\s+resource:\s*"\*"\s+effect:\s*deny' -or
        $boundedReadOnlyAgent.Value -notmatch '(?ms)- action:\s*subagent\s+resource:\s*"\*"\s+effect:\s*deny') {
        $errors += "$($boundedReadOnlyAgent.Key) must deny shell and subagent access."
    }
}
foreach ($enricherDeniedCapability in @('shell', 'grep', 'glob', 'list', 'webfetch', 'subagent')) {
    if ($bootstrapEnricherAgentContent -notmatch ('(?ms)- action:\s*' + [regex]::Escape($enricherDeniedCapability) + '\s+resource:\s*"\*"\s+effect:\s*deny')) {
        $errors += "bootstrap-enricher must deny $enricherDeniedCapability."
    }
}
foreach ($evidenceReaderToken in @('steps: 8', 'six production files and four test files', 'never read the same file twice', 'must not send the same unchanged question again')) {
    if ($evidenceReaderAgentContent -notmatch [regex]::Escape($evidenceReaderToken)) {
        $errors += "evidence-reader is missing bounded exploration contract: $evidenceReaderToken."
    }
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
foreach ($toolExport in @('state', 'next', 'standard_review', 'quick_review', 'gate', 'fast_path', 'validate_project', 'profile_project', 'bootstrap_prepare', 'bootstrap_apply', 'validate_diagnosis', 'delivery_check')) {
    if ($typedToolContent -notmatch [regex]::Escape("export const $toolExport = tool")) {
        $errors += "Typed workflow tool is missing export: $toolExport."
    }
}
if ($typedToolContent -notmatch [regex]::Escape('Bun.spawn(["pwsh", "-NoProfile", "-File", scriptPath, ...args]') -or
    $typedToolContent -match '(?m)Bun\.spawn\(`') {
    $errors += 'Typed workflow tools must invoke PowerShell with an argument vector, never an interpolated shell string.'
}
foreach ($compactToolToken in @('limit = 4_000', 'function nextActions', 'function compactState', 'function compactGate', 'do not rerun unchanged gates')) {
    if ($typedToolContent -notmatch [regex]::Escape($compactToolToken)) {
        $errors += "Typed workflow tools are missing compact execution contract: $compactToolToken."
    }
}
foreach ($agentToolRequirement in @{
    'orchestrator workflow_state' = @($orchestratorAgentContent, 'workflow_state')
    'orchestrator workflow_next' = @($orchestratorAgentContent, 'workflow_next')
    'orchestrator workflow_gate' = @($orchestratorAgentContent, 'workflow_gate')
    'orchestrator workflow_bootstrap_prepare' = @($orchestratorAgentContent, 'workflow_bootstrap_prepare')
    'orchestrator workflow_bootstrap_apply' = @($orchestratorAgentContent, 'workflow_bootstrap_apply')
    'developer workflow_gate' = @($developerAgentContent, 'workflow_gate')
    'quick-fix workflow_fast_path' = @($quickFixAgentContent, 'workflow_fast_path')
    'quick-fix workflow_state' = @($quickFixAgentContent, 'workflow_state')
    'quick-fix workflow_next' = @($quickFixAgentContent, 'workflow_next')
    'delivery workflow_next' = @($deliveryAgentContent, 'workflow_next')
    'bootstrap-enricher workflow_bootstrap_apply' = @($bootstrapEnricherAgentContent, 'workflow_bootstrap_apply')
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
foreach ($requiredRunnerToken in @('quality-gates.schema.json', 'startedWorktreeFingerprint', 'runnerSha256', 'configuredCommandCount', 'qualityPlanSha256', 'workflow-run.schema.json', 'RunId', '[switch]$Force', 'Invalid or stale runtime evidence is replaced')) {
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
foreach ($smokeToken in @('opencode2', 'AllowLegacyOpenCodeFallback', 'SelfTest', 'OpenCode smoke helper self-test passed', 'Get-WindowsCommandInvocation', 'Get-WorkflowToolNamesFromSource', 'Get-StaticMarkdownDefinitionNames', 'static definition fallback', 'static export fallback', '/api/health', '/global/health', '/api/agent', '/api/command', '/api/experimental/tool/ids', 'directory=', 'Authorization', '<redacted>', 'workflow_state', 'workflow_next', 'workflow_standard_review', 'workflow_quick_review', 'workflow_gate', 'workflow_bootstrap_prepare', 'workflow_bootstrap_apply')) {
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
foreach ($bootstrapToken in @('workflow_bootstrap_prepare', 'prepare-bootstrap-proposal.ps1', 'BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE', 'BOOTSTRAP_PROPOSAL_CURRENT', 'BOOTSTRAP_PROPOSAL_STALE', 'Do not read source files', '.ai/bootstrap-proposal/project.json', '.ai/bootstrap-proposal/evidence-packet.json', '/ai-bootstrap-apply', '/ai-bootstrap-enhance')) {
    if ($bootstrapCommandContent -notmatch [regex]::Escape($bootstrapToken)) {
        $errors += "ai-bootstrap command is missing bootstrap robustness contract: $bootstrapToken."
    }
}
foreach ($bootstrapPrecedenceToken in @('For `/ai-bootstrap`, do not load `project-context` first', 'Bootstrap has no trusted project context yet', 'Do not manually explore the repository during bootstrap')) {
    if ($rootAgentsContent -notmatch [regex]::Escape($bootstrapPrecedenceToken)) {
        $errors += "AGENTS.md is missing bootstrap precedence guard: $bootstrapPrecedenceToken."
    }
}
foreach ($orchestratorBootstrapToken in @('For `/ai-bootstrap`, follow the command file before any normal planning behavior', 'run `workflow_bootstrap_prepare`', 'Do not read source files, list directories, load `project-context`, ask for bootstrap input', 'The preparer owns profiling, conservative inference', 'For `/ai-bootstrap-apply`, do not regenerate or reinterpret the proposal')) {
    if ($orchestratorAgentContent -notmatch [regex]::Escape($orchestratorBootstrapToken)) {
        $errors += "orchestrator is missing bootstrap precedence guard: $orchestratorBootstrapToken."
    }
}
foreach ($smallModelContract in @('workflow_next', 'Do not repeat an unchanged state, profile, gate, review, or exploration call', 'evidence-reader')) {
    if ($orchestratorAgentContent -notmatch [regex]::Escape($smallModelContract)) {
        $errors += "orchestrator is missing bounded-execution guidance: $smallModelContract."
    }
}
foreach ($nextAwareCommand in @('run-status', 'implement', 'test', 'review', 'delivery-check')) {
    $nextAwareContent = Get-Content -LiteralPath (Join-Path $workflowRoot "template\.opencode\commands\$nextAwareCommand.md") -Raw
    if ($nextAwareContent -notmatch [regex]::Escape('workflow_next') -or $nextAwareContent -notmatch [regex]::Escape('once')) {
        $errors += "$nextAwareCommand must use workflow_next exactly once at its resume boundary."
    }
}
foreach ($skillScopedAgent in @{
    'orchestrator' = $orchestratorAgentContent
    'developer' = $developerAgentContent
    'reviewer' = $reviewerAgentContent
    'quick-fix' = $quickFixAgentContent
    'quick-reviewer' = $quickReviewerAgentContent
    'delivery' = $deliveryAgentContent
    'diagnostician' = $diagnosticianAgentContent
    'bootstrap-enricher' = $bootstrapEnricherAgentContent
    'evidence-reader' = $evidenceReaderAgentContent
}.GetEnumerator()) {
    if ($skillScopedAgent.Value -notmatch '(?ms)- action:\s*skill\s+resource:\s*"\*"\s+effect:\s*deny') {
        $errors += "$($skillScopedAgent.Key) must deny the global skill catalog before reopening a bounded allowlist."
    }
}
foreach ($projectContextBootstrapToken in @('If the current task is `/ai-bootstrap`, stop using this skill', 'Project context is not trusted until bootstrap is approved and persisted', 'do not inspect files, ask for bootstrap input, or create project configuration from this skill')) {
    if ($projectContextSkillContent -notmatch [regex]::Escape($projectContextBootstrapToken)) {
        $errors += "project-context skill is missing bootstrap escape hatch: $projectContextBootstrapToken."
    }
}
foreach ($bootstrapSkillToken in @('PROFILE FALLBACK USED', 'BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE', 'Do not continue with manual directory exploration', 'Do not announce that they need to be loaded without reading them', 'Loop guard: never restate the profile result', 'produce the full proposal in durable draft files', 'workflow_bootstrap_apply', 'architecture-simple-layered')) {
    if ($repoBootstrapSkillContent -notmatch [regex]::Escape($bootstrapSkillToken)) {
        $errors += "repo-bootstrap skill is missing bootstrap robustness contract: $bootstrapSkillToken."
    }
}
foreach ($profilerToken in @('PROFILE FALLBACK USED', 'BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE', '.ai/bootstrap-proposal/project-profile.json', '.ai/project-profile.json', 'architecture-simple-layered')) {
    if ($projectProfilerSkillContent -notmatch [regex]::Escape($profilerToken)) {
        $errors += "project-profiler skill is missing controlled fallback or conservative architecture guidance: $profilerToken."
    }
}
if ($projectSkillBuilderContent -notmatch [regex]::Escape('do not use `architecture-clean` as a default')) {
    $errors += 'project-skill-builder must forbid defaulting conventional layered applications to architecture-clean.'
}
if ($cleanArchitectureSkillContent -notmatch [regex]::Escape('Do not apply this skill to a conventional controller/model/repository API')) {
    $errors += 'architecture-clean skill must reject conventional layered APIs without stronger architecture evidence.'
}
if ($simpleLayeredSkillContent -notmatch [regex]::Escape('controller/model/repository') -or
    $simpleLayeredSkillContent -notmatch [regex]::Escape('do not add layers')) {
    $errors += 'architecture-simple-layered skill must describe pragmatic layered boundaries and avoid architecture inflation.'
}
$benchmarkSchemaContent = Get-Content -LiteralPath (Join-Path $workflowRoot 'evaluations\benchmark.schema.json') -Raw
foreach ($benchmarkMetric in @('toolCalls', 'duplicateToolCalls', 'subagentDelegations', 'protocolViolations', 'stepLimitReached')) {
    if ($benchmarkSchemaContent -notmatch [regex]::Escape('"' + $benchmarkMetric + '"')) {
        $errors += "Benchmark schema is missing small-model loop metric: $benchmarkMetric."
    }
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
