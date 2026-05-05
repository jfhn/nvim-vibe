# Named Terminal Buffer Plan

## Implementation: `lua/nvim-vibe/terminal.lua`

### Syntax

- `:Term this is a session` → name="this is a session", shell=`vim.o.shell`
- `:Term[zsh] this is a session` → name="this is a session", shell="zsh"

### Command Definition

```lua
vim.api.nvim_create_user_command("Term", function(args)
  -- args.fargs = table of arguments (space-separated)
  -- args.bang = boolean for `!` modifier
end, { nargs = "*" })
```

### Parsing Logic

1. Join all args into string
2. Match `^\[([^\]]+)\]` at start (shell in brackets)
3. Rest becomes name

### Terminal Creation

```lua
-- jobstart with term feature
local job = vim.fn.jobstart({shell}, {
  term = true,
  on_exit = function()
    -- optional: close/wipe buffer on exit
  end
})

-- Open term buffer
local buf = vim.api.nvim_open_term(bufnr, {...})
```

### Buffer Naming

```lua
vim.api.nvim_buf_set_name(bufnr, "term://" .. name)
```

Or using `keepalt file`:
```lua
vim.cmd.keepalt("file " .. name)
```

### Module API

```lua
local M = {}

function M.open(name, opts)
  opts = opts or {}
  local shell = opts.shell or vim.o.shell
  -- create terminal and set name
end

function M.setup()
  -- register :Term command
end

return M
```

### Optional Enhancements

- Persist terminals (Toggleterm-style toggle)
- Track terminals in table for cycling/toggling
- Autoclose option
- Custom working directory