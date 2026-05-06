# Handoff: Phase 1 Frontmatter Double-Write Bug

## Status

Phase 1 task storage is implemented but has a critical bug in `tasks.create()` BufWriteCmd callback.

## Bug

When user saves a new task via `:NvimVibe tasks`, the resulting `node.md` has **doubled frontmatter** — the callback writes a new frontmatter block (with updated title) but the original frontmatter from the template remains in the body, producing invalid output:

```
---
id: task_1778101542_cb5
title: untitled
---

: agent
title: 
status: planned
...
```

## Root Cause

In `lua/nvim-vibe/tasks.lua`, the `BufWriteCmd` callback at ~line 161:

1. Reads buffer lines as raw text
2. Parses with `fm.parse()` to get meta + body
3. Modifies `meta.title` 
4. Re-serializes with `fm.serialize(raw_meta, body)`

The problem: `fm.serialize()` writes frontmatter from `raw_meta`, then appends `body`. But `body` still contains the **remaining unparsed frontmatter fields** because `fm.parse()` only extracted some fields into `meta` — the rest ended up in `body`.

## Likely Parse Bug

`fm.parse()` in `lua/nvim-vibe/frontmatter.lua` is probably failing to parse all frontmatter fields. Check:

1. Does `_coerce` handle all value types correctly?
2. Does the parser handle `kind: agent` (no quotes) correctly?  
3. The `title: ` line (empty value) may cause the parser to enter "nested map" mode, treating subsequent lines (`status: planned`, etc.) as children of `title` — then those lines never make it into `meta` as top-level keys and instead remain in `body`.

**Most likely cause**: when `title:` has empty value, parser sets `current_map_key = "title"` and starts collecting nested keys. The next line `status: planned` doesn't start with two spaces, so it should exit nested mode — verify this logic in the `elseif line:match("^  %S")` branch. The issue may be that `kind: agent` on the line right after `title:` is NOT indented, so it should be parsed as a new top-level key — but if `current_map_key` isn't cleared properly, it could be skipped.

## Suggested Fix Approach

Instead of re-serializing the entire frontmatter, do a **targeted field update** in the raw buffer text:

1. Find `title: ` line in buffer
2. Replace with `title: <extracted_title>`
3. Write buffer as-is

This avoids round-tripping through parse/serialize entirely for the create flow. The full parse/serialize path should still be fixed for correctness, but targeted update is more robust for the save callback.

## Files

- `lua/nvim-vibe/frontmatter.lua` — parser + serializer, likely parse bug in nested map detection
- `lua/nvim-vibe/tasks.lua` — `create()` BufWriteCmd callback at ~line 161
- `lua/nvim-vibe/id.lua` — ID generation, works correctly
- `lua/nvim-vibe/init.lua` — exposes `read_node`/`write_node`

## What Works

- `id.lua` — generates correct IDs
- `tasks.add()` — programmatic task creation works (no round-trip parse/serialize)
- `tasks.list()` — reads directory-based tasks correctly
- `tasks.toggle()` — toggles status
- `tasks.remove()` — deletes task directory
- Sidebar — compatible with new format

## What Needs Testing After Fix

1. Create task via `:NvimVibe tasks`, type title, `:w` — verify single clean frontmatter
2. Sidebar shows new task with correct title
3. Toggle task done/undone from sidebar
4. Delete task from sidebar
5. Re-open node.md — frontmatter parses cleanly

## Branch

`plan/v2`, latest commit `21376df`

## Plan Context

See `plans/vibe.v2.md` for full v2 design. This bug is in Phase 1 (Task Root Storage). Phases 2-7 depend on correct frontmatter round-tripping.
