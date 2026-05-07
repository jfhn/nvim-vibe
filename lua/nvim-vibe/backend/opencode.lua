local tree = require("nvim-vibe.task_tree")
local runtime = require("nvim-vibe.task_runtime")
local events = require("nvim-vibe.task_events")
local config = require("nvim-vibe.config")

local M = {}

M.config = {
  command = "opencode",
  model = "opencode/minimax-m2.5-free",
}

local sessions = {}

function M._project_dir(task_dir)
  local root = tree.root_dir(task_dir)
  local tasks_parent = vim.fn.fnamemodify(root, ":h")
  local project_name = vim.fn.fnamemodify(tasks_parent, ":t")

  local projects = config.load()
  local project = projects[project_name]
  if project and project.path then
    return vim.fn.expand(project.path)
  end
  return vim.fn.getcwd()
end

function M._build_plan_prompt(node)
  local parts = {
    "You are a task planner. Given a task, create a structured execution plan.",
    "",
    "Task: " .. (node.title or "untitled"),
  }
  if node._body and node._body ~= "" then
    table.insert(parts, "")
    table.insert(parts, "Description:")
    table.insert(parts, node._body)
  end
  table.insert(parts, "")
  table.insert(parts, "Output ONLY a JSON code block with this exact structure:")
  table.insert(parts, "```json")
  table.insert(parts, "{")
  table.insert(parts, '  "title": "task title",')
  table.insert(parts, '  "summary": "brief plan description",')
  table.insert(parts, '  "root": {')
  table.insert(parts, '    "kind": "sequence",')
  table.insert(parts, '    "title": "same as task title",')
  table.insert(parts, '    "on_error": "fail_fast",')
  table.insert(parts, '    "retry_budget": 1,')
  table.insert(parts, '    "master": { "backend": "opencode", "agent": "plan" },')
  table.insert(parts, '    "tasks": [')
  table.insert(parts, '      { "kind": "agent", "title": "step description", "retry_budget": 1, "agent": { "backend": "opencode", "role": "coder" } }')
  table.insert(parts, "    ]")
  table.insert(parts, "  }")
  table.insert(parts, "}")
  table.insert(parts, "```")
  table.insert(parts, "")
  table.insert(parts, "Rules:")
  table.insert(parts, "- Break work into clear sequential steps")
  table.insert(parts, "- Each step should be a focused action")
  table.insert(parts, "- Keep titles concise but descriptive")
  table.insert(parts, "- Output only the JSON block, no other text")
  return table.concat(parts, "\n")
end

function M._build_exec_prompt(node)
  local parts = { "Task: " .. (node.title or "untitled") }
  if node._body and node._body ~= "" then
    table.insert(parts, "")
    table.insert(parts, node._body)
  end
  return table.concat(parts, "\n")
end

function M._parse_events(output)
  local result = {}
  for line in output:gmatch("[^\n]+") do
    local ok, event = pcall(vim.json.decode, line)
    if ok and type(event) == "table" then
      table.insert(result, event)
    end
  end
  return result
end

function M._extract_text(parsed_events)
  local parts = {}
  for _, evt in ipairs(parsed_events) do
    if evt.type == "text" and evt.part and evt.part.text then
      table.insert(parts, evt.part.text)
    end
  end
  return table.concat(parts)
end

function M._extract_session_id(parsed_events)
  for _, evt in ipairs(parsed_events) do
    if evt.sessionID then return evt.sessionID end
  end
  return nil
end

function M._try_decode_proposal(json_str)
  local ok, proposal = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "invalid plan JSON: " .. tostring(proposal)
  end
  if type(proposal) ~= "table" then
    return nil, "plan JSON is not an object"
  end
  if not proposal.root then
    return nil, "proposal missing root field"
  end
  return proposal
end

function M._extract_proposal(text)
  local start_idx = text:find("```json")
  if start_idx then
    local content_start = text:find("\n", start_idx)
    if content_start then
      content_start = content_start + 1
      local end_idx = text:find("\n```", content_start)
      if end_idx then
        return M._try_decode_proposal(text:sub(content_start, end_idx - 1))
      end
    end
  end

  start_idx = text:find("```%s*{")
  if start_idx then
    local brace_start = text:find("{", start_idx)
    if brace_start then
      local end_idx = text:find("\n```", brace_start)
      if end_idx then
        return M._try_decode_proposal(text:sub(brace_start, end_idx - 1))
      end
    end
  end

  local first_brace = text:find("{")
  if first_brace then
    local last_brace = text:match(".*()}")
    if last_brace then
      return M._try_decode_proposal(text:sub(first_brace, last_brace))
    end
  end

  return nil, "no JSON plan found in response"
end

function M.solve(task_dir)
  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  if vim.fn.executable(M.config.command) == 0 then
    return nil, "opencode not found in PATH"
  end

  local prompt = M._build_plan_prompt(node)
  local project_dir = M._project_dir(task_dir)

  local cmd = {
    M.config.command, "run",
    "--format", "json",
    "--model", M.config.model,
    "--dir", project_dir,
    prompt,
  }

  vim.notify("nvim-vibe: planning via OpenCode...", vim.log.levels.INFO)

  local result = vim.system(cmd, { text = true }):wait()

  if result.code ~= 0 then
    return nil, "opencode failed (exit " .. result.code .. "): " .. (result.stderr or "unknown")
  end

  local parsed = M._parse_events(result.stdout or "")
  local text = M._extract_text(parsed)

  if text == "" then
    return nil, "opencode returned no text"
  end

  return M._extract_proposal(text)
end

