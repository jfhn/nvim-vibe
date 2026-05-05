local M = {}

local terminals = {}

function M.open(name, opts)
  opts = opts or {}
  local shell = opts.shell or vim.o.shell

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

  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()

  vim.fn.termopen(shell, {
    on_exit = function()
      terminals[name] = nil
    end,
  })

  vim.api.nvim_buf_set_name(buf, "term://" .. name)
  vim.cmd("startinsert")

  terminals[name] = { buf = buf, name = name, shell = shell }
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

function M.setup()
  vim.api.nvim_create_user_command("Term", function(args)
    local name, shell = parse_args(args.fargs)
    name = name or ("terminal-" .. (#M.list() + 1))
    M.open(name, { shell = shell })
  end, { nargs = "*" })
end

return M
