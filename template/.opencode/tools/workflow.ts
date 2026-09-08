import path from "node:path"
import { mkdir, rm, writeFile } from "node:fs/promises"
import { tool } from "@opencode-ai/plugin"

type ToolContext = {
  directory: string
  worktree?: string
}

const runId = tool.schema
  .string()
  .regex(/^[a-z0-9][a-z0-9-]{2,63}$/, "Use a lowercase kebab-case workflow run ID.")

const relativePath = tool.schema
  .string()
  .min(1)
  .max(500)
  .refine((value) => !path.isAbsolute(value), "Use a repository-relative path.")

const reviewFinding = tool.schema.object({
  severity: tool.schema.enum(["BLOCKER", "HIGH", "MEDIUM", "LOW", "NIT"]),
  file: relativePath,
  line: tool.schema.number().int().min(1).nullable(),
  category: tool.schema.string().min(1).max(100),
  problem: tool.schema.string().min(1).max(1500),
  evidence: tool.schema.string().min(1).max(1500),
  impact: tool.schema.string().min(1).max(1500),
  recommendedFix: tool.schema.string().min(1).max(1500),
})

const reviewCoverage = tool.schema.object({
  criterion: tool.schema.string().min(1).max(1000),
  status: tool.schema.enum(["COVERED", "PARTIAL", "MISSING"]),
  evidence: tool.schema.string().min(1).max(1500),
})

const reviewArgs = {
  runId,
  summary: tool.schema.string().min(1).max(2000),
  findings: tool.schema.array(reviewFinding).max(20),
  acceptanceCriteriaCoverage: tool.schema.array(reviewCoverage).min(1).max(30),
  residualRisks: tool.schema.array(tool.schema.string().min(1).max(1000)).max(20),
  escalationReason: tool.schema.string().min(1).max(2000).optional(),
}

function repositoryRoot(context: ToolContext): string {
  return path.resolve(context.worktree || context.directory)
}

function addValue(args: string[], name: string, value: unknown): void {
  if (value === undefined || value === null || value === "") return
  args.push(name, String(value))
}

function addSwitch(args: string[], name: string, enabled: boolean | undefined): void {
  if (enabled) args.push(name)
}

function clip(value: string, limit = 4_000): string {
  return value.length <= limit ? value : `${value.slice(0, limit)}\n... output truncated; inspect the persisted artifact for details ...`
}

type ProcessResult = {
  exitCode: number
  stdout: string
  stderr: string
}

function nextActions(status: string, workflowPath: string): string[] {
  const actions: Record<string, string[]> = {
    PLANNING: ["ApprovePlan", "Escalate"],
    PLAN_APPROVED: ["CreateBranch (optional)", "BeginImplementation", "Escalate"],
    IMPLEMENTING: ["workflow_gate", "RecordGates", "Escalate"],
    GATES_PASSED: [workflowPath === "fast-path" ? "workflow_quick_review" : "workflow_standard_review", "Escalate"],
    GATE_FAILED: ["BeginCorrection", "Escalate"],
    REVIEW_FAILED: ["BeginCorrection", "Escalate"],
    READY_FOR_DELIVERY: ["delivery-check", "commit", "stop"],
    COMMITTED: ["publish", "stop"],
    PUBLISHED: ["draft-pr", "stop"],
    DRAFT_PR_CREATED: ["stop"],
    DIAGNOSING: ["RecordDiagnosis", "Escalate"],
    DIAGNOSIS_BLOCKED: ["BeginDiagnosticIteration", "Escalate"],
    ROOT_CAUSE_CONFIRMED: ["/ticket diagnosis:<run-id>", "stop"],
    ESCALATED: ["stop"],
  }
  return actions[status] || ["stop and inspect the persisted run"]
}

