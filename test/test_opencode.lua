local t = require("test.harness")
local oc = require("nvim-vibe.backend.opencode")
local tree = require("nvim-vibe.task_tree")
local runtime = require("nvim-vibe.task_runtime")
local events = require("nvim-vibe.task_events")

t.suite("opencode._parse_events")

t.test("parses JSON lines", function()
  local output = '{"type":"step_start","sessionID":"ses_1"}\n'
    .. '{"type":"text","part":{"text":"hello"}}\n'
    .. '{"type":"step_finish","part":{"reason":"stop"}}\n'
  local evts = oc._parse_events(output)
  t.eq(#evts, 3)
  t.eq(evts[1].type, "step_start")
  t.eq(evts[2].type, "text")
  t.eq(evts[3].type, "step_finish")
end)

t.test("skips non-JSON lines", function()
  local output = 'not json\n{"type":"text"}\ngarbage\n'
  local evts = oc._parse_events(output)
  t.eq(#evts, 1)
  t.eq(evts[1].type, "text")
end)

t.test("empty input returns empty", function()
  t.eq(#oc._parse_events(""), 0)
end)

t.suite("opencode._extract_text")

t.test("concatenates text parts", function()
  local evts = {
    { type = "step_start" },
    { type = "text", part = { text = "hello " } },
    { type = "text", part = { text = "world" } },
    { type = "step_finish" },
  }
  t.eq(oc._extract_text(evts), "hello world")
end)

t.test("returns empty for no text events", function()
  local evts = { { type = "step_start" }, { type = "step_finish" } }
  t.eq(oc._extract_text(evts), "")
end)

t.test("handles missing part gracefully", function()
  local evts = { { type = "text" }, { type = "text", part = {} } }
  t.eq(oc._extract_text(evts), "")
end)

t.suite("opencode._extract_session_id")

t.test("finds session ID from events", function()
  local evts = {
    { type = "step_start", sessionID = "ses_abc123" },
    { type = "text" },
  }
  t.eq(oc._extract_session_id(evts), "ses_abc123")
end)

t.test("returns nil when no session ID", function()
  local evts = { { type = "text" } }
  t.eq(oc._extract_session_id(evts), nil)
end)

t.suite("opencode._extract_proposal")

t.test("extracts from json code block", function()
  local text = "Here is the plan:\n```json\n"
    .. '{"title":"test","summary":"s","root":{"kind":"sequence","tasks":[]}}'
    .. "\n```\nDone."
  local proposal, err = oc._extract_proposal(text)
  t.is_true(proposal ~= nil, err)
  t.eq(proposal.title, "test")
  t.eq(proposal.root.kind, "sequence")
end)

t.test("extracts from bare code block", function()
  local text = "```\n"
    .. '{"title":"t","summary":"s","root":{"kind":"agent","tasks":[]}}'
    .. "\n```"
  local proposal, err = oc._extract_proposal(text)
  t.is_true(proposal ~= nil, err)
  t.eq(proposal.title, "t")
end)

t.test("extracts bare JSON object", function()
  local text = '{"title":"t","summary":"s","root":{"kind":"agent","tasks":[]}}'
  local proposal, err = oc._extract_proposal(text)
  t.is_true(proposal ~= nil, err)
  t.eq(proposal.title, "t")
end)

t.test("handles multiline JSON in code block", function()
  local text = "```json\n{\n"
    .. '  "title": "multi",\n'
    .. '  "summary": "line",\n'
    .. '  "root": {"kind": "sequence", "tasks": []}\n'
    .. "}\n```"
  local proposal, err = oc._extract_proposal(text)
  t.is_true(proposal ~= nil, err)
  t.eq(proposal.title, "multi")
end)

t.test("rejects missing root", function()
  local text = '{"title":"test","summary":"s"}'
  local _, err = oc._extract_proposal(text)
  t.is_true(err:find("missing root") ~= nil, err)
end)

t.test("rejects no JSON", function()
  local text = "just some text without any JSON"
  local _, err = oc._extract_proposal(text)
  t.is_true(err:find("no JSON") ~= nil, err)
end)

t.test("rejects invalid JSON", function()
  local text = '{"broken json'
  local _, err = oc._extract_proposal(text)
  t.is_true(err ~= nil)
end)

t.suite("opencode._build_plan_prompt")

t.test("includes title", function()
  local prompt = oc._build_plan_prompt({ title = "Fix sidebar bug", _body = "" })
  t.is_true(prompt:find("Fix sidebar bug") ~= nil)
end)

t.test("includes body when present", function()
  local prompt = oc._build_plan_prompt({ title = "Task", _body = "Detailed description here" })
  t.is_true(prompt:find("Detailed description here") ~= nil)
end)

t.test("includes JSON format instructions", function()
  local prompt = oc._build_plan_prompt({ title = "T", _body = "" })
  t.is_true(prompt:find("```json") ~= nil)
  t.is_true(prompt:find('"root"') ~= nil)
end)

t.suite("opencode._build_exec_prompt")

t.test("includes title", function()
  local prompt = oc._build_exec_prompt({ title = "Run tests", _body = "" })
  t.is_true(prompt:find("Run tests") ~= nil)
end)

t.test("includes body", function()
  local prompt = oc._build_exec_prompt({ title = "T", _body = "All unit tests" })
  t.is_true(prompt:find("All unit tests") ~= nil)
end)

t.suite("opencode._handle_event")

t.test("step_start sets session_id and status", function()
  local session = { text = "", status = "starting" }
  oc._handle_event("/tmp/test", session, {
    type = "step_start",
    sessionID = "ses_xyz",
  })
  t.eq(session.session_id, "ses_xyz")
  t.eq(session.status, "running")
end)

t.test("text accumulates", function()
  local session = { text = "", status = "running" }
  oc._handle_event("/tmp/test", session, {
    type = "text",
    part = { text = "hello " },
  })
  oc._handle_event("/tmp/test", session, {
    type = "text",
    part = { text = "world" },
  })
  t.eq(session.text, "hello world")
end)

t.test("step_finish records tokens and cost", function()
  local session = { text = "", status = "running" }
  oc._handle_event("/tmp/test", session, {
    type = "step_finish",
    part = {
      tokens = { total = 100, input = 80, output = 20 },
      cost = 0.001,
    },
  })
  t.eq(session.status, "step_done")
  t.eq(session.tokens.total, 100)
  t.eq(session.cost, 0.001)
end)

t.test("ignores unknown event types", function()
  local session = { text = "", status = "running" }
  oc._handle_event("/tmp/test", session, { type = "unknown_event" })
  t.eq(session.status, "running")
end)

t.suite("opencode._handle_exit")

local dir = t.tmpdir()

t.test("exit 0 transitions to Done", function()
  local task_dir = dir .. "/exit-ok"
  tree.write_node(task_dir, {
    id = "e1", kind = "agent", title = "OK task",
    status = "running", runtime_state = "Active",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "# OK\n")

  local session = { task_dir = task_dir, node_id = "e1", text = "done", session_id = "ses_1" }
  oc._handle_exit(task_dir, session, 0)

  local node = tree.read_node(task_dir)
  t.eq(node.runtime_state, "Done")
  t.eq(node.status, "completed")
end)

t.test("exit non-zero transitions to Failed", function()
  local task_dir = dir .. "/exit-fail"
  tree.write_node(task_dir, {
    id = "e2", kind = "agent", title = "Fail task",
    status = "running", runtime_state = "Active",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "# Fail\n")

  local session = { task_dir = task_dir, node_id = "e2", text = "", session_id = "ses_2" }
  oc._handle_exit(task_dir, session, 1)

  local node = tree.read_node(task_dir)
  t.eq(node.runtime_state, "Failed")
  t.eq(node.status, "failed")
end)

t.test("emits node_completed event on success", function()
  local task_dir = dir .. "/exit-evt-ok"
  tree.write_node(task_dir, {
    id = "e3", kind = "agent", title = "T",
    status = "running", runtime_state = "Active",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  oc._handle_exit(task_dir, { task_dir = task_dir, node_id = "e3", text = "x", session_id = "s" }, 0)

  local evts = events.read(task_dir)
  local found = false
  for _, e in ipairs(evts) do
    if e.type == "node_completed" then found = true end
  end
  t.is_true(found, "node_completed event")
end)

t.test("emits node_failed event on failure", function()
  local task_dir = dir .. "/exit-evt-fail"
  tree.write_node(task_dir, {
    id = "e4", kind = "agent", title = "T",
    status = "running", runtime_state = "Active",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  oc._handle_exit(task_dir, { task_dir = task_dir, node_id = "e4", text = "", session_id = "s" }, 1)

  local evts = events.read(task_dir)
  local found = false
  for _, e in ipairs(evts) do
    if e.type == "node_failed" then found = true end
  end
  t.is_true(found, "node_failed event")
end)

t.test("skips transition if not Active", function()
  local task_dir = dir .. "/exit-skip"
  tree.write_node(task_dir, {
    id = "e5", kind = "agent", title = "T",
    status = "completed", runtime_state = "Done",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  oc._handle_exit(task_dir, { task_dir = task_dir, node_id = "e5", text = "", session_id = "s" }, 0)

  local node = tree.read_node(task_dir)
  t.eq(node.runtime_state, "Done")
end)

t.suite("opencode._try_advance_parent")

t.test("advances sequence index on child completion", function()
  local parent = dir .. "/seq-advance"
  tree.write_node(parent, {
    id = "sa1", kind = "sequence", title = "Seq",
    status = "running", runtime_state = "Active",
    index = 0, retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  local c1 = tree.add_child(parent, {
    kind = "agent", title = "Step 1",
    status = "completed", runtime_state = "Done",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  tree.add_child(parent, {
    kind = "agent", title = "Step 2",
    status = "planned", runtime_state = "Planned",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  oc._try_advance_parent(c1)

  local node = tree.read_node(parent)
  t.eq(node.index, 1)
end)

t.test("completes sequence when all children done", function()
  local parent = dir .. "/seq-complete"
  tree.write_node(parent, {
    id = "sc1", kind = "sequence", title = "Seq",
    status = "running", runtime_state = "Active",
    index = 0, retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  local c1 = tree.add_child(parent, {
    kind = "agent", title = "Only step",
    status = "completed", runtime_state = "Done",
    retry_budget = 1, attempt_count = 0,
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, "")

  oc._try_advance_parent(c1)

  local node = tree.read_node(parent)
  t.eq(node.runtime_state, "Done")
  t.eq(node.index, 1)
end)

t.suite("opencode.config")

t.test("has default model", function()
  t.is_true(oc.config.model ~= nil)
  t.is_true(type(oc.config.model) == "string")
end)

t.test("has default command", function()
  t.is_true(oc.config.command ~= nil)
  t.eq(oc.config.command, "opencode")
end)

t.suite("opencode.session management")

t.test("session returns nil for unknown task", function()
  t.eq(oc.session("/nonexistent"), nil)
end)

t.test("active_sessions returns table", function()
  local s = oc.active_sessions()
  t.is_table(s)
end)

t.test("stop returns error for no active session", function()
  local _, err = oc.stop("/nonexistent")
  t.is_true(err:find("no active") ~= nil, err)
end)

t.suite("opencode._try_decode_proposal")

t.test("decodes valid proposal", function()
  local p, err = oc._try_decode_proposal('{"title":"t","root":{"kind":"seq"}}')
  t.is_true(p ~= nil, err)
  t.eq(p.title, "t")
end)

t.test("rejects non-object", function()
  local _, err = oc._try_decode_proposal('"just a string"')
  t.is_true(err:find("not an object") ~= nil, err)
end)

t.test("rejects missing root", function()
  local _, err = oc._try_decode_proposal('{"title":"t"}')
  t.is_true(err:find("missing root") ~= nil, err)
end)

t.cleanup(dir)

return t.summary()
