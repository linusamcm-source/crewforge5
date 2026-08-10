# Optional: Wire Into Pre-Commit Hook

```bash
# In .git/hooks/pre-commit (or via husky)
just review-staged --severity=HIGH || {
  echo "Pre-commit review found HIGH findings. Address or waive."
  exit 1
}
```

The corresponding `just` recipe runs this skill against
`git diff --cached` and exits non-zero if any HIGH+ finding is
unresolved. Users can bypass with explicit `// REVIEW-WAIVED: <reason>`
comments in the diff — the reviewer agent recognises and skips findings
on waived hunks. Project rule: never `--no-verify`.
