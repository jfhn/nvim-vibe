local tree = require("nvim-vibe.task_tree")
local runtime = require("nvim-vibe.task_runtime")
local events = require("nvim-vibe.task_events")
local backend = require("nvim-vibe.backend")
local id_mod = require("nvim-vibe.id")

local M = {}

function M.solve(task_dir, backend_name)
  backend_name = backend_name or "stub"
  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  local state = node.runtime_state or "Planned"
  if state ~= "Planned" and state ~= "Failed" then
    return nil, "task must be Planned or Failed to solve, got: " .. state
  end

  if state == "Failed" then
    runtime.transition(task_dir, "Active", { reason = "solve retry" })
  else
    runtime.transition(task_dir, "Active", { reason = "planner starting" })
  end

  local proposal, err = backend.solve(task_dir, backend_name)
  if not proposal then
    runtime.transition(task_dir, "Failed", { reason = "planner failed: " .. (err or "unknown") })
    return nil, err
  end

  local proposal_path = task_dir .. "/proposal.json"
  local f = io.open(proposal_path, "w")
  if f then
    f:write(vim.json.encode(proposal))
    f:close()
  end

  node = tree.read_node(task_dir)
  local body = M._proposal_to_markdown(proposal)
  tree.write_node(task_dir, node, body)

  runtime.transition(task_dir, "Reviewing", { reason = "plan proposed" })

  events.append(task_dir, {
    task_id = node.id,
    type = "plan_proposed",
    payload = { backend = backend_name, summary = proposal.summary },
  })

  vim.notify("nvim-vibe: plan proposed — review with gp (approve) / gr (reject)", vim.log.levels.INFO)
  return proposal
end

function M.approve(task_dir)
  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  if (node.runtime_state or "Planned") ~= "Reviewing" then
    return nil, "task not in Reviewing state"
  end

  local proposal_path = task_dir .. "/proposal.json"
  if vim.fn.filereadable(proposal_path) == 0 then
    return nil, "no proposal found"
  end

  local raw = table.concat(vim.fn.readfile(proposal_path), "\n")
  local ok, proposal = pcall(vim.json.decode, raw)
  if not ok then return nil, "invalid proposal JSON" end

  local root_spec = proposal.root
  if not root_spec then return nil, "proposal missing root" end

  node.kind = root_spec.kind or node.kind
  node.on_error = root_spec.on_error
  node.retry_budget = root_spec.retry_budget or node.retry_budget
  node.master = root_spec.master
  if root_spec.kind == "sequence" then
    node.index = 0
  end

  tree.write_node(task_dir, node, node._body)

  if root_spec.tasks then
    M._materialize_children(task_dir, root_spec.tasks)
  end

  runtime.transition(task_dir, "Active", { reason = "plan approved" })

  events.append(task_dir, {
    task_id = node.id,
    type = "plan_approved",
    payload = { children_count = root_spec.tasks and #root_spec.tasks or 0 },
  })

  vim.fn.delete(proposal_path)

  vim.notify("nvim-vibe: plan approved, subtree materialized", vim.log.levels.INFO)
  return node
end

function M.reject(task_dir)
  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  if (node.runtime_state or "Planned") ~= "Reviewing" then
    return nil, "task not in Reviewing state"
  end

  runtime.transition(task_dir, "Active", { reason = "plan rejected, returning to active" })
  runtime.transition(task_dir, "Failed", { reason = "plan rejected by user" })
  runtime.transition(task_dir, "Active", { reason = "re-solve available" })

  events.append(task_dir, {
    task_id = node.id,
    type = "plan_rejected",
    payload = {},
  })

  local proposal_path = task_dir .. "/proposal.json"
  if vim.fn.filereadable(proposal_path) == 1 then
    vim.fn.delete(proposal_path)
  end

  node = tree.read_node(task_dir)
  node.kind = "agent"
  node.master = vim.NIL
  node.index = vim.NIL
  node.on_error = vim.NIL
  tree.write_node(task_dir, node, "# " .. (node.title or "untitled") .. "\n")

  runtime.transition(task_dir, "Failed", { reason = "plan rejected" })
  runtime.transition(task_dir, "Active")
  runtime.transition(task_dir, "Cancelled", { reason = "rejected, re-create to retry" })

  vim.notify("nvim-vibe: plan rejected", vim.log.levels.WARN)
  return node
end

function M._materialize_children(parent_dir, task_specs)
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")

  for _, spec in ipairs(task_specs) do
    local meta = {
      id = id_mod.generate("task"),
      kind = spec.kind or "agent",
      title = spec.title or "untitled",
      status = "planned",
      runtime_state = "Planned",
      retry_budget = spec.retry_budget or 1,
      attempt_count = 0,
      updated_at = now,
    }

    if spec.agent then
      meta.agent = spec.agent
    end
    if spec.master then
      meta.master = spec.master
    end
    if spec.on_error then
      meta.on_error = spec.on_error
    end
    if spec.kind == "sequence" then
      meta.index = 0
    end

    local body = "# " .. meta.title .. "\n"
    local child_dir = tree.add_child(parent_dir, meta, body)

    events.append(child_dir, {
      task_id = meta.id,
      type = "node_created",
      payload = { kind = meta.kind, title = meta.title, materialized = true },
    })

    if spec.tasks then
      M._materialize_children(child_dir, spec.tasks)
    end
  end
end

function M._proposal_to_markdown(proposal)
  local lines = { "# " .. (proposal.title or "Plan") }
  table.insert(lines, "")
  table.insert(lines, "## Proposal")
  table.insert(lines, "")
  table.insert(lines, proposal.summary or "")
  table.insert(lines, "")

  if proposal.root and proposal.root.tasks then
    table.insert(lines, "### Steps")
    table.insert(lines, "")
    M._render_proposal_tree(proposal.root.tasks, lines, 0)
  end

  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "*Approve with `gp` or reject with `gr` in sidebar.*")
  return table.concat(lines, "\n")
end

function M._render_proposal_tree(tasks, lines, depth)
  local indent = string.rep("  ", depth)
  for i, spec in ipairs(tasks) do
    local km = ({ agent = "A", sequence = "S", parallel = "P" })[spec.kind] or "?"
    table.insert(lines, indent .. i .. ". **[" .. km .. "]** " .. (spec.title or "untitled"))
    if spec.tasks then
      M._render_proposal_tree(spec.tasks, lines, depth + 1)
    end
  end
end

return M