function compactState(value: any, exitCode: number): string {
  const artifacts = Object.entries(value.artifacts || {}).map(([name, record]: [string, any]) => ({
    name,
    path: record?.path,
    verdict: record?.verdict,
  }))
  return JSON.stringify(
    {
      exitCode,
      runId: value.runId,
      workflowPath: value.workflowPath,
      status: value.status,
      currentSha: value.currentSha,
      affectedModules: value.qualityPlan?.affectedModuleIds || [],
      correctionBudget: {
        used: value.correctionIterations,
        maximum: value.maximumCorrectionIterations,
      },
      diagnosticBudget: {
        used: value.diagnosticIterations,
        maximum: value.maximumDiagnosticIterations,
      },
      artifacts,
      nextActions: nextActions(String(value.status || ""), String(value.workflowPath || "")),
      terminal: ["DRAFT_PR_CREATED", "ROOT_CAUSE_CONFIRMED", "ESCALATED"].includes(String(value.status || "")),
    },
    null,
    2,
  )
}

function compactGate(value: any, exitCode: number): string {
  const modules = (Array.isArray(value.modules) ? value.modules : []).map((module: any) => {
    const failures: any[] = []
    for (const phase of Array.isArray(module.phases) ? module.phases : []) {
      for (const command of Array.isArray(phase.commands) ? phase.commands : []) {
        if (command.status === "FAIL") {
          failures.push({
            phase: phase.name,
            command: command.command,
            exitCode: command.exitCode,
            timedOut: command.timedOut,
            stderr: clip(String(command.stderr || ""), 2_000),
            stdout: clip(String(command.stdout || ""), 2_000),
          })
        }
      }
    }
    return { id: module.id, overall: module.overall, failures }
  })
  return JSON.stringify(
    {
      exitCode,
      verdict: value.overall,
      runId: value.runId,
      artifact: `.ai/runtime/${value.runId}/gates.json`,
      worktreeStable: value.worktreeStable,
      worktreeFingerprint: value.worktreeFingerprint,
      modules,
      next: value.overall === "PASS" ? "RecordGates with PASS" : "RecordGates with FAIL; do not rerun unchanged gates",
    },
    null,
    2,
  )
}

function formatProcessResult(result: ProcessResult): string {
  const stdout = result.stdout.trim()
  if (stdout) {
    try {
      const parsed = JSON.parse(stdout)
      if (parsed && parsed.runId && parsed.status && parsed.workflowPath) {
        return compactState(parsed, result.exitCode)
      }
      if (parsed && parsed.runId && parsed.overall && Array.isArray(parsed.modules)) {
        return compactGate(parsed, result.exitCode)
      }
      return JSON.stringify({ exitCode: result.exitCode, ...parsed }, null, 2)
    } catch {
      // Non-JSON command output is reported through the bounded fallback below.
    }
  }
  return JSON.stringify(
    {
      exitCode: result.exitCode,
      stdout: clip(stdout),
      stderr: clip(result.stderr.trim()),
    },
    null,
    2,
  )
}

async function invokePowerShell(
  scriptName: string,
  args: string[],
  context: ToolContext,
): Promise<string> {
  const root = repositoryRoot(context)
  const scriptPath = path.join(root, ".ai", "scripts", scriptName)
  const process = Bun.spawn(["pwsh", "-NoProfile", "-File", scriptPath, ...args], {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  })
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ])

  return formatProcessResult({ exitCode, stdout, stderr })
}

async function recordReview(
  reviewerRole: "reviewer" | "quick-reviewer",
  input: { runId: string; [key: string]: unknown },
  context: ToolContext,
): Promise<string> {
  const root = repositoryRoot(context)
  const runtimeDirectory = path.join(root, ".ai", "runtime", input.runId)
  const payloadPath = path.join(runtimeDirectory, "review-input.json")
  await mkdir(runtimeDirectory, { recursive: true })
  await writeFile(payloadPath, JSON.stringify(input), { encoding: "utf8" })
  try {
    return await invokePowerShell(
      "record-review.ps1",
      [
        "-RunId",
        input.runId,
        "-ReviewerRole",
        reviewerRole,
        "-PayloadPath",
        `.ai/runtime/${input.runId}/review-input.json`,
      ],
      context,
    )
  } finally {
    await rm(payloadPath, { force: true })
  }
}

