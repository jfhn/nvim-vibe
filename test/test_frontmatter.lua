local t = require("test.harness")
local fm = require("nvim-vibe.frontmatter")

t.suite("frontmatter.parse")

t.test("empty content returns empty meta", function()
  local meta, body = fm.parse("no frontmatter here")
  t.eq(next(meta), nil, "meta empty")
  t.eq(body, "no frontmatter here\n", "body is full content with trailing newline")
end)

t.test("basic flat fields", function()
  local content = "---\nid: task_1\ntitle: Hello\nstatus: planned\n---\n\nbody text\n"
  local meta, body = fm.parse(content)
  t.eq(meta.id, "task_1")
  t.eq(meta.title, "Hello")
  t.eq(meta.status, "planned")
  t.eq(body, "body text\n")
end)

t.test("coerce numbers", function()
  local content = "---\nindex: 0\nretry_budget: 3\n---\n\n"
  local meta = fm.parse(content)
  t.eq(meta.index, 0)
  t.eq(meta.retry_budget, 3)
end)

t.test("coerce booleans", function()
  local content = "---\na: true\nb: false\n---\n\n"
  local meta = fm.parse(content)
  t.eq(meta.a, true)
  t.eq(meta.b, false)
end)

t.test("empty value becomes vim.NIL", function()
  local content = "---\nblock_reason:\n---\n\n"
  local meta = fm.parse(content)
  t.eq(meta.block_reason, vim.NIL)
end)

t.test("nested map fields", function()
  local content = "---\nmaster:\n  backend: stub\n  agent: plan\n---\n\nbody\n"
  local meta, body = fm.parse(content)
  t.is_table(meta.master)
  t.eq(meta.master.backend, "stub")
  t.eq(meta.master.agent, "plan")
  t.eq(body, "body\n")
end)

t.test("nested map followed by flat field", function()
  local content = "---\nmaster:\n  backend: opencode\nattempt_count: 2\n---\n\n"
  local meta = fm.parse(content)
  t.is_table(meta.master)
  t.eq(meta.master.backend, "opencode")
  t.eq(meta.attempt_count, 2)
end)

t.test("vim.NIL field before nested map", function()
  local content = "---\nblock_reason:\nmaster:\n  backend: stub\n---\n\n"
  local meta = fm.parse(content)
  t.eq(meta.block_reason, vim.NIL)
  t.is_table(meta.master)
  t.eq(meta.master.backend, "stub")
end)

t.suite("frontmatter.serialize")

t.test("roundtrip flat fields", function()
  local meta = { id = "t1", kind = "agent", title = "Test", status = "planned" }
  local s = fm.serialize(meta, "# Test\n")
  local m, b = fm.parse(s)
  t.eq(m.id, "t1")
  t.eq(m.kind, "agent")
  t.eq(m.title, "Test")
  t.eq(b, "# Test\n")
end)

t.test("roundtrip nested map", function()
  local meta = {
    id = "t1", kind = "sequence", title = "Test",
    status = "running", runtime_state = "Active",
    master = { backend = "stub", agent = "plan" },
    index = 0, retry_budget = 1, attempt_count = 0,
    updated_at = "2026-05-07T00:00:00Z",
  }
  local s = fm.serialize(meta, "# Test\n")
  local m = fm.parse(s)
  t.is_table(m.master)
  t.eq(m.master.backend, "stub")
  t.eq(m.master.agent, "plan")
  t.eq(m.index, 0)
end)

t.test("roundtrip vim.NIL fields", function()
  local meta = { id = "t1", block_reason = vim.NIL, parent_id = vim.NIL }
  local s = fm.serialize(meta, "")
  local m = fm.parse(s)
  t.eq(m.block_reason, vim.NIL)
  t.eq(m.parent_id, vim.NIL)
end)

t.test("key order respected", function()
  local meta = { updated_at = "z", id = "a", title = "b" }
  local s = fm.serialize(meta, "")
  local id_pos = s:find("id:")
  local title_pos = s:find("title:")
  local updated_pos = s:find("updated_at:")
  t.is_true(id_pos < title_pos, "id before title")
  t.is_true(title_pos < updated_pos, "title before updated_at")
end)

return t.summary()
