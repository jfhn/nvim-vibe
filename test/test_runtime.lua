local t = require("test.harness")
local tree = require("nvim-vibe.task_tree")
local runtime = require("nvim-vibe.task_runtime")

t.suite("runtime.can_transition")

t.test("Planned → Active", function()
  t.is_true(runtime.can_transition("Planned", "Active"))
end)

t.test("Planned → Cancelled", function()
  t.is_true(runtime.can_transition("Planned", "Cancelled"))
end)

t.test("Planned → Done blocked", function()
  t.eq(runtime.can_transition("Planned", "Done"), false)
end)

t.test("Active → Reviewing", function()
  t.is_true(runtime.can_transition("Active", "Reviewing"))
end)

t.test("Active → Done", function()
  t.is_true(runtime.can_transition("Active", "Done"))
end)

t.test("Active → Failed", function()
  t.is_true(runtime.can_transition("Active", "Failed"))
end)

t.test("Reviewing → Active", function()
  t.is_true(runtime.can_transition("Reviewing", "Active"))
end)

t.test("Done is terminal", function()
  t.eq(runtime.can_transition("Done", "Active"), false)
  t.eq(runtime.can_transition("Done", "Planned"), false)
end)

t.test("Failed → Active (retry)", function()
  t.is_true(runtime.can_transition("Failed", "Active"))
end)

t.test("Cancelled is terminal", function()
  t.eq(runtime.can_transition("Cancelled", "Active"), false)
end)

t.suite("runtime._status_from_runtime")

t.test("maps runtime states to derived status", function()
  t.eq(runtime._status_from_runtime("Planned", {}), "planned")
  t.eq(runtime._status_from_runtime("Active", {}), "running")
  t.eq(runtime._status_from_runtime("Reviewing", {}), "waiting_review")
  t.eq(runtime._status_from_runtime("Done", {}), "completed")
  t.eq(runtime._status_from_runtime("Failed", {}), "failed")
  t.eq(runtime._status_from_runtime("Cancelled", {}), "cancelled")
end)

t.test("block_reason overrides to blocked", function()
  t.eq(runtime._status_from_runtime("Active", { block_reason = "question" }), "blocked")
end)

t.suite("runtime.transition")

local dir = t.tmpdir()

t.test("transitions node and writes to disk", function()
  local task_dir = dir .. "/trans-test"
  tree.write_node(task_dir, {
    id = "rt1", kind = "agent", title = "Test",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Test\n")

  local node = runtime.transition(task_dir, "Active")
  t.eq(node.runtime_state, "Active")
  t.eq(node.status, "running")

  local on_disk = tree.read_node(task_dir)
  t.eq(on_disk.runtime_state, "Active")
end)

t.test("rejects invalid transition", function()
  local task_dir = dir .. "/invalid-trans"
  tree.write_node(task_dir, {
    id = "rt2", kind = "agent", title = "Test",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Test\n")

  local node, err = runtime.transition(task_dir, "Done")
  t.eq(node, nil)
  t.is_true(err:find("invalid transition"), "error message")
end)

t.test("retry increments attempt_count", function()
  local task_dir = dir .. "/retry-test"
  tree.write_node(task_dir, {
    id = "rt3", kind = "agent", title = "Test",
    status = "planned", runtime_state = "Planned",
    retry_budget = 2, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Test\n")

  runtime.transition(task_dir, "Active")
  runtime.transition(task_dir, "Failed")
  runtime.transition(task_dir, "Active")

  local node = tree.read_node(task_dir)
  t.eq(node.attempt_count, 1)
end)

t.suite("runtime.derive_status — sequence")

t.test("running when current child running", function()
  local root = dir .. "/seq1"
  tree.write_node(root, {
    id = "s1", kind = "sequence", title = "Seq",
    status = "planned", runtime_state = "Planned",
    index = 0, retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Seq\n")

  tree.add_child(root, {
    kind = "agent", title = "C1",
    status = "running", runtime_state = "Active",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# C1\n")

  t.eq(runtime.derive_status(root), "running")
end)

t.test("completed when all children done and index past end", function()
  local root = dir .. "/seq2"
  tree.write_node(root, {
    id = "s2", kind = "sequence", title = "Seq",
    status = "planned", runtime_state = "Planned",
    index = 1, retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Seq\n")

  tree.add_child(root, {
    kind = "agent", title = "C1",
    status = "completed", runtime_state = "Done",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# C1\n")

  t.eq(runtime.derive_status(root), "completed")
end)

t.test("blocked when current child blocked", function()
  local root = dir .. "/seq3"
  tree.write_node(root, {
    id = "s3", kind = "sequence", title = "Seq",
    status = "planned", runtime_state = "Planned",
    index = 0, retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Seq\n")

  tree.add_child(root, {
    kind = "agent", title = "C1",
    status = "blocked", runtime_state = "Active",
    block_reason = "question",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# C1\n")

  t.eq(runtime.derive_status(root), "blocked")
end)

t.suite("runtime.derive_status — parallel")

t.test("running when any child running", function()
  local root = dir .. "/par1"
  tree.write_node(root, {
    id = "p1", kind = "parallel", title = "Par",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Par\n")

  tree.add_child(root, {
    kind = "agent", title = "A", status = "running",
    runtime_state = "Active", retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# A\n")
  tree.add_child(root, {
    kind = "agent", title = "B", status = "planned",
    runtime_state = "Planned", retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# B\n")

  t.eq(runtime.derive_status(root), "running")
end)

t.test("completed when all children done", function()
  local root = dir .. "/par2"
  tree.write_node(root, {
    id = "p2", kind = "parallel", title = "Par",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Par\n")

  tree.add_child(root, {
    kind = "agent", title = "A", status = "completed",
    runtime_state = "Done", retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# A\n")
  tree.add_child(root, {
    kind = "agent", title = "B", status = "completed",
    runtime_state = "Done", retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# B\n")

  t.eq(runtime.derive_status(root), "completed")
end)

t.test("failed when child failed and none running", function()
  local root = dir .. "/par3"
  tree.write_node(root, {
    id = "p3", kind = "parallel", title = "Par",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Par\n")

  tree.add_child(root, {
    kind = "agent", title = "A", status = "completed",
    runtime_state = "Done", retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# A\n")
  tree.add_child(root, {
    kind = "agent", title = "B", status = "failed",
    runtime_state = "Failed", retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# B\n")

  t.eq(runtime.derive_status(root), "failed")
end)

t.cleanup(dir)

return t.summary()
