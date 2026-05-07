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

function M.start(task_dir, backend_name, opts)
  local b = backends[backend_name or "opencode"]
  if not b then return nil, "unknown backend: " .. (backend_name or "opencode") end
  if not b.start then return nil, "backend does not support start" end
  return b.start(task_dir, opts)
end

function M.stop(task_dir, backend_name)
  local b = backends[backend_name or "opencode"]
  if not b then return nil, "unknown backend: " .. (backend_name or "opencode") end
  if not b.stop then return nil, "backend does not support stop" end
  return b.stop(task_dir)
end

function M.execute(task_dir, backend_name)
  local b = backends[backend_name or "opencode"]
  if not b then return nil, "unknown backend: " .. (backend_name or "opencode") end
  if not b.execute then return nil, "backend does not support execute" end
  return b.execute(task_dir)
end

function M.session(task_dir, backend_name)
  local b = backends[backend_name or "opencode"]
  if not b then return nil end
  if not b.session then return nil end
  return b.session(task_dir)
end

return M
