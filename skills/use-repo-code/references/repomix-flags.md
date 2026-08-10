# Recommended pack-generation flags per project size

Base command (all sizes):

```bash
repomix --compress --style xml --remove-comments --remove-empty-lines \
  --truncate-base64 --top-files-len 20 -o "$PACK" --ignore "<ignore-list>"
```

## Ignore list

Always exclude derived artifacts and lockfiles — they pollute greps with noise that
looks like findings (e.g. committed knowledge-graph JSON matching security patterns):

```
**/node_modules/**,**/dist/**,**/build/**,**/.next/**,**/.expo/**,**/coverage/**,
**/cdk.out/**,**/*.lock,**/package-lock.json,**/bun.lockb,**/yarn.lock,
**/graphify-out/**,**/.repomix-output.xml,**/.venv/**,**/__pycache__/**,**/target/**
```

## By repo size

| Repo size | Flags | Notes |
|---|---|---|
| Small (<5k LOC) | base flags; consider dropping `--compress` | Full bodies fit; compression loses more than it saves. PowerShell in particular compresses poorly (Tree-sitter grammar keeps little beyond `function` lines) — prefer uncompressed for PS-heavy repos. |
| Medium (5k–50k LOC) | base flags | The default sweet spot. |
| Large (50k–200k LOC) | base + `--include "src/**,lib/**"` per module | Pack per top-level module; one giant pack makes `-A` windows useless. |
| Very large (>200k LOC) | pack only the module under audit | Whole-repo packs exceed practical grep signal. |

## Freshness

Regenerate when missing or older than 2 hours (SKILL.md Step 1). Multi-agent flows:
regenerate once at flow start so every agent greps the same snapshot.
