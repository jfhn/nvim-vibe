if vim.g.loaded_nvim_vibe then return end
vim.g.loaded_nvim_vibe = true

vim.api.nvim_create_user_command("NvimVibe", function(cmd)
  local vibe = require("nvim-vibe")
  local args = vim.split(cmd.args, "%s+", { trimempty = true })
  local sub = args[1]

  local input = require("nvim-vibe.input")

  if sub == "switch" then
    if #args == 3 then
      vibe.switch(args[2], args[3])
    else
      vibe.pick()
    end
  elseif sub == "add-project" then
    if #args >= 2 then
      vibe.add_project(args[2], args[3] or "")
    else
      input.add_project()
    end
  elseif sub == "remove-project" then
    if #args >= 2 then
      vibe.remove_project(args[2])
    else
      local state = vibe.state()
      vim.ui.select(vim.tbl_keys(state.projects), { prompt = "Remove project:" }, function(sel)
        if sel then vibe.remove_project(sel) end
      end)
    end
  elseif sub == "add-worktree" then
    if #args >= 4 then
      vibe.add_worktree(args[2], args[3], args[4])
    else
      input.add_worktree(args[2] or nil)
    end
  elseif sub == "remove-worktree" then
    if #args >= 3 then
      vibe.remove_worktree(args[2], args[3])
    else
      local state = vibe.state()
      vim.ui.select(vim.tbl_keys(state.projects), { prompt = "Select project:" }, function(pname)
        if not pname then return end
        local wts = vim.tbl_keys(state.projects[pname].worktrees or {})
        vim.ui.select(wts, { prompt = "Remove worktree:" }, function(wt)
          if wt then vibe.remove_worktree(pname, wt) end
        end)
      end)
    end
  elseif sub == "sidebar" then
    vibe.toggle_sidebar()
  elseif sub == "pick" then
    vibe.pick()
  elseif sub == "reload" then
    vibe.reload()
  else
    vim.notify("nvim-vibe: unknown subcommand: " .. (sub or ""), vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function(_, line)
    local parts = vim.split(line, "%s+", { trimempty = true })
    if #parts <= 2 then
      return { "switch", "add-project", "remove-project", "add-worktree", "remove-worktree", "sidebar", "pick", "reload" }
    end
    return {}
  end,
})
