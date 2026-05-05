# nvim-vibe Plugin Plan

## Storage
- **Config**: `~/.local/nvim-vibe/projects.lua`
- **Start**: Empty, user adds projects
- Single nvim instance assumed

## Project Structure

```lua
-- ~/.local/nvim-vibe/projects.lua
return {
  ["my-project"] = {
    path = "/path/to/my-project",
    description = "My main project",
    worktrees = {
      ["feat/x"] = "/path/to/feat-x",
    }
  },
}
```

## Core Features (v1)
1. **Project switching** — `cd` into worktree, change cwd
2. **Buffer cleanup on switch** — wipe bufs from previous worktree (LSP mem: rust-analyzer w/ many bufs = GB)
3. **Worktree management** — Add/remove worktrees per project
4. **Telescope integration** — Pick project/worktree via telescope
5. **Sidebar UI** — Simple tree view: projects → worktrees, toggle + expand
6. **Auto-detection** — Only activate if cwd matches known project
7. **Hooks** — `on_switch` callbacks (LSP restart, env reload, custom)

## Git Integration
- Set `cwd` before invoking Neogit/Fugitive
- Store worktree paths in config (no re-scanning)

## Interface
- Expose functions, no default keybindings
- User creates commands/keymaps
- Telescope pickers registered automatically

## Future (v2)
- Tasks stored in config
- Notifications (agent status)
- Floating overview window

---

## Key Design Decisions
- **Directory**: `~/.local/nvim-vibe/`
- **Switch behavior**: Switch cwd + wipe old bufs
- **Worktree naming**: Explicit, suggested format
- **Startup**: No auto-activate unless cwd matches known project
- **Interface**: API-only, no default keymaps
- **Telescope**: Core dependency, not optional