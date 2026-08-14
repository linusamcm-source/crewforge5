# File handling

## Raw text input

Rewrite and return the rewritten text. No file operations needed.

## .docx input

Use the `officecli` skill (read its SKILL.md for guidance) to:

1. Read the document, preserving structure (headings, lists, tables, comments).
2. Rewrite paragraph-by-paragraph, keeping structural markup intact.
3. Write back to a new .docx with `-humanised` suffixed to the filename.
4. Save to the user's outputs folder and share the link.

Don't attempt to rewrite text inside figures, tables with numeric data, or code blocks — only prose.

## When user hasn't specified

If the input is short enough to paste, return text. If they've handed over a file, return a file.
