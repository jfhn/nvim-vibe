if vim.g.loaded_nvim_vibe then return end
vim.g.loaded_nvim_vibe = true

vim.api.nvim_create_user_command("NvimVibe", function(cmd)
  local vibe = require("nvim-vibe")
  local args = vim.split(cmd.args, "%s+", { trimempty = true })
  local sub = args[1]

  if sub == "switch" then
    if #args == 3 then
      vibe.switch(args[2], args[3])
    else
      vibe.pick()
    end
  elseif sub == "add-project" then
    if #args >= 2 then
      vibe.add_project(args[2], args[3] or "")
    end
  elseif sub == "remove-project" then
    if #args >= 2 then
      vibe.remove_project(args[2])
    end
  elseif sub == "add-worktree" then
    if #args >= 4 then
      vibe.add_worktree(args[2], args[3], args[4])
    end
  elseif sub == "remove-worktree" then
    if #args >= 3 then
      vibe.remove_worktree(args[2], args[3])
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
