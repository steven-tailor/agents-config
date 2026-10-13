---
name: save-to-obsidian
description: Save or update an editable Markdown prompt, specification, ticket, or related document in the user's private Obsidian Engineering vault. Use when the user asks to store, capture, publish, or keep such content in Obsidian; route it to prompts, specs, or tickets. Do not use for merely reading or discussing a note.
---

# Save to Obsidian

Treat Markdown files as source of truth. Obsidian is only the user's editor/viewer.

## Destination

Vault root: `/Users/studio/Documents/Obsidian/Engineering`

Route by requested artifact:

- prompt -> `prompts/`
- spec or specification -> `specs/`
- ticket or issue -> `tickets/`
- generic doc -> infer `prompts/`, `specs/`, or `tickets/` from its purpose; ask one concise question when purpose is ambiguous

Create the selected directory when absent. Preserve any deeper path or project grouping the user explicitly supplies.

## Write

1. Save exactly one `# Title`, then the requested Markdown content. Preserve headings that belong to the content. Add no YAML frontmatter, metadata, summary, description, document-type section, explanatory preface, or outer Markdown code fence.
2. Use the user's supplied content and requested structure. If drafting is requested, produce concise Markdown appropriate to the artifact type.
3. Preserve a supplied filename. Otherwise derive a clear `.md` filename from the title or subject, matching nearby naming style when the destination already contains notes.
4. Before replacing an existing file, inspect it. Update it only when the user requested an edit or replacement; otherwise ask which version should win.
5. Write only the requested note and any missing destination directories. Do not operate Obsidian UI, modify vault settings, or create an external tracker entry.
6. Read the saved file back and verify destination and content. Return its absolute clickable path.

If filesystem access fails, report the exact path and error. Ask the user to grant access, then retry the same destination. Never fall back to Linear, GitHub, Notion, or another service.
