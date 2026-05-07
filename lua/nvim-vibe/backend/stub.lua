local tree = require("nvim-vibe.task_tree")

local M = {}

function M.solve(task_dir)
  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  return {
    title = node.title,
    summary = "Stub planner: split into plan + execute steps.",
    root = {
      kind = "sequence",
      title = node.title,
      on_error = "fail_fast",
      retry_budget = 1,
      master = { backend = "stub", agent = "plan" },
      tasks = {
        {
          kind = "agent",
          title = "Plan: " .. (node.title or "untitled"),
          retry_budget = 1,
          agent = { backend = "stub", role = "planner" },
        },
        {
          kind = "agent",
          title = "Execute: " .. (node.title or "untitled"),
          retry_budget = 1,
          agent = { backend = "stub", role = "coder" },
        },
      },
    },
  }
end

return M
