local config = require("nvim-vibe.config")
local fm = require("nvim-vibe.frontmatter")
local id = require("nvim-vibe.id")

local M = {}

local data_dir = config.data_dir()

local function tasks_dir(project_name)
  local core = require("nvim-vibe.core")
  local project = core.state().projects[project_name]
  local slug = (project and project.slug) or config.slugify(project_name)
  return data_dir .. "/tasks/" .. slug
end

local function read_node(dir)
  local path = dir .. "/node.md"
  if vim.fn.filereadable(path) == 0 then return nil end
  local content = table.concat(vim.fn.readfile(path), "\n")
  local meta, body = fm.parse(content)
  meta._dir = dir
  meta._file = path
  meta._body = body
  return meta
end

local function write_node(dir, meta, body)
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/node.md"
  local raw_meta = {}
  for k, v in pairs(meta) do
    if k:sub(1, 1) ~= "_" then
      raw_meta[k] = v
    end
  end
  local content = fm.serialize(raw_meta, body)
  vim.fn.writefile(vim.split(content, "\n"), path)
  return path
end

function M.list(project_name)
  local dir = tasks_dir(project_name)
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end

  local entries = vim.fn.readdir(dir)
  local tasks = {}
  for _, entry in ipairs(entries) do
    local task_dir = dir .. "/" .. entry
    if vim.fn.isdirectory(task_dir) == 1 then
      local node = read_node(task_dir)
      if node then
        node.name = node.title or entry
        node.file = node._file
        node.done = node.status == "completed"
        table.insert(tasks, node)
      end
    end
  end
  return tasks
end

function M.add(project_name, name, opts)
  opts = opts or {}
  local dir = tasks_dir(project_name)

  local task_id = id.generate("task")
  local slug = config.slugify(name)
  if slug == "" then slug = "untitled" end
  local task_dir = dir .. "/" .. task_id .. "-" .. slug

  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local meta = {
    id = task_id,
    kind = opts.kind or "agent",
    title = name,
    status = "planned",
    runtime_state = "Planned",
    retry_budget = opts.retry_budget or 1,
    attempt_count = 0,
    updated_at = now,
  }

  local body = opts.body or ("# " .. name .. "\n")
  write_node(task_dir, meta, body)
  return task_dir
end

function M.toggle(filepath)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  local node = read_node(dir)
  if not node then return end

  if node.status == "completed" then
    node.status = "planned"
    node.runtime_state = "Planned"
  else
    node.status = "completed"
    node.runtime_state = "Done"
  end
  node.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

  write_node(dir, node, node._body)
  return node.status == "completed"
end

function M.remove(filepath)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  if vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, "rf")
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

  local task_id = id.generate("task")
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")

  local template = fm.serialize({
    id = task_id,
    kind = "agent",
    title = "",
    status = "planned",
    runtime_state = "Planned",
    retry_budget = 1,
    attempt_count = 0,
    updated_at = now,
  }, "# \n")

  local placeholder = dir .. "/new-task/node.md"
  vim.fn.mkdir(dir .. "/new-task", "p")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, placeholder)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(template, "\n"))
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "markdown"

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^# $") then
      vim.api.nvim_win_set_cursor(0, { i, 2 })
      break
    end
  end
  vim.cmd("startinsert!")

  local saved = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(buf_lines, "\n")
      local meta, body = fm.parse(content)

      if not saved then
        local title = meta.title
        if (not title or title == "") and body then
          local heading = body:match("^#%s+(.+)")
          if heading then
            title = heading
          end
        end
        title = title or "untitled"

        -- update title in frontmatter
        meta.title = title
        meta.id = meta.id or task_id

        local slug = config.slugify(title)
        if slug == "" then slug = "untitled" end
        local task_dir = dir .. "/" .. meta.id .. "-" .. slug

        vim.fn.mkdir(task_dir, "p")
        local filepath = task_dir .. "/node.md"

        local raw_meta = {}
        for k, v in pairs(meta) do
          if k:sub(1, 1) ~= "_" then
            raw_meta[k] = v
          end
        end

        vim.fn.writefile(vim.split(fm.serialize(raw_meta, body), "\n"), filepath)
        vim.bo[buf].modified = false

        -- clean up placeholder dir
        local old_dir = dir .. "/new-task"
        if vim.fn.isdirectory(old_dir) == 1 then
          vim.fn.delete(old_dir, "rf")
        end

        vim.api.nvim_buf_set_name(buf, filepath)
        saved = true
      else
        vim.fn.writefile(buf_lines, vim.api.nvim_buf_get_name(buf))
        vim.bo[buf].modified = false
      end
    end,
  })
end

function M.read_node(dir)
  return read_node(dir)
end

function M.write_node(dir, meta, body)
  return write_node(dir, meta, body)
end

return M
