local M = {}

function M.projects(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local core = require("nvim-vibe.core")
  local state = core.state()

  opts = opts or {}

  local entries = {}
  for pname, project in pairs(state.projects) do
    table.insert(entries, {
      display = pname,
      project = pname,
      worktree = nil,
      path = project.path,
      ordinal = pname,
    })
    for wname, wpath in pairs(project.worktrees or {}) do
      table.insert(entries, {
        display = pname .. " / " .. wname,
        project = pname,
        worktree = wname,
        path = wpath,
        ordinal = pname .. " " .. wname,
      })
    end
  end

  pickers.new(opts, {
    prompt_title = "nvim-vibe",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          core.switch(selection.value.project, selection.value.worktree)
        end
      end)
      return true
    end,
  }):find()
end

return M
