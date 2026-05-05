local M = {}

function M.prompt(opts, callback)
  opts = opts or {}
  local title = opts.title or "Input"
  local fields = opts.fields or {}

  local results = {}
  local idx = 0

  local function next_field()
    idx = idx + 1
    if idx > #fields then
      callback(results)
      return
    end

    local field = fields[idx]
    local prompt_str = field.prompt or (field.name .. ": ")
    local default = field.default or ""

    vim.ui.input({ prompt = prompt_str, default = default }, function(val)
      if val == nil then
        callback(nil)
        return
      end
      if field.required and val == "" then
        vim.notify("nvim-vibe: " .. field.name .. " is required", vim.log.levels.WARN)
        callback(nil)
        return
      end
      results[field.name] = val
      next_field()
    end)
  end

  vim.notify(title, vim.log.levels.INFO)
  next_field()
end

function M.add_project(callback)
  M.prompt({
    title = "nvim-vibe: Add Project",
    fields = {
      { name = "name", prompt = "Project name: ", required = true },
      { name = "description", prompt = "Description (optional): ", required = false },
    },
  }, function(results)
    if not results then return end
    local core = require("nvim-vibe.core")
    core.add_project(results.name, results.description)
    vim.notify("nvim-vibe: project '" .. results.name .. "' added")
    if callback then callback(results.name) end
  end)
end

function M.add_worktree(project_name, callback)
  if not project_name then
    local state = require("nvim-vibe.core").state()
    local names = vim.tbl_keys(state.projects)
    if #names == 0 then
      vim.notify("nvim-vibe: no projects exist. Add a project first.", vim.log.levels.WARN)
      return
    end
    vim.ui.select(names, { prompt = "Select project:" }, function(selected)
      if not selected then return end
      M._add_worktree_fields(selected, callback)
    end)
  else
    M._add_worktree_fields(project_name, callback)
  end
end

function M._add_worktree_fields(project_name, callback)
  M.prompt({
    title = "nvim-vibe: Add Worktree to '" .. project_name .. "'",
    fields = {
      { name = "name", prompt = "Worktree name (e.g. main, feat/x): ", required = true },
      { name = "path", prompt = "Path: ", default = vim.fn.getcwd(), required = true },
    },
  }, function(results)
    if not results then return end
    local core = require("nvim-vibe.core")
    core.add_worktree(project_name, results.name, results.path)
    vim.notify("nvim-vibe: worktree '" .. results.name .. "' added to " .. project_name)
    if callback then callback(results.name) end
  end)
end

return M
