---
name: macos-desktop-cleanup
description: Use when the user explicitly wants to organize Desktop files on macOS. Enforces preview-first cleanup, explicit confirmation before moves, no permanent delete, and undo-manifest reporting.
---

# macOS Desktop Cleanup Workflow

## Overview

Use this skill for requests like:

- "clean up my desktop"
- "organize desktop files"
- "sort my desktop by type"

This skill is move-only by default. No permanent deletion.

## Trigger Guard

Use this skill only for explicit filesystem organization requests.

If wording could refer to code cleanup rather than desktop files, ask a one-line disambiguation question first.

## Non-Negotiable Rules

1. Always show a preview plan before making changes.
2. Never delete files in V1 cleanup.
3. Execute only after explicit user confirmation.
4. Write/return undo details whenever files are moved.
5. Keep the user informed of exact scope and file counts.

## Default Scope

- Target directory: `~/Desktop`
- Include: regular files
- Exclude by default: directories, symlinks, hidden files

If user wants different scope/rules, confirm before preview.

## Execution Order

1. Clarify cleanup policy
- Confirm:
  - target path
  - grouping scheme (by file type default)
  - whether hidden files should be included (default no)

2. Generate preview plan
- Build candidate list and destination folders.
- Show:
  - operation count
  - sample moves
  - folder breakdown (Images, Documents, Code, Archives, Other)
- For generic requests, proceed with this preview using default scope instead of asking extra setup questions first.

3. Ask explicit confirmation
- Require phrase: `apply cleanup`.
- If user declines, stop without changes.

4. Execute move operations
- Prefer native action path when available: `desktop.cleanup`.
- Fallback script must:
  - create destination folders
  - avoid name collisions
  - move atomically per file
  - record undo mapping (`sourcePath`, `movedPath`)

5. Return summary
- Number of files moved.
- Destination folder counts.
- Undo manifest path/details.

## Fallback Implementation Notes

When native action is unavailable:

- Enumerate regular files only.
- Create deterministic destination mapping by extension.
- For collisions, append numeric suffix (`-2`, `-3`, ...).
- Persist undo manifest in app/workspace-owned storage.

## Suggested Folder Mapping

- Images: png, jpg, jpeg, gif, heic, svg, webp
- Media: mov, mp4, m4v, mkv, avi, mp3, wav, aiff
- Archives: zip, tar, gz, bz2, rar, 7z
- Code: swift, js, ts, tsx, py, go, rs, java, c, cpp, json, toml, yml
- Documents: pdf, doc, docx, txt, md, rtf, pages, csv, xlsx, pptx
- Other: everything else

## Undo Behavior

If user asks to undo:

1. Locate latest cleanup undo manifest.
2. Move files back from `movedPath` to original `sourcePath`.
3. Handle collisions safely (no overwrite without consent).
4. Report restored count and any skipped files.

## Failure Handling

- Missing Desktop path:
  - Ask for corrected path.
- Permission/file lock errors:
  - Report specific blocked files.
- Partial completion:
  - Report moved/skipped counts and keep undo data for moved files.

## Output Contract

Always include:

1. Preview summary before execution.
2. Explicit note whether execution happened.
3. Final moved count (if executed).
4. Undo manifest location/details.
5. Confirmation that no permanent deletes were performed.