export const state = tool({
  description: "Apply one validated transition to a persisted engineering workflow run.",
  args: {
    action: tool.schema.enum([
      "Start",
      "ApprovePlan",
      "BeginImplementation",
      "RecordGates",
      "BeginCorrection",
      "Escalate",
      "RecordDiagnosis",
      "BeginDiagnosticIteration",
      "RecordCommit",
      "RecordPublish",
      "RecordPullRequest",
      "Show",
      "Validate",
    ]),
    runId,
    workflowPath: tool.schema.enum(["standard", "fast-path", "diagnostic"]).optional(),
    taskType: tool.schema.string().min(1).max(80).optional(),
    sourceRunId: runId.optional(),
    artifactPath: relativePath.optional(),
    affectedModules: tool.schema.array(tool.schema.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)).min(1).optional(),
    verdict: tool.schema.enum(["PASS", "FAIL", "ESCALATE"]).optional(),
    reason: tool.schema.string().min(1).max(2000).optional(),
  },
  async execute(input, context) {
    const args = ["-Action", input.action, "-RunId", input.runId]
    addValue(args, "-WorkflowPath", input.workflowPath)
    addValue(args, "-TaskType", input.taskType)
    addValue(args, "-SourceRunId", input.sourceRunId)
    addValue(args, "-ArtifactPath", input.artifactPath)
    addValue(args, "-AffectedModules", input.affectedModules?.join(","))
    addValue(args, "-Verdict", input.verdict)
    addValue(args, "-Reason", input.reason)
    return invokePowerShell("workflow-state.ps1", args, context)
  },
})

export const next = tool({
  description: "Return the compact current state and deterministic next legal actions for one workflow run.",
  args: { runId },
  async execute(input, context) {
    return invokePowerShell("workflow-state.ps1", ["-Action", "Show", "-RunId", input.runId], context)
  },
})

export const standard_review = tool({
  description: "Persist a schema-valid standard review and atomically advance its exact workflow run.",
  args: reviewArgs,
  async execute(input, context) {
    return recordReview("reviewer", input, context)
  },
})

export const quick_review = tool({
  description: "Persist a schema-valid fast-path review and atomically advance its exact workflow run.",
  args: reviewArgs,
  async execute(input, context) {
    return recordReview("quick-reviewer", input, context)
  },
})

export const gate = tool({
  description: "Run the exact quality-gate matrix persisted for an approved workflow run.",
  args: {
    runId,
    timeoutSeconds: tool.schema.number().int().min(1).max(86400).optional(),
    continueAfterFailure: tool.schema.boolean().optional(),
    force: tool.schema.boolean().optional(),
  },
  async execute(input, context) {
    const args = ["-RunId", input.runId]
    addValue(args, "-TimeoutSeconds", input.timeoutSeconds)
    addSwitch(args, "-ContinueAfterFailure", input.continueAfterFailure)
    addSwitch(args, "-Force", input.force)
    return invokePowerShell("run-quality-gates.ps1", args, context)
  },
})

