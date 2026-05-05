local M = {}

local data_dir = vim.fn.expand("~/.local/nvim-vibe")
local projects_file = data_dir .. "/projects.lua"

function M.load()
  if vim.fn.filereadable(projects_file) == 0 then
    return {}
  end
  local ok, result = pcall(dofile, projects_file)
  if not ok then
    vim.notify("nvim-vibe: failed to load projects.lua: " .. result, vim.log.levels.ERROR)
    return {}
  end
  return result or {}
end

function M.save(projects)
  vim.fn.mkdir(data_dir, "p")
  local lines = { "return {" }
  for name, project in pairs(projects) do
    table.insert(lines, string.format('  [%q] = {', name))
    table.insert(lines, string.format('    description = %q,', project.description or ""))
    table.insert(lines, "    worktrees = {")
    for wt_name, wt_path in pairs(project.worktrees or {}) do
      table.insert(lines, string.format('      [%q] = %q,', wt_name, wt_path))
    end
    table.insert(lines, "    },")
    table.insert(lines, "  },")
  end
  table.insert(lines, "}")
  vim.fn.writefile(lines, projects_file)
end

function M.data_dir()
  return data_dir
end

return M
