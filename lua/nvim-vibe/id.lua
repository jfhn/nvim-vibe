local M = {}

function M.generate(prefix)
  prefix = prefix or "task"
  local time = os.time()
  local suffix = string.format("%03x", math.random(0, 4095))
  return prefix .. "_" .. time .. "_" .. suffix
end

return M
