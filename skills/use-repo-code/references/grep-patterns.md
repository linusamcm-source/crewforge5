# Common grep patterns by language

Patterns for grepping the repomix pack. Always add `-B 2` so the hit carries its owning
`<file path="...">` tag. The pack is `--compress`ed — signatures and structure survive,
function bodies may not; for body-level detail, live-read the file the tag points to.

## Finding the file block itself (any language)

```
^<file path="path/to/expected\.ext">$        # exact file exists?
<file path="[^"]*services/                   # everything under a directory
```

## TypeScript / JavaScript

| Question | Pattern |
|---|---|
| Symbol defined? | `function CreateThing\|const CreateThing\|class CreateThing` |
| Exported? | `export (default )?(function\|const\|class) CreateThing` |
| Route handler exists? | `(get\|post\|put\|delete)\(['"]/v1/foo` |
| Test coverage? | `describe\(['"]CreateThing\|it\(['"].*creates` |
| Layer violation? | `import .* from '@/services` (inside UI/store files) |
| Type escape hatches | `: any\|as any\|@ts-ignore\|@ts-expect-error` |

## Go

| Question | Pattern |
|---|---|
| Symbol defined? | `func (\(\w+ \*?\w+\) )?CreateThing` |
| Interface? | `type Thing interface` |
| Test coverage? | `func TestCreateThing` |
| Error swallowed? | `_ = err\|err != nil \{\s*$` |

## Python

| Question | Pattern |
|---|---|
| Symbol defined? | `def create_thing\|class CreateThing` |
| Test coverage? | `def test_create_thing` |
| Type escape hatches | `# type: ignore\|Any\]` |
| Error swallowed? | `except.*:\s*pass\|except Exception:` |

## Rust

| Question | Pattern |
|---|---|
| Symbol defined? | `fn create_thing\|struct CreateThing\|impl CreateThing` |
| Test coverage? | `#\[test\]` near `create_thing` |
| Panic paths | `\.unwrap\(\)\|\.expect\(\|panic!` |

## PowerShell

Verb-Noun naming means symbol greps anchor on the verb list. `.psd1` manifests and
`.psm1` loaders are the contract surface — grep them first.

| Question | Pattern |
|---|---|
| Cmdlet/function defined? | `function\s+(Get\|Set\|New\|Remove\|Invoke\|Import\|Export\|Test\|Backup\|Restore)-\w+` |
| Specific cmdlet? | `function\s+Invoke-RsMigration\b` |
| Exported from module? | `FunctionsToExport\|Export-ModuleMember` |
| Advanced function? | `\[CmdletBinding\|\[Parameter\(` |
| Return contract declared? | `\[OutputType\(` |
| Input validation? | `\[ValidateSet\|\[ValidateNotNull\|\[ValidateScript` |
| Test coverage (Pester)? | `Describe\s+['"].*Invoke-RsMigration\|It\s+['"]` |
| Error handling style | `catch\s*\{\|-ErrorAction\|\$ErrorActionPreference\|throw\s` |
| Destructive-op guard | `SupportsShouldProcess\|ShouldProcess\(\|-WhatIf\|-Confirm` |
| Output/logging drift | `Write-(Host\|Verbose\|Warning\|Error\|Information\|Debug)` |
| Secrets handling | `ConvertTo-SecureString\|AsPlainText\|ConvertFrom-SecureString\|Get-Credential` |
| SQL surface | `Invoke-Sqlcmd\|Invoke-DbaQuery\|SqlClient\|-Query\s` |
| Module dependencies | `RequiredModules\|Import-Module\|using module` |

## Generic (any stack)

| Question | Pattern |
|---|---|
| TODO debt | `TODO\|FIXME\|HACK\|XXX` |
| Hardcoded secrets | `(api[_-]?key\|secret\|password\|token)\s*[:=]\s*['"][^'"$]` |
| Env var usage | `process\.env\.\|os\.environ\|env::var\|\$env:` |
