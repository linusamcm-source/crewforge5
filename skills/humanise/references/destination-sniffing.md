# Destination sniffing

`scripts/sniff.sh` scores cheap signals and emits `scenario= confidence= evidence=` lines. This file documents the contract and what the model does with each confidence level.

## Signal table (implemented in sniff.sh)

| Signal | Scenario | Weight |
|---|---|---|
| `--path` basename README* | readme | 2 |
| `--path` source-file extension (.py .ts .go ...) | docstring | 2 |
| `--path` COMMIT_EDITMSG | commit-message | 3 |
| `--path` on non-main git branch | pr-description | 1 |
| `--hint` slack/whatsapp/dm/chat/mate | casual-message | 2 |
| `--hint` email | email | 2 |
| `--hint` board/tender/proposal/client | formal-doc | 2 |
| `--hint` report/briefing/postmortem | report | 2 |
| `--hint` pull request / pr description | pr-description | 2 |
| Draft opens hey/hi/hiya/g'day | email +1, casual +1 | 1 |
| Draft opens "Dear" | formal-doc | 2 |
| Imperative first line (Add/Fix/Update...) | pr +2, commit +1 | 2 |
| <50 words | casual-message | 1 |
| >600 words / ≥3 headings | report | 1 |
| Email sign-off present | email | 1 |

## Confidence contract

- **high** — proceed silently; put the routing receipt in the output note: "treated as PR description (evidence: imperative first line, branch feat/x) — say `as email` to override".
- **medium** — proceed, but flag prominently before the rewrite: "guessing report; redo as something else on request".
- **low / unknown** — fire the intake gate (AskUserQuestion), pre-filled with the best guess as the recommended option.

User override always wins: "as casual", "as formal-doc", any explicit register naming skips sniffing entirely.

## Sibling house-style recipes (repo-bound scenarios)

- **readme**: other README.md files in the repo/org.
- **pr-description**: `gh pr list --state merged --limit 5 --json title,body`.
- **docstring**: docstrings in the nearest three files of the same language.
- **commit-message**: `git log --oneline -20` plus `git log -5 --format=%B`.

**Contamination rule**: vet every sibling with `scripts/tells.sh --max 3 <file>` before imitating it. A sibling that fails is discarded — an AI-written or sludge-ridden exemplar would faithfully reproduce exactly what this skill exists to remove. `references/llm-tells.md` and the voice profile always outrank sibling style.