export const fast_path = tool({
  description: "Deterministically classify a proposed or completed quick fix or small task.",
  args: {
    taskType: tool.schema.enum(["QuickFix", "SmallTask"]),
    phase: tool.schema.enum(["Estimate", "Actual"]),
    moduleCount: tool.schema.number().int().min(0).max(1).optional(),
    fileCount: tool.schema.number().int().min(0).max(3).optional(),
    lineCount: tool.schema.number().int().min(0).max(120).optional(),
    maximumFiles: tool.schema.number().int().min(1).max(3).optional(),
    maximumLines: tool.schema.number().int().min(1).max(120).optional(),
    baseRef: tool.schema.string().min(1).max(200).optional(),
    acceptanceClear: tool.schema.boolean().optional(),
    rootCauseKnown: tool.schema.boolean().optional(),
    verificationAvailable: tool.schema.boolean().optional(),
    publicContract: tool.schema.boolean().optional(),
    newDependency: tool.schema.boolean().optional(),
    migration: tool.schema.boolean().optional(),
    securitySensitive: tool.schema.boolean().optional(),
    infrastructure: tool.schema.boolean().optional(),
    dataIntegrity: tool.schema.boolean().optional(),
    concurrency: tool.schema.boolean().optional(),
    crossModule: tool.schema.boolean().optional(),
    generatedCode: tool.schema.boolean().optional(),
  },
  async execute(input, context) {
    const args = ["-TaskType", input.taskType, "-Phase", input.phase]
    addValue(args, "-ModuleCount", input.moduleCount)
    addValue(args, "-FileCount", input.fileCount)
    addValue(args, "-LineCount", input.lineCount)
    addValue(args, "-MaximumFiles", input.maximumFiles)
    addValue(args, "-MaximumLines", input.maximumLines)
    addValue(args, "-BaseRef", input.baseRef)
    addSwitch(args, "-AcceptanceClear", input.acceptanceClear)
    addSwitch(args, "-RootCauseKnown", input.rootCauseKnown)
    addSwitch(args, "-VerificationAvailable", input.verificationAvailable)
    addSwitch(args, "-PublicContract", input.publicContract)
    addSwitch(args, "-NewDependency", input.newDependency)
    addSwitch(args, "-Migration", input.migration)
    addSwitch(args, "-SecuritySensitive", input.securitySensitive)
    addSwitch(args, "-Infrastructure", input.infrastructure)
    addSwitch(args, "-DataIntegrity", input.dataIntegrity)
    addSwitch(args, "-Concurrency", input.concurrency)
    addSwitch(args, "-CrossModule", input.crossModule)
    addSwitch(args, "-GeneratedCode", input.generatedCode)
    return invokePowerShell("fast-path-check.ps1", args, context)
  },
})

export const validate_project = tool({
  description: "Validate the installed project configuration, generated skills, and structural profile.",
  args: {},
  async execute(_input, context) {
    return invokePowerShell("validate-project.ps1", [], context)
  },
})

export const profile_project = tool({
  description: "Inspect repository structure and optionally persist the deterministic project profile.",
  args: {
    persist: tool.schema.boolean().optional(),
  },
  async execute(input, context) {
    const args: string[] = []
    if (input.persist) args.push("-OutputPath", ".ai/project-profile.json")
    return invokePowerShell("profile-project.ps1", args, context)
  },
})

export const bootstrap_prepare = tool({
  description: "Prepare a durable bootstrap proposal under .ai/bootstrap-proposal and validate it as a dry run.",
  args: {
    force: tool.schema.boolean().optional(),
  },
  async execute(input, context) {
    const args: string[] = []
    addSwitch(args, "-Force", input.force)
    return invokePowerShell("prepare-bootstrap-proposal.ps1", args, context)
  },
})

export const bootstrap_apply = tool({
  description: "Validate and apply the approved durable bootstrap proposal from .ai/bootstrap-proposal.",
  args: {
    dryRun: tool.schema.boolean().optional(),
  },
  async execute(input, context) {
    const args: string[] = []
    addSwitch(args, "-DryRun", input.dryRun)
    return invokePowerShell("apply-bootstrap-proposal.ps1", args, context)
  },
})

export const validate_diagnosis = tool({
  description: "Validate a production-diagnosis artifact before it can advance workflow state.",
  args: {
    path: relativePath,
    expectedRunId: runId.optional(),
  },
  async execute(input, context) {
    const args = ["-Path", input.path]
    addValue(args, "-ExpectedRunId", input.expectedRunId)
    return invokePowerShell("validate-diagnosis.ps1", args, context)
  },
})

export const delivery_check = tool({
  description: "Evaluate delivery readiness without performing a Git or GitHub mutation.",
  args: {
    remote: tool.schema.string().regex(/^[A-Za-z0-9._-]+$/).optional(),
  },
  async execute(input, context) {
    const args: string[] = []
    addValue(args, "-Remote", input.remote)
    return invokePowerShell("delivery-check.ps1", args, context)
  },
})
