local core = require("nvim-vibe.core")
local tasks = require("nvim-vibe.tasks")
local tree = require("nvim-vibe.task_tree")
local planner = require("nvim-vibe.planner")

local M = {}

local sidebar_buf = nil
local sidebar_win = nil

-- expanded[project_name] = true/false (project level)
-- expanded[project_name..":tasks"] = true/false
-- expanded[project_name..":worktrees"] = true/false
local expanded = {}

local function is_open()
  return sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)
end

local status_icons = {
  planned        = "○",
  ready          = "◎",
  running        = "●",
  waiting_review = "?",
  blocked        = "⊘",
  completed      = "✓",
  failed         = "✗",
  cancelled      = "-",
}

local status_hl = {
  planned        = "Comment",
  ready          = "Normal",
  running        = "Function",
  waiting_review = "WarningMsg",
  blocked        = "ErrorMsg",
  completed      = "Comment",
  failed         = "ErrorMsg",
  cancelled      = "Comment",
}

local kind_markers = { agent = "A", sequence = "S", parallel = "P" }

local function render_task_node(node, project, depth, lines, highlights, actions)
  local indent = string.rep(" ", 6 + depth * 2)
  local s = node.status or "planned"
  local si = status_icons[s] or "?"
  local km = kind_markers[node.kind] or "A"
  local has_children = not tree.is_leaf(node._dir)

  local label = indent
  if has_children then
    local ekey = "task:" .. node._dir
    label = label .. (expanded[ekey] and "▼ " or "▶ ")
  end
  label = label .. km .. " " .. si .. " " .. (node.title or node.name or "untitled")

  if s == "blocked" and node.block_reason and node.block_reason ~= vim.NIL then
    label = label .. " (" .. tostring(node.block_reason) .. ")"
  end

  table.insert(lines, label)
  table.insert(highlights, { line = #lines, hl = status_hl[s] or "Normal" })
  table.insert(actions, {
    type = "task",
    project = project,
    file = node._file,
    dir = node._dir,
    kind = node.kind,
    status = s,
  })

  if has_children and expanded["task:" .. node._dir] then
    local children = tree.children(node._dir)
    for _, child in ipairs(children) do
      render_task_node(child, project, depth + 1, lines, highlights, actions)
    end
  end
end

local function build_lines()
  local lines = {}
  local highlights = {}
  local actions = {}
  local state = core.state()

  for pname, project in pairs(state.projects) do
    local icon = expanded[pname] and "▼" or "▶"
    local marker = (pname == state.current_project) and " *" or ""
    table.insert(lines, icon .. " " .. pname .. marker)
    table.insert(highlights, { line = #lines, hl = "Title" })
    table.insert(actions, { type = "project", name = pname })

    if expanded[pname] then
      -- Tasks section
      local tkey = pname .. ":tasks"
      local ticon = expanded[tkey] and "▼" or "▶"
      table.insert(lines, "  " .. ticon .. " Tasks")
      table.insert(highlights, { line = #lines, hl = "Statement" })
      table.insert(actions, { type = "section", key = tkey })

      if expanded[tkey] then
        local project_tasks = tasks.list(pname)
        if #project_tasks == 0 then
          table.insert(lines, "      (none)")
          table.insert(highlights, { line = #lines, hl = "Comment" })
          table.insert(actions, { type = "none" })
        else
          for _, task in ipairs(project_tasks) do
            render_task_node(task, pname, 0, lines, highlights, actions)
          end
        end
      end

      -- Worktrees section
      local wkey = pname .. ":worktrees"
      local wicon = expanded[wkey] and "▼" or "▶"
      table.insert(lines, "  " .. wicon .. " Worktrees")
      table.insert(highlights, { line = #lines, hl = "Statement" })
      table.insert(actions, { type = "section", key = wkey })

      if expanded[wkey] then
        local wts = project.worktrees or {}
        if vim.tbl_isempty(wts) then
          table.insert(lines, "      (none)")
          table.insert(highlights, { line = #lines, hl = "Comment" })
          table.insert(actions, { type = "none" })
        else
          for wname, _ in pairs(wts) do
            local wmarker = (pname == state.current_project and wname == state.current_worktree) and " ●" or ""
            table.insert(lines, "      " .. wname .. wmarker)
            table.insert(highlights, { line = #lines, hl = "Normal" })
            table.insert(actions, { type = "worktree", project = pname, name = wname })
          end
        end
      end
    end
  end

  if #lines == 0 then
    lines = { "  No projects configured" }
    highlights = { { line = 1, hl = "Comment" } }
    actions = { { type = "none" } }
  end

  return lines, highlights, actions
end

function M.toggle()
  if is_open() then
    M.close()
  else
    M.open()
  end
end

function M.open()
  if is_open() then return end

  vim.cmd("topleft 35vnew")
  sidebar_win = vim.api.nvim_get_current_win()
  sidebar_buf = vim.api.nvim_get_current_buf()

  vim.bo[sidebar_buf].buftype = "nofile"
  vim.bo[sidebar_buf].bufhidden = "wipe"
  vim.bo[sidebar_buf].swapfile = false
  vim.bo[sidebar_buf].filetype = "nvim-vibe"
  vim.wo[sidebar_win].number = false
  vim.wo[sidebar_win].relativenumber = false
  vim.wo[sidebar_win].signcolumn = "no"
  vim.wo[sidebar_win].winfixwidth = true

  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = sidebar_buf,
    callback = function() M.render() end,
  })

  local actions_ref = {}

  vim.keymap.set("n", "<CR>", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    if action.type == "project" then
      core.switch(action.name)
      M.render()
    elseif action.type == "worktree" then
      core.switch(action.project, action.name)
      M.render()
    elseif action.type == "task" then
      vim.cmd("wincmd l")
      vim.cmd("edit " .. vim.fn.fnameescape(action.file))
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "<TAB>", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    if action.type == "project" then
      expanded[action.name] = not expanded[action.name]
      M.render()
    elseif action.type == "section" then
      expanded[action.key] = not expanded[action.key]
      M.render()
    elseif action.type == "task" and action.dir then
      local ekey = "task:" .. action.dir
      expanded[ekey] = not expanded[ekey]
      M.render()
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "x", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    if action.type == "task" then
      tasks.toggle(action.file)
      M.render()
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "d", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    if action.type == "task" then
      vim.ui.select({ "Yes", "No" }, { prompt = "Delete task?" }, function(choice)
        if choice == "Yes" then
          tasks.remove(action.file)
          M.render()
        end
      end)
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "r", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    if action.type == "task" then
      vim.ui.input({ prompt = "Rename to: ", default = action.file }, function(new_path)
        if new_path and new_path ~= "" and new_path ~= action.file then
          vim.fn.rename(action.file, new_path)
          M.render()
        end
      end)
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "<C-r>", function()
    M.render()
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "a", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    local project_name
    if action.type == "project" then
      project_name = action.name
    elseif action.project then
      project_name = action.project
    elseif action.key then
      project_name = action.key:match("^(.+):tasks$") or action.key:match("^(.+):worktrees$")
    end
    if project_name then
      vim.cmd("wincmd l")
      tasks.create(project_name)
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "s", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action or action.type ~= "task" then return end
    if not action.dir then return end
    local _, err = planner.solve(action.dir)
    if err then
      vim.notify("nvim-vibe: solve failed: " .. err, vim.log.levels.ERROR)
    end
    M.render()
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "gp", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action or action.type ~= "task" then return end
    if action.status ~= "waiting_review" then
      vim.notify("nvim-vibe: task not awaiting review", vim.log.levels.WARN)
      return
    end
    local _, err = planner.approve(action.dir)
    if err then
      vim.notify("nvim-vibe: approve failed: " .. err, vim.log.levels.ERROR)
    end
    M.render()
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "gr", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action or action.type ~= "task" then return end
    if action.status ~= "waiting_review" then
      vim.notify("nvim-vibe: task not awaiting review", vim.log.levels.WARN)
      return
    end
    local _, err = planner.reject(action.dir)
    if err then
      vim.notify("nvim-vibe: reject failed: " .. err, vim.log.levels.ERROR)
    end
    M.render()
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "ge", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action or action.type ~= "task" then return end
    if not action.dir then return end
    local backend_mod = require("nvim-vibe.backend")
    local _, err = backend_mod.execute(action.dir)
    if err then
      vim.notify("nvim-vibe: execute failed: " .. err, vim.log.levels.ERROR)
    end
    M.render()
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "q", M.close, { buffer = sidebar_buf })

  M._actions_ref = actions_ref
  M._update_actions = function(a)
    for k in pairs(actions_ref) do actions_ref[k] = nil end
    for k, v in pairs(a) do actions_ref[k] = v end
  end

  M.render()
end

function M.render()
  if not sidebar_buf or not vim.api.nvim_buf_is_valid(sidebar_buf) then return end

  local lines, highlights, actions = build_lines()

  vim.bo[sidebar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)
  vim.bo[sidebar_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(sidebar_buf, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace("nvim_vibe_sidebar")
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(sidebar_buf, ns, hl.hl, hl.line - 1, 0, -1)
  end

  if M._update_actions then
    local indexed = {}
    for i, a in ipairs(actions) do indexed[i] = a end
    M._update_actions(indexed)
  end
end

function M.close()
  if not sidebar_win or not vim.api.nvim_win_is_valid(sidebar_win) then
    sidebar_win = nil
    sidebar_buf = nil
    return
  end

  local wins = vim.api.nvim_list_wins()
  if #wins <= 1 then
    -- last window: try switching to another buffer
    local bufs = vim.tbl_filter(function(b)
      return vim.api.nvim_buf_is_loaded(b)
        and vim.bo[b].buflisted
        and b ~= sidebar_buf
    end, vim.api.nvim_list_bufs())

    if #bufs > 0 then
      vim.api.nvim_win_set_buf(sidebar_win, bufs[1])
    else
      vim.notify("nvim-vibe: no other buffers to switch to", vim.log.levels.WARN)
      return
    end
  else
    vim.api.nvim_win_close(sidebar_win, true)
  end

  sidebar_win = nil
  sidebar_buf = nil
end

return M
