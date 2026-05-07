local t = require("test.harness")
local events = require("nvim-vibe.task_events")
local tree = require("nvim-vibe.task_tree")

local dir = t.tmpdir()

t.suite("task_events.root_dir")

t.test("root task returns itself", function()
  t.eq(events.root_dir("/a/b/tasks/proj/task-1"), "/a/b/tasks/proj/task-1")
end)

t.test("child walks up one level", function()
  t.eq(events.root_dir("/a/b/task-1/children/01-sub"), "/a/b/task-1")
end)

t.test("grandchild walks up two levels", function()
  t.eq(events.root_dir("/a/b/task-1/children/01-sub/children/01-deep"), "/a/b/task-1")
end)

t.suite("task_events.append / read")

t.test("append creates events.jsonl at root", function()
  local root = dir .. "/evt-root"
  tree.write_node(root, { id = "e1", kind = "agent", title = "T" }, "")

  events.append(root, {
    task_id = "e1",
    type = "node_created",
    payload = { kind = "agent" },
  })

  t.is_true(vim.fn.filereadable(root .. "/events.jsonl") == 1)
end)

t.test("read returns appended events", function()
  local root = dir .. "/evt-read"
  tree.write_node(root, { id = "e2", kind = "agent", title = "T" }, "")

  events.append(root, { task_id = "e2", type = "first", payload = {} })
  events.append(root, { task_id = "e2", type = "second", payload = {} })

  local evts = events.read(root)
  t.eq(#evts, 2)
  t.eq(evts[1].type, "first")
  t.eq(evts[2].type, "second")
  t.is_true(evts[1].id ~= nil, "auto-generated id")
  t.is_true(evts[1].time ~= nil, "auto-generated time")
end)

t.test("child event lands in root events.jsonl", function()
  local root = dir .. "/evt-child"
  tree.write_node(root, { id = "ec", kind = "sequence", title = "P" }, "")
  local child = tree.add_child(root, { kind = "agent", title = "C" }, "")

  events.append(child, { task_id = "child_1", type = "child_event", payload = {} })

  local evts = events.read(root)
  local found = false
  for _, e in ipairs(evts) do
    if e.type == "child_event" then found = true end
  end
  t.is_true(found, "child event in root log")
end)

t.test("read empty dir returns empty table", function()
  t.eq(#events.read(dir .. "/nonexistent"), 0)
end)

t.cleanup(dir)

return t.summary()
