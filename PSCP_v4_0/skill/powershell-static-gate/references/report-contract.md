# PSCP gate contract

Use these fields to decide whether PowerShell can be handed off for runtime testing:

| Exit | Verdict | Required response |
|---:|---|---|
| 0 | `PASS_STATIC` | State that all required static engines completed; runtime testing must still be isolated. |
| 1 | `REVIEW` | Review and normally fix warnings, then rerun. If a warning is accepted, report its rule ID and reason. |
| 2 | `BLOCK` | Do not run or hand off as ready. Fix blocking findings and rerun. |
| 3 | `INCOMPLETE` | Restore the missing engine/file/coverage and rerun. Never treat this as clean. |
| 4 | `FATAL` | Correct the request, launcher, or analyzer failure and rerun. |

Always inspect:

- `analysisComplete` and `safeToBeginSandboxTesting`;
- `summary.directAnswer` and `summary.recommendedAction`;
- each required entry in `coverage[]`;
- unsuppressed `findings[]`, particularly `blocking`, `severity`, `confidence`, `consequence`, and `remediation`;
- `malwareAssessment` and `decodedArtifacts[]`;
- `capabilities[]` and the generated `testPlan[]`.

Do not use `MinimumSeverity` to hide issues while deciding the verdict. PSCP calculates the verdict from the complete finding set before applying the report filter.

The launcher is pinned to an immutable ZiAAS GitHub commit and validates the analyzer SHA-256 before use. A valid cached copy is reused; a mismatched cache fails closed unless an explicitly requested refresh successfully downloads and validates a replacement.
