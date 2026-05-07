local fm = require("nvim-vibe.frontmatter")
local id_mod = require("nvim-vibe.id")
local config = require("nvim-vibe.config")

local M = {}

function M.read_node(dir)
  local path = dir .. "/node.md"
  if vim.fn.filereadable(path) == 0 then return nil end
  local content = table.concat(vim.fn.readfile(path), "\n")
  local meta, body = fm.parse(content)
  meta._dir = dir
  meta._file = path
  meta._body = body
  return meta
end

function M.write_node(dir, meta, body)
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

function M.children(dir)
  local children_dir = dir .. "/children"
  if vim.fn.isdirectory(children_dir) == 0 then return {} end

  local entries = vim.fn.readdir(children_dir)
  table.sort(entries)

  local result = {}
  for _, entry in ipairs(entries) do
    local child_dir = children_dir .. "/" .. entry
    if vim.fn.isdirectory(child_dir) == 1 then
      local node = M.read_node(child_dir)
      if node then
        table.insert(result, node)
      end
    end
  end
  return result
end

function M.parent_dir(dir)
  local parent = vim.fn.fnamemodify(dir, ":h")
  if vim.fn.fnamemodify(parent, ":t") == "children" then
    return vim.fn.fnamemodify(parent, ":h")
  end
  return nil
end

function M.root_dir(dir)
  local current = dir
  while true do
    local p = M.parent_dir(current)
    if not p then return current end
    current = p
  end
end

function M.is_leaf(dir)
  local children_dir = dir .. "/children"
  if vim.fn.isdirectory(children_dir) == 0 then return true end
  local entries = vim.fn.readdir(children_dir)
  return #entries == 0
end

function M.walk(dir, fn, depth)
  depth = depth or 0
  local node = M.read_node(dir)
  if not node then return end

  fn(node, depth)

  for _, child in ipairs(M.children(dir)) do
    M.walk(child._dir, fn, depth + 1)
  end
end

function M.add_child(parent_dir, meta, body)
  local children_dir = parent_dir .. "/children"
  vim.fn.mkdir(children_dir, "p")

  local existing = vim.fn.readdir(children_dir)
  local position = #existing

  local task_id = meta.id or id_mod.generate("task")
  meta.id = task_id

  local slug = config.slugify(meta.title or "untitled")
  if slug == "" then slug = "untitled" end

  local dir_name = string.format("%02d-%s", position + 1, slug)
  local child_dir = children_dir .. "/" .. dir_name

  local parent_node = M.read_node(parent_dir)
  if parent_node then
    meta.parent_id = parent_node.id
  end
  meta.position = position

  M.write_node(child_dir, meta, body)
  return child_dir
end

function M.remove_child(child_dir)
  if vim.fn.isdirectory(child_dir) == 1 then
    vim.fn.delete(child_dir, "rf")
  end
end

return M
