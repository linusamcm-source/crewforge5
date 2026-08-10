# Stack-specific tooling

Detect the stack from the manifest and run the relevant tools. Run them in parallel when possible.

- **TypeScript / JavaScript** — `npm audit`, `npx knip` (dead exports), `npx madge --circular` (circular deps), `npx depcheck` (unused deps), `tsc --noEmit` for type drift.
- **Python** — `pip-audit`, `ruff check`, `vulture` (dead code), `pydeps --show-cycles`, `mypy --strict` for type drift.
- **Rust** — `cargo audit`, `cargo udeps`, `cargo machete`, `cargo clippy -- -W clippy::pedantic`.
- **Go** — `govulncheck`, `go vet`, `staticcheck`, `golangci-lint run`.
- **PowerShell** — `Invoke-ScriptAnalyzer -Path . -Recurse` (respect any `PSScriptAnalyzerSettings.psd1`), Pester with coverage if configured; no CVE scanner exists for PS modules, so review `RequiredModules` pinning by inspection.
- **Any other stack** — run the language-native linter/analyzer and CVE scanner if one exists; if none does, do the dependency review by inspection and say so in the audit.

If a tool isn't installed, note it in the audit and move on rather than blocking. Do not install dev tools globally without permission.
