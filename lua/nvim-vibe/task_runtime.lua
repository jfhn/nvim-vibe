local M = {}

local transitions = {
  Planned   = { "Active", "Cancelled" },
  Active    = { "Reviewing", "Done", "Failed", "Cancelled" },
  Reviewing = { "Active", "Done", "Failed", "Cancelled" },
  Done      = {},
  Failed    = { "Active" },
  Cancelled = {},
}

function M.can_transition(from, to)
  local allowed = transitions[from]
  if not allowed then return false end
  for _, s in ipairs(allowed) do
    if s == to then return true end
  end
  return false
end

function M.transition(task_dir, new_state, opts)
  opts = opts or {}
  local tree = require("nvim-vibe.task_tree")
  local events = require("nvim-vibe.task_events")

  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  local old_state = node.runtime_state or "Planned"
  if not M.can_transition(old_state, new_state) then
    return nil, "invalid transition: " .. old_state .. " -> " .. new_state
  end

  node.runtime_state = new_state
  node.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  node.status = M._status_from_runtime(new_state, opts)

  if old_state == "Failed" and new_state == "Active" then
    node.attempt_count = (node.attempt_count or 0) + 1
  end

  if opts.block_reason then
    node.block_reason = opts.block_reason
  elseif node.status ~= "blocked" then
    node.block_reason = vim.NIL
  end

  tree.write_node(task_dir, node, node._body)

  events.append(task_dir, {
    task_id = node.id,
    type = "node_status_changed",
    payload = {
      from = old_state,
      to = new_state,
      status = node.status,
      block_reason = opts.block_reason,
      reason = opts.reason,
    },
  })

  M.recompute_ancestors(task_dir)

  return node
end

function M._status_from_runtime(runtime_state, opts)
  opts = opts or {}
  if opts.block_reason then return "blocked" end
  local map = {
    Planned   = "planned",
    Active    = "running",
    Reviewing = "waiting_review",
    Done      = "completed",
    Failed    = "failed",
    Cancelled = "cancelled",
  }
  return map[runtime_state] or "planned"
end

function M.derive_status(task_dir)
  local tree = require("nvim-vibe.task_tree")
  local node = tree.read_node(task_dir)
  if not node then return nil end

  if tree.is_leaf(task_dir) then
    return node.status or "planned"
  end

  local children = tree.children(task_dir)
  if #children == 0 then
    return node.status or "planned"
  end

  if node.kind == "sequence" then
    return M._derive_sequence(node, children)
  elseif node.kind == "parallel" then
    return M._derive_parallel(node, children)
  end

  return node.status or "planned"
end

function M._derive_sequence(node, children)
  local idx = node.index or 0

  if idx >= #children then
    local all_done = true
    for _, child in ipairs(children) do
      if child.status ~= "completed" then
        all_done = false
        break
      end
    end
    if all_done then return "completed" end
  end

  local current = children[idx + 1]
  if not current then return node.status or "planned" end

  local cs = current.status or "planned"
  if cs == "running" then return "running" end
  if cs == "blocked" then return "blocked" end
  if cs == "waiting_review" then return "waiting_review" end
  if cs == "failed" then return "failed" end
  if cs == "completed" then return "running" end

  return node.status or "planned"
end

function M._derive_parallel(_, children)
  local any_running = false
  local any_blocked = false
  local any_failed = false
  local all_completed = true

  for _, child in ipairs(children) do
    local cs = child.status or "planned"
    if cs == "running" then any_running = true end
    if cs == "blocked" then any_blocked = true end
    if cs == "failed" then any_failed = true end
    if cs ~= "completed" then all_completed = false end
  end

  if all_completed then return "completed" end
  if any_running then return "running" end
  if any_blocked then return "blocked" end
  if any_failed then return "failed" end

  return "planned"
end

function M.recompute(task_dir)
  local tree = require("nvim-vibe.task_tree")
  local status = M.derive_status(task_dir)
  local node = tree.read_node(task_dir)
  if node and node.status ~= status then
    node.status = status
    node.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    tree.write_node(task_dir, node, node._body)
  end
end

function M.recompute_ancestors(task_dir)
  local tree = require("nvim-vibe.task_tree")
  local parent = tree.parent_dir(task_dir)
  while parent do
    M.recompute(parent)
    parent = tree.parent_dir(parent)
  end
end

return M
