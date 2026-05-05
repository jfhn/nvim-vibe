local config = require("nvim-vibe.config")
local hooks = require("nvim-vibe.hooks")

local M = {}

local state = {
  projects = {},
  current_project = nil,
  current_worktree = nil,
}

function M.state()
  return state
end

function M.reload()
  state.projects = config.load()
end

function M.switch(project_name, worktree_name)
  local project = state.projects[project_name]
  if not project then
    vim.notify("nvim-vibe: unknown project: " .. project_name, vim.log.levels.ERROR)
    return false
  end

  local wt_path = project.worktrees[worktree_name]
  if not wt_path then
    vim.notify("nvim-vibe: unknown worktree: " .. worktree_name, vim.log.levels.ERROR)
    return false
  end

  wt_path = vim.fn.expand(wt_path)
  if vim.fn.isdirectory(wt_path) == 0 then
    vim.notify("nvim-vibe: path not found: " .. wt_path, vim.log.levels.ERROR)
    return false
  end

  local old_cwd = vim.fn.getcwd()

  -- wipe bufs from old worktree
  if state.current_project then
    M._wipe_worktree_bufs(old_cwd)
  end

  vim.cmd("cd " .. vim.fn.fnameescape(wt_path))
  state.current_project = project_name
  state.current_worktree = worktree_name

  hooks.fire("on_switch", {
    project = project_name,
    worktree = worktree_name,
    path = wt_path,
    old_cwd = old_cwd,
  })

  vim.notify(string.format("nvim-vibe: %s → %s", project_name, worktree_name))
  return true
end

function M._wipe_worktree_bufs(dir)
  dir = vim.fn.resolve(dir)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.startswith(vim.fn.resolve(name), dir) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end
end

function M.add_project(name, description)
  state.projects[name] = {
    description = description or "",
    worktrees = {},
  }
  config.save(state.projects)
end

function M.remove_project(name)
  state.projects[name] = nil
  config.save(state.projects)
  if state.current_project == name then
    state.current_project = nil
    state.current_worktree = nil
  end
end

function M.add_worktree(project_name, wt_name, wt_path)
  local project = state.projects[project_name]
  if not project then
    vim.notify("nvim-vibe: unknown project: " .. project_name, vim.log.levels.ERROR)
    return false
  end
  project.worktrees[wt_name] = vim.fn.fnamemodify(wt_path, ":p"):gsub("/$", "")
  config.save(state.projects)
  return true
end

function M.remove_worktree(project_name, wt_name)
  local project = state.projects[project_name]
  if not project then return false end
  project.worktrees[wt_name] = nil
  config.save(state.projects)
  return true
end

function M.detect()
  local cwd = vim.fn.getcwd()
  for pname, project in pairs(state.projects) do
    for wname, wpath in pairs(project.worktrees or {}) do
      if vim.fn.resolve(vim.fn.expand(wpath)) == vim.fn.resolve(cwd) then
        state.current_project = pname
        state.current_worktree = wname
        return pname, wname
      end
    end
  end
  return nil, nil
end

return M
