---
name: powershell-static-gate
description: Mandatory final static-analysis gate for every task that creates, edits, refactors, fixes, or outputs PowerShell source (.ps1, .psm1, or .psd1). Automatically run PSCP after the final source change and before handing PowerShell to the user; also use for explicit PowerShell validation and pre-runtime safety reviews.
---

# PowerShell Static Gate

Run PSCP as the last verification step for every PowerShell artifact Codex produces or changes. This gate is mandatory even when the user did not explicitly request analysis.

## Required workflow

1. Finish the intended PowerShell edits first.
2. Do not import, dot-source, invoke, or run the target script or its tests merely to validate it.
3. Run the bundled launcher against every changed `.ps1`, `.psm1`, and `.psd1` file:

   ```powershell
   & "$PSScriptRoot\scripts\Invoke-PowerShellStaticGate.ps1" -Path <changed-paths> -AnalysisProfile Maximum -DependencyMode AutoInstall -OutputPath <workspace-report.json>
   ```

   When operating from outside this skill, resolve the skill directory first and use its absolute script path. Put reports in task scratch/work space unless the user requested them as deliverables.
4. Read the JSON verdict, `analysisComplete`, required engine statuses, blocking findings, and recommended action. Never infer success from empty output.
5. Fix actionable findings introduced by the work and rerun the gate. Continue until `PASS_STATIC`, or until remaining findings require a user decision or a runtime-only environment.
6. In the handoff, state the verdict and whether all required engines completed. For `REVIEW`, `BLOCK`, `INCOMPLETE`, or `FATAL`, include the exact unresolved rule IDs and next action.

For an inline PowerShell snippet that is not otherwise saved, place the exact snippet in a temporary `.ps1` under the task workspace, analyze it, and remove or retain the temporary file according to the workspace policy.

## Non-negotiable boundaries

- `PASS_STATIC` means ready to begin isolated runtime testing; it is not proof of safety or absence of malware.
- `INCOMPLETE` and `FATAL` are failures, never passes. Do not skip the gate because PSGallery, networking, or a host is unavailable.
- Use only the launcher's immutable GitHub source and pinned SHA-256. Do not replace it with `Invoke-RestMethod | Invoke-Expression`, a mutable unverified raw URL, Defender, or another scanner.
- The launcher may install only the analyzer's exact pinned `PSScriptAnalyzer` version from PSGallery. Do not add arbitrary package sources or bypass publisher checks.
- Do not weaken or suppress a rule merely to obtain a pass. A narrow suppression needs a real justification in source and must remain visible in the report.
- Static analysis does not authorize runtime execution, external writes, deployment, or tests. Those still follow the user's requested scope and normal approval boundaries.

Read [references/report-contract.md](references/report-contract.md) when integrating the gate into CI, interpreting a non-pass verdict, or changing the wrapper/report handling.
