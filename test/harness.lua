local M = {}

local passed = 0
local failed = 0
local current_suite = ""

function M.suite(name)
  current_suite = name
  print("  " .. name)
end

function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("    ✓ " .. name)
  else
    failed = failed + 1
    print("    ✗ " .. name .. ": " .. tostring(err))
  end
end

function M.eq(got, expected, msg)
  if got ~= expected then
    error((msg or "eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(got), 2)
  end
end

function M.neq(got, unexpected, msg)
  if got == unexpected then
    error((msg or "neq") .. ": did not expect " .. tostring(unexpected), 2)
  end
end

function M.is_true(val, msg)
  if not val then
    error((msg or "is_true") .. ": expected truthy, got " .. tostring(val), 2)
  end
end

function M.is_table(val, msg)
  if type(val) ~= "table" then
    error((msg or "is_table") .. ": expected table, got " .. type(val), 2)
  end
end

function M.summary()
  print("")
  print("  " .. passed .. " passed, " .. failed .. " failed")
  return failed == 0
end

function M.tmpdir()
  local dir = "/tmp/nvim-vibe-test-" .. os.time() .. "-" .. math.random(1000, 9999)
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.cleanup(dir)
  vim.fn.delete(dir, "rf")
end

return M