function M.start(task_dir, opts)
  opts = opts or {}

  if sessions[task_dir] then
    return nil, "session already active for this task"
  end

  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  if vim.fn.executable(M.config.command) == 0 then
    return nil, "opencode not found in PATH"
  end

  local prompt = opts.prompt or M._build_exec_prompt(node)
  local project_dir = M._project_dir(task_dir)
  local model = opts.model or M.config.model

  local cmd = {
    M.config.command, "run",
    "--format", "json",
    "--model", model,
    "--dir", project_dir,
    prompt,
  }

  local partial = ""
  local session = {
    task_dir = task_dir,
    node_id = node.id,
    session_id = nil,
    status = "starting",
    text = "",
    job_id = nil,
  }

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      partial = partial .. data[1]
      for i = 2, #data do
        if partial ~= "" then
          local ok, evt = pcall(vim.json.decode, partial)
          if ok and type(evt) == "table" then
            M._handle_event(task_dir, session, evt)
          end
        end
        partial = data[i]
      end
    end,
    on_exit = function(_, exit_code)
      session.status = "finished"
      session.exit_code = exit_code
      M._handle_exit(task_dir, session, exit_code)
    end,
  })

  if job_id <= 0 then
    return nil, "failed to start opencode process"
  end

  session.job_id = job_id
  sessions[task_dir] = session

  events.append(task_dir, {
    task_id = node.id,
    type = "session_attached",
    payload = { backend = "opencode", model = model },
  })

  return session
end

function M._handle_event(task_dir, session, evt)
  if evt.type == "step_start" then
    if evt.sessionID then
      session.session_id = evt.sessionID
    end
    session.status = "running"
  elseif evt.type == "text" then
    if evt.part and evt.part.text then
      session.text = session.text .. evt.part.text
    end
  elseif evt.type == "step_finish" then
    session.status = "step_done"
    if evt.part and evt.part.tokens then
      session.tokens = evt.part.tokens
    end
    if evt.part and evt.part.cost then
      session.cost = evt.part.cost
    end
  end
end

function M._handle_exit(task_dir, session, exit_code)
  sessions[task_dir] = nil

  local node = tree.read_node(task_dir)
  if not node then return end
  if node.runtime_state ~= "Active" then return end

  if exit_code == 0 then
    runtime.transition(task_dir, "Done", { reason = "opencode session completed" })
    events.append(task_dir, {
      task_id = node.id,
      type = "node_completed",
      payload = {
        backend = "opencode",
        session_id = session.session_id,
        text_length = #session.text,
      },
    })
    vim.schedule(function()
      vim.notify("nvim-vibe: completed — " .. (node.title or "untitled"), vim.log.levels.INFO)
      M._try_advance_parent(task_dir)
    end)
  else
    runtime.transition(task_dir, "Failed", {
      reason = "opencode exited with code " .. exit_code,
    })
    events.append(task_dir, {
      task_id = node.id,
      type = "node_failed",
      payload = {
        backend = "opencode",
        exit_code = exit_code,
        session_id = session.session_id,
      },
    })
    vim.schedule(function()
      vim.notify("nvim-vibe: failed — " .. (node.title or "untitled"), vim.log.levels.ERROR)
    end)
  end
end

function M._try_advance_parent(child_dir)
  local parent_dir = tree.parent_dir(child_dir)
  if not parent_dir then return end

  local parent = tree.read_node(parent_dir)
  if not parent then return end
  if parent.kind ~= "sequence" then return end
  if parent.runtime_state ~= "Active" then return end

  local children = tree.children(parent_dir)
  local idx = parent.index or 0

  local current = children[idx + 1]
  if not current then return end
  if current.runtime_state ~= "Done" then return end

  parent.index = idx + 1
  parent.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  tree.write_node(parent_dir, parent, parent._body)

  events.append(parent_dir, {
    task_id = parent.id,
    type = "node_status_changed",
    payload = { reason = "sequence advanced", index = parent.index },
  })

  if parent.index >= #children then
    runtime.transition(parent_dir, "Done", { reason = "all children completed" })
    vim.notify("nvim-vibe: sequence completed — " .. (parent.title or "untitled"), vim.log.levels.INFO)
    M._try_advance_parent(parent_dir)
  else
    local next_child = children[parent.index + 1]
    if next_child and (next_child.runtime_state or "Planned") == "Planned" then
      M.execute(next_child._dir)
    end
  end
end

function M.execute(task_dir)
  local node = tree.read_node(task_dir)
  if not node then return nil, "node not found" end

  if tree.is_leaf(task_dir) then
    if (node.runtime_state or "Planned") == "Planned" then
      runtime.transition(task_dir, "Active", { reason = "execution started" })
    end
    return M.start(task_dir)
  end

  if node.kind == "sequence" then
    if (node.runtime_state or "Planned") ~= "Active" then
      return nil, "sequence not Active"
    end
    local children = tree.children(task_dir)
    local idx = node.index or 0
    local child = children[idx + 1]
    if not child then return nil, "no child at index " .. idx end
    return M.execute(child._dir)
  end

  return nil, "unsupported kind for execution: " .. (node.kind or "nil")
end

function M.stop(task_dir)
  local session = sessions[task_dir]
  if not session then return nil, "no active session" end

  if session.job_id then
    vim.fn.jobstop(session.job_id)
  end

  sessions[task_dir] = nil
  return true
end

function M.session(task_dir)
  return sessions[task_dir]
end

function M.active_sessions()
  local result = {}
  for dir, s in pairs(sessions) do
    table.insert(result, { dir = dir, session = s })
  end
  return result
end

return M
