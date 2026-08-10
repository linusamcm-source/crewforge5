---
name: plugin-forge
model: sonnet
description: Create and manage Claude Code plugins. Use when creating plugins for a marketplace, adding components (commands, agents, hooks), bumping plugin versions, or editing plugin.json/marketplace.json
disable-model-invocation: true
---

# CC Plugin Forge

## Purpose

Build and manage Claude Code plugins with correct structure, manifests, and marketplace integration.

## When to Use

- Creating new plugins for a marketplace
- Adding/modifying plugin components (commands, skills, agents, hooks)
- Updating plugin versions
- Working with plugin or marketplace manifests
- Setting up local plugin testing
- Publishing plugins

## Getting Started

### Create New Plugin

Follow the Development Workflow below — directory structure, then
`plugin.json`, then the marketplace entry. `claude plugin init <name>` scaffolds
a starting point if you would rather not write the manifest by hand, and
`claude plugin validate <path>` checks it before you publish.

### Bump Version

Edit the version in **both** manifests and keep them equal — `claude plugin tag`
validates exactly that agreement before cutting a release tag.

Semantic versioning:

- **major**: Breaking changes (1.0.0 → 2.0.0)
- **minor**: New features, refactoring (1.0.0 → 1.1.0)
- **patch**: Bug fixes, docs (1.0.0 → 1.0.1)

## Development Workflow

### 1. Create Structure



```bash
mkdir -p plugins/plugin-name/.claude-plugin
mkdir -p plugins/plugin-name/commands
mkdir -p plugins/plugin-name/skills
```

### 2. Plugin Manifest

File: `plugins/plugin-name/.claude-plugin/plugin.json`

```json
{
  "name": "plugin-name",
  "version": "0.1.0",
  "description": "Plugin description",
  "author": {
    "name": "Your Name",
    "email": "your.email@example.com"
  },
  "keywords": ["keyword1", "keyword2"]
}
```

### 3. Register in Marketplace

Update `.claude-plugin/marketplace.json`:

```json
{
  "name": "plugin-name",
  "source": "./plugins/plugin-name",
  "description": "Plugin description",
  "version": "0.1.0",
  "keywords": ["keyword1", "keyword2"],
  "category": "productivity"
}
```

### 4. Add Components

Create in respective directories:

| Component   | Location           | Format                    |
| ----------- | ------------------ | ------------------------- |
| Commands    | `commands/`        | Markdown with frontmatter |
| Skills      | `skills/<name>/`   | Directory with `SKILL.md` |
| Agents      | `agents/`          | Markdown definitions      |
| Hooks       | `hooks/hooks.json` | Event handlers            |
| MCP Servers | `.mcp.json`        | External integrations     |

### 5. Local Testing

```bash
# Add marketplace
/plugin marketplace add /path/to/marketplace-root

# Install plugin
/plugin install plugin-name@marketplace-name

# After changes: reinstall
/plugin uninstall plugin-name@marketplace-name
/plugin install plugin-name@marketplace-name
```

## Plugin Patterns

### Framework Plugin

For framework-specific guidance (React, Vue, etc.):

```
plugins/framework-name/
├── .claude-plugin/plugin.json
├── skills/
│   └── framework-name/
│       ├── SKILL.md
│       └── references/
├── commands/
│   └── prime/
│       ├── components.md
│       └── framework.md
└── README.md
```

### Utility Plugin

For tools and commands:

```
plugins/utility-name/
├── .claude-plugin/plugin.json
├── commands/
│   ├── action1.md
│   └── action2.md
└── README.md
```

### Domain Plugin

For domain-specific knowledge:

```
plugins/domain-name/
├── .claude-plugin/plugin.json
├── skills/
│   └── domain-name/
│       ├── SKILL.md
│       ├── references/
│       └── scripts/
└── README.md
```

## Command Naming

Subdirectory-based namespacing with `:` separator:

- `commands/namespace/command.md` → `/namespace:command`
- `commands/simple.md` → `/simple`

Examples:

- `commands/prime/vue.md` → `/prime:vue`
- `commands/docs/generate.md` → `/docs:generate`

## Version Management

**Important:** Update version in BOTH locations:

1. `plugins/<name>/.claude-plugin/plugin.json`
2. `.claude-plugin/marketplace.json`

`claude plugin tag` fails when they disagree, so a mismatch is caught at release
rather than by an installer.

## Git Commits

Use conventional commits:

```bash
git commit -m "feat: add new plugin"
git commit -m "fix: correct plugin manifest"
git commit -m "docs: update plugin README"
git commit -m "feat!: breaking change"
```
