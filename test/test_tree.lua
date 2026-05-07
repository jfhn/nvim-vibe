local t = require("test.harness")
local tree = require("nvim-vibe.task_tree")

local dir = t.tmpdir()

t.suite("task_tree.read_node / write_node")

t.test("write and read back", function()
  local task_dir = dir .. "/rw-test"
  tree.write_node(task_dir, {
    id = "t1", kind = "agent", title = "Hello",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Hello\n")

  local node = tree.read_node(task_dir)
  t.eq(node.id, "t1")
  t.eq(node.title, "Hello")
  t.eq(node._dir, task_dir)
  t.eq(node._file, task_dir .. "/node.md")
  t.eq(node._body, "# Hello\n")
end)

t.test("read nonexistent returns nil", function()
  t.eq(tree.read_node(dir .. "/nope"), nil)
end)

t.suite("task_tree.children / add_child")

t.test("no children dir returns empty", function()
  local task_dir = dir .. "/no-kids"
  tree.write_node(task_dir, { id = "nk", kind = "agent", title = "X" }, "")
  t.eq(#tree.children(task_dir), 0)
end)

t.test("add_child creates children dir and node", function()
  local parent = dir .. "/parent"
  tree.write_node(parent, {
    id = "p1", kind = "sequence", title = "Parent",
    status = "planned", runtime_state = "Planned",
  }, "# Parent\n")

  local c1 = tree.add_child(parent, {
    kind = "agent", title = "Child one",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = "2026-01-01T00:00:00Z",
  }, "# Child one\n")

  t.is_true(vim.fn.isdirectory(c1) == 1, "child dir exists")
  local children = tree.children(parent)
  t.eq(#children, 1)
  t.eq(children[1].title, "Child one")
  t.eq(children[1].parent_id, "p1")
  t.eq(children[1].position, 0)
end)

t.test("multiple children sorted by position", function()
  local parent = dir .. "/multi-parent"
  tree.write_node(parent, {
    id = "mp", kind = "sequence", title = "Multi",
  }, "")

  tree.add_child(parent, { kind = "agent", title = "First" }, "")
  tree.add_child(parent, { kind = "agent", title = "Second" }, "")
  tree.add_child(parent, { kind = "agent", title = "Third" }, "")

  local children = tree.children(parent)
  t.eq(#children, 3)
  t.eq(children[1].title, "First")
  t.eq(children[2].title, "Second")
  t.eq(children[3].title, "Third")
end)

t.suite("task_tree.parent_dir / root_dir")

t.test("root node has no parent", function()
  local root = dir .. "/root-nav"
  tree.write_node(root, { id = "rn", kind = "agent", title = "Root" }, "")
  t.eq(tree.parent_dir(root), nil)
end)

t.test("child parent points to parent", function()
  local parent = dir .. "/nav-parent"
  tree.write_node(parent, { id = "np", kind = "sequence", title = "P" }, "")
  local child = tree.add_child(parent, { kind = "agent", title = "C" }, "")
  t.eq(tree.parent_dir(child), parent)
end)

t.test("root_dir walks up to root", function()
  local root = dir .. "/deep-root"
  tree.write_node(root, { id = "dr", kind = "sequence", title = "R" }, "")
  local mid = tree.add_child(root, { kind = "sequence", title = "Mid" }, "")
  local leaf = tree.add_child(mid, { kind = "agent", title = "Leaf" }, "")
  t.eq(tree.root_dir(leaf), root)
  t.eq(tree.root_dir(mid), root)
  t.eq(tree.root_dir(root), root)
end)

t.suite("task_tree.is_leaf")

t.test("node without children is leaf", function()
  local task_dir = dir .. "/leaf-test"
  tree.write_node(task_dir, { id = "lt", kind = "agent", title = "Leaf" }, "")
  t.is_true(tree.is_leaf(task_dir))
end)

t.test("node with children is not leaf", function()
  local parent = dir .. "/nonleaf-test"
  tree.write_node(parent, { id = "nl", kind = "sequence", title = "P" }, "")
  tree.add_child(parent, { kind = "agent", title = "C" }, "")
  t.eq(tree.is_leaf(parent), false)
end)

t.suite("task_tree.walk")

t.test("visits all nodes depth-first", function()
  local root = dir .. "/walk-test"
  tree.write_node(root, { id = "w1", kind = "sequence", title = "Root" }, "")
  tree.add_child(root, { kind = "agent", title = "A" }, "")
  local mid = tree.add_child(root, { kind = "sequence", title = "B" }, "")
  tree.add_child(mid, { kind = "agent", title = "B1" }, "")

  local visited = {}
  tree.walk(root, function(node, depth)
    table.insert(visited, { title = node.title, depth = depth })
  end)

  t.eq(#visited, 4)
  t.eq(visited[1].title, "Root")
  t.eq(visited[1].depth, 0)
  t.eq(visited[2].title, "A")
  t.eq(visited[2].depth, 1)
  t.eq(visited[3].title, "B")
  t.eq(visited[3].depth, 1)
  t.eq(visited[4].title, "B1")
  t.eq(visited[4].depth, 2)
end)

t.suite("task_tree.remove_child")

t.test("removes child directory", function()
  local parent = dir .. "/rm-parent"
  tree.write_node(parent, { id = "rp", kind = "sequence", title = "P" }, "")
  local child = tree.add_child(parent, { kind = "agent", title = "Gone" }, "")
  t.is_true(vim.fn.isdirectory(child) == 1, "exists before")
  tree.remove_child(child)
  t.eq(vim.fn.isdirectory(child), 0, "gone after")
end)

t.cleanup(dir)

return t.summary()
