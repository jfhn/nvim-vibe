local M = {}

local backends = {}

function M.register(name, impl)
  backends[name] = impl
end

function M.get(name)
  return backends[name]
end

function M.solve(task_dir, backend_name)
  local b = backends[backend_name or "stub"]
  if not b then return nil, "unknown backend: " .. (backend_name or "stub") end
  if not b.solve then return nil, "backend does not support solve" end
  return b.solve(task_dir)
end

return M
