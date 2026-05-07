local core = require("nvim-vibe.core")
local hooks = require("nvim-vibe.hooks")
local sidebar = require("nvim-vibe.sidebar")
local telescope = require("nvim-vibe.telescope")
local tasks = require("nvim-vibe.tasks")
local terminal = require("nvim-vibe.terminal")
local task_tree = require("nvim-vibe.task_tree")
local task_runtime = require("nvim-vibe.task_runtime")
local task_events = require("nvim-vibe.task_events")
local backend_mod = require("nvim-vibe.backend")
local planner_mod = require("nvim-vibe.planner")

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

M.tasks = tasks.create
M.add_task = tasks.add
M.toggle_task = tasks.toggle
M.remove_task = tasks.remove
M.list_tasks = tasks.list
M.read_node = task_tree.read_node
M.write_node = task_tree.write_node

M.tree = task_tree
M.runtime = task_runtime
M.events = task_events
M.backend = backend_mod
M.planner = planner_mod

M.on = hooks.register
M.fire = hooks.fire

M.term = terminal.open
M.terminals = terminal.list

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

  terminal.setup(opts.terminal)

  backend_mod.register("stub", require("nvim-vibe.backend.stub"))

  local opencode = require("nvim-vibe.backend.opencode")
  if opts.opencode then
    if opts.opencode.model then opencode.config.model = opts.opencode.model end
    if opts.opencode.command then opencode.config.command = opts.opencode.command end
  end
  backend_mod.register("opencode", opencode)

  require("telescope").load_extension("nvim-vibe")
end

return M
