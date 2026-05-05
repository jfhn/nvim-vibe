local M = {}

local hooks = {}

function M.register(event, fn)
  hooks[event] = hooks[event] or {}
  table.insert(hooks[event], fn)
end

function M.fire(event, data)
  for _, fn in ipairs(hooks[event] or {}) do
    local ok, err = pcall(fn, data)
    if not ok then
      vim.notify("nvim-vibe hook error: " .. err, vim.log.levels.WARN)
    end
  end
end

function M.clear(event)
  if event then
    hooks[event] = nil
  else
    hooks = {}
  end
end

return M
