local config = require("nvim-vibe.config")

local M = {}

local data_dir = config.data_dir()

local function tasks_dir(project_name)
  local core = require("nvim-vibe.core")
  local project = core.state().projects[project_name]
  local slug = (project and project.slug) or config.slugify(project_name)
  return data_dir .. "/tasks/" .. slug
end

local function parse_frontmatter(content)
  local meta = { done = false, tags = {} }
  local body_start = 1

  if content:sub(1, 4) == "---\n" then
    local end_pos = content:find("\n---\n", 5)
    if end_pos then
      local fm = content:sub(5, end_pos - 1)
      for line in fm:gmatch("[^\n]+") do
        local key, val = line:match("^(%w+):%s*(.+)$")
        if key == "done" then
          meta.done = val == "true"
        elseif key == "tags" then
          meta.tags = {}
          for tag in val:gmatch("[%w_-]+") do
            table.insert(meta.tags, tag)
          end
        end
      end
      body_start = end_pos + 5
    end
  end

  meta.body = content:sub(body_start):gsub("^%s+", ""):gsub("%s+$", "")
  return meta
end

local function serialize_task(meta)
  local lines = { "---" }
  table.insert(lines, "done: " .. (meta.done and "true" or "false"))
  if meta.tags and #meta.tags > 0 then
    table.insert(lines, "tags: [" .. table.concat(meta.tags, ", ") .. "]")
  end
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, meta.body or "")
  return table.concat(lines, "\n")
end

function M.list(project_name)
  local dir = tasks_dir(project_name)
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end

  local files = vim.fn.glob(dir .. "/*.md", false, true)
  local tasks = {}
  for _, filepath in ipairs(files) do
    local content = table.concat(vim.fn.readfile(filepath), "\n")
    local meta = parse_frontmatter(content)
    meta.file = filepath
    meta.name = vim.fn.fnamemodify(filepath, ":t:r")
    table.insert(tasks, meta)
  end
  return tasks
end

function M.add(project_name, name, opts)
  opts = opts or {}
  local dir = tasks_dir(project_name)
  vim.fn.mkdir(dir, "p")

  local filename = name:gsub("[^%w_-]", "-"):gsub("-+", "-")
  local filepath = dir .. "/" .. filename .. ".md"

  local meta = {
    done = false,
    tags = opts.tags or {},
    body = opts.body or name,
  }

  vim.fn.writefile(vim.split(serialize_task(meta), "\n"), filepath)
  return filepath
end

function M.toggle(filepath)
  if vim.fn.filereadable(filepath) == 0 then return end
  local content = table.concat(vim.fn.readfile(filepath), "\n")
  local meta = parse_frontmatter(content)
  meta.done = not meta.done
  vim.fn.writefile(vim.split(serialize_task(meta), "\n"), filepath)
  return meta.done
end

function M.remove(filepath)
  if vim.fn.filereadable(filepath) == 1 then
    vim.fn.delete(filepath)
  end
end

function M.create(project_name)
  if not project_name then
    local core = require("nvim-vibe.core")
    project_name = core.state().current_project
  end
  if not project_name then
    vim.notify("nvim-vibe: no active project", vim.log.levels.WARN)
    return
  end

  local dir = tasks_dir(project_name)
  vim.fn.mkdir(dir, "p")

  local template = {
    "---",
    "done: false",
    "tags: []",
    "---",
    "",
    "",
  }

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, template)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "markdown"

  -- cursor on last line for writing body
  vim.api.nvim_win_set_cursor(0, { 6, 0 })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    once = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(lines, "\n")
      local meta = parse_frontmatter(content)

      local name = meta.body:match("^([^\n]+)") or "untitled"
      local filename = name:gsub("[^%w_-]", "-"):gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")
      if filename == "" then filename = "untitled" end
      local filepath = dir .. "/" .. filename .. ".md"

      -- avoid overwrite
      local n = 1
      while vim.fn.filereadable(filepath) == 1 do
        filepath = dir .. "/" .. filename .. "-" .. n .. ".md"
        n = n + 1
      end

      vim.fn.writefile(lines, filepath)
      vim.bo[buf].modified = false
      vim.api.nvim_buf_set_name(buf, filepath)
      vim.notify("nvim-vibe: task saved → " .. filepath)
    end,
  })
end

return M
