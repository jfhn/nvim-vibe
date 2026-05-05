# nvim-vibe

Neovim plugin for task-driven workflow. Manage projects, git worktrees, and markdown tasks from within Neovim.

## Features

- **Project switching** - switch between projects via sidebar or telescope picker
- **Git worktrees** - create/remove worktrees per project
- **Task management** - markdown-based tasks with sidebar tree view, toggle completion via hotkey
- **Hooks** - fire events on project/task changes for external integration

## Install

With Neovim 0.12+ built-in pack:

```sh
vim.pack.add {
  ...
  'https://github.com/jfhn/nvim-vibe',
  ...
}
```

## API

```lua
local vibe = require("nvim-vibe")

-- projects
vibe.switch(project_name)
vibe.add_project(path)
vibe.remove_project(name)
vibe.add_worktree(project, branch)
vibe.remove_worktree(project, worktree_name)

-- tasks
vibe.tasks()         -- open task file
vibe.add_task(title)
vibe.toggle_task()   -- toggle task at cursor
vibe.remove_task()
vibe.list_tasks()    -- list all tasks across projects

-- sidebar
vibe.toggle_sidebar()

-- hooks (for AI integration)
vibe.on("project switched", function(project)
  print("now on", project.name)
end)

vibe.setup()
```

## Keys

In sidebar:
- `<CR>` switch / open
- `r` rename task file
- `d` delete with confirmation
- `C-r` refresh

## Next Goal

OpenCode / Claude Code integration to visualize task state during AI agent work.
