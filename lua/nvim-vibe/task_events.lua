local id = require("nvim-vibe.id")

local M = {}

function M.root_dir(task_dir)
  local dir = task_dir
  while true do
    local parent = vim.fn.fnamemodify(dir, ":h")
    if vim.fn.fnamemodify(parent, ":t") == "children" then
      dir = vim.fn.fnamemodify(parent, ":h")
    else
      return dir
    end
  end
end

function M.append(task_dir, event)
  local root = M.root_dir(task_dir)
  local path = root .. "/events.jsonl"

  event.id = event.id or id.generate("evt")
  event.time = event.time or os.date("!%Y-%m-%dT%H:%M:%SZ")

  local line = vim.json.encode(event)
  local f = io.open(path, "a")
  if f then
    f:write(line .. "\n")
    f:close()
  end
end

function M.read(root_dir)
  local path = root_dir .. "/events.jsonl"
  if vim.fn.filereadable(path) == 0 then return {} end

  local events = {}
  for line in io.lines(path) do
    if line ~= "" then
      local ok, evt = pcall(vim.json.decode, line)
      if ok then
        table.insert(events, evt)
      end
    end
  end
  return events
end

return M
