# Failure Modes

- **Reviewer returns no findings on a clearly risky change.** Likely
  the reviewer's lane was too narrow — re-spawn with broader scope, or
  add the missing pattern to the reviewer's role contract for next run.
- **Reviewers disagree on severity.** Default to the higher severity.
  Both perspectives are valid; the user can downgrade in the report.
- **`--auto-fix` keeps regressing the same finding.** Stop after 2
  rounds and surface the loop — the fix-implementer is misunderstanding
  the finding. Manual intervention required.
- **Diff is huge (>2000 lines).** Split by directory or path prefix and
  run multiple fleets sequentially. A single reviewer drowning in diff
  produces shallow findings.
