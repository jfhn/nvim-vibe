local core = require("nvim-vibe.core")

local M = {}

local sidebar_buf = nil
local sidebar_win = nil
local expanded = {}

local function is_open()
  return sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)
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
      for wname, wpath in pairs(project.worktrees or {}) do
        local wmarker = (pname == state.current_project and wname == state.current_worktree) and " ●" or ""
        table.insert(lines, "  " .. wname .. wmarker)
        table.insert(highlights, { line = #lines, hl = "Normal" })
        table.insert(actions, { type = "worktree", project = pname, name = wname, path = wpath })
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

  M.render()

  local actions_ref = {}

  vim.keymap.set("n", "<CR>", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    if action.type == "worktree" then
      core.switch(action.project, action.name)
      M.render()
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "<TAB>", function()
    local line = vim.fn.line(".")
    local action = actions_ref[line]
    if not action then return end
    if action.type == "project" then
      expanded[action.name] = not expanded[action.name]
      M.render()
    end
  end, { buffer = sidebar_buf })

  vim.keymap.set("n", "q", M.close, { buffer = sidebar_buf })

  -- store ref for keymaps
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
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    vim.api.nvim_win_close(sidebar_win, true)
  end
  sidebar_win = nil
  sidebar_buf = nil
end

return M
