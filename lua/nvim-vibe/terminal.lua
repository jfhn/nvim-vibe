local M = {}

local terminals = {}

local split_cmds = {
  replace = "enew",
  vertical = "rightbelow vnew",
  horizontal = "rightbelow new",
}

function M.open(name, opts)
  opts = opts or {}
  local cmd = opts.cmd or opts.shell or vim.o.shell
  local split = opts.split or "replace"

  local existing = terminals[name]
  if existing and vim.api.nvim_buf_is_valid(existing.buf) then
    local wins = vim.fn.win_findbuf(existing.buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
    else
      vim.cmd("buffer " .. existing.buf)
    end
    return existing
  end

  vim.cmd(split_cmds[split] or "enew")
  local buf = vim.api.nvim_get_current_buf()

  local user_on_exit = opts.on_exit
  vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code, _)
      terminals[name] = nil
      if user_on_exit then
        user_on_exit(exit_code)
      end
    end,
  })

  vim.api.nvim_buf_set_name(buf, "term://" .. name)
  vim.cmd("startinsert")

  terminals[name] = { buf = buf, name = name, cmd = cmd }
  return terminals[name]
end

function M.list()
  local result = {}
  for name, entry in pairs(terminals) do
    if vim.api.nvim_buf_is_valid(entry.buf) then
      table.insert(result, entry)
    else
      terminals[name] = nil
    end
  end
  return result
end

local function parse_args(raw)
  local shell, name
  local joined = table.concat(raw, " ")
  local bracket_shell, rest = joined:match("^%[([^%]]+)%]%s*(.*)")
  if bracket_shell then
    shell = bracket_shell
    name = rest
  else
    name = joined
  end
  if name == "" then name = nil end
  return name, shell
end

local function make_handler(split)
  return function(args)
    local name, shell = parse_args(args.fargs)
    name = name or ("terminal-" .. (#M.list() + 1))
    M.open(name, { shell = shell, split = split })
  end
end

local alias_map = {
  replace = "replace",
  vertical = "vertical",
  horizontal = "horizontal",
  r = "replace",
  v = "vertical",
  s = "horizontal",
}

function M.setup(opts)
  opts = opts or {}
  local nargs = { nargs = "*" }

  vim.api.nvim_create_user_command("TermR", make_handler("replace"), nargs)
  vim.api.nvim_create_user_command("TermV", make_handler("vertical"), nargs)
  vim.api.nvim_create_user_command("TermS", make_handler("horizontal"), nargs)

  local default = alias_map[opts.default or "replace"] or "replace"
  vim.api.nvim_create_user_command("Term", make_handler(default), nargs)
end

return M
