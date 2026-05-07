local t = require("test.harness")
local tree = require("nvim-vibe.task_tree")
local events = require("nvim-vibe.task_events")
local backend = require("nvim-vibe.backend")
local planner = require("nvim-vibe.planner")

backend.register("stub", require("nvim-vibe.backend.stub"))

local dir = t.tmpdir()

local function make_task(name)
  local task_dir = dir .. "/" .. name
  tree.write_node(task_dir, {
    id = name, kind = "agent", title = "Task " .. name,
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "# Task " .. name .. "\n")
  return task_dir
end

t.suite("planner.solve")

t.test("transitions to Reviewing", function()
  local task_dir = make_task("solve1")
  local proposal, err = planner.solve(task_dir)
  t.is_true(proposal ~= nil, err)

  local node = tree.read_node(task_dir)
  t.eq(node.runtime_state, "Reviewing")
  t.eq(node.status, "waiting_review")
end)

t.test("creates proposal.json", function()
  local task_dir = make_task("solve2")
  planner.solve(task_dir)
  t.is_true(vim.fn.filereadable(task_dir .. "/proposal.json") == 1)
end)

t.test("writes proposal summary to body", function()
  local task_dir = make_task("solve3")
  planner.solve(task_dir)

  local node = tree.read_node(task_dir)
  t.is_true(node._body:find("Proposal") ~= nil, "body has Proposal")
  t.is_true(node._body:find("gp") ~= nil, "body mentions approve key")
end)

t.test("emits plan_proposed event", function()
  local task_dir = make_task("solve4")
  planner.solve(task_dir)

  local evts = events.read(task_dir)
  local found = false
  for _, e in ipairs(evts) do
    if e.type == "plan_proposed" then found = true end
  end
  t.is_true(found, "plan_proposed event")
end)

t.test("rejects solve on non-Planned task", function()
  local task_dir = make_task("solve5")
  planner.solve(task_dir)
  local _, err = planner.solve(task_dir)
  t.is_true(err:find("must be Planned"), err)
end)

t.suite("planner.approve")

t.test("materializes subtree", function()
  local task_dir = make_task("approve1")
  planner.solve(task_dir)
  local node, err = planner.approve(task_dir)
  t.is_true(node ~= nil, err)

  node = tree.read_node(task_dir)
  t.eq(node.kind, "sequence")
  t.eq(node.runtime_state, "Active")
  t.eq(node.index, 0)
  t.is_table(node.master)
  t.eq(node.master.backend, "stub")

  local children = tree.children(task_dir)
  t.eq(#children, 2)
  t.is_true(children[1].title:find("Plan:") ~= nil, "child 1 title")
  t.is_true(children[2].title:find("Execute:") ~= nil, "child 2 title")
  t.eq(children[1].status, "planned")
  t.eq(children[1].parent_id, "approve1")
end)

t.test("removes proposal.json", function()
  local task_dir = make_task("approve2")
  planner.solve(task_dir)
  planner.approve(task_dir)
  t.eq(vim.fn.filereadable(task_dir .. "/proposal.json"), 0)
end)

t.test("emits plan_approved event", function()
  local task_dir = make_task("approve3")
  planner.solve(task_dir)
  planner.approve(task_dir)

  local evts = events.read(task_dir)
  local found = false
  for _, e in ipairs(evts) do
    if e.type == "plan_approved" then found = true end
  end
  t.is_true(found)
end)

t.test("emits node_created for children", function()
  local task_dir = make_task("approve4")
  planner.solve(task_dir)
  planner.approve(task_dir)

  local evts = events.read(task_dir)
  local count = 0
  for _, e in ipairs(evts) do
    if e.type == "node_created" and e.payload and e.payload.materialized then
      count = count + 1
    end
  end
  t.eq(count, 2)
end)

t.test("rejects approve on non-Reviewing task", function()
  local task_dir = make_task("approve5")
  local _, err = planner.approve(task_dir)
  t.is_true(err:find("not in Reviewing"), err)
end)

t.suite("planner.reject")

t.test("cleans up and cancels", function()
  local task_dir = make_task("reject1")
  planner.solve(task_dir)
  local node, err = planner.reject(task_dir)
  t.is_true(node ~= nil, err)
  t.eq(vim.fn.filereadable(task_dir .. "/proposal.json"), 0)
end)

t.test("emits plan_rejected event", function()
  local task_dir = make_task("reject2")
  planner.solve(task_dir)
  planner.reject(task_dir)

  local evts = events.read(task_dir)
  local found = false
  for _, e in ipairs(evts) do
    if e.type == "plan_rejected" then found = true end
  end
  t.is_true(found)
end)

t.test("rejects reject on non-Reviewing task", function()
  local task_dir = make_task("reject3")
  local _, err = planner.reject(task_dir)
  t.is_true(err:find("not in Reviewing"), err)
end)

t.cleanup(dir)

return t.summary()
