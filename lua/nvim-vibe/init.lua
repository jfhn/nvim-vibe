local core = require("nvim-vibe.core")
local hooks = require("nvim-vibe.hooks")
local sidebar = require("nvim-vibe.sidebar")
local telescope = require("nvim-vibe.telescope")

local M = {}

M.switch = core.switch
M.add_project = core.add_project
M.remove_project = core.remove_project
M.add_worktree = core.add_worktree
M.remove_worktree = core.remove_worktree
M.state = core.state
M.detect = core.detect
M.reload = core.reload

M.toggle_sidebar = sidebar.toggle
M.open_sidebar = sidebar.open
M.close_sidebar = sidebar.close

M.pick = telescope.projects

M.on = hooks.register
M.fire = hooks.fire

function M.setup(opts)
  opts = opts or {}
  core.reload()
  core.detect()

  if opts.hooks then
    for event, fns in pairs(opts.hooks) do
      if type(fns) == "function" then
        hooks.register(event, fns)
      else
        for _, fn in ipairs(fns) do
          hooks.register(event, fn)
        end
      end
    end
  end

  require("telescope").load_extension("nvim-vibe")
end

return M
