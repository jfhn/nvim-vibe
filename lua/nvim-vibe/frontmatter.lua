local M = {}

function M.parse(content)
  if content:sub(-1) ~= "\n" then
    content = content .. "\n"
  end

  if content:sub(1, 4) ~= "---\n" then
    return {}, content
  end

  local end_pos = content:find("\n---\n", 5, true)
  if not end_pos then
    return {}, content
  end

  local fm = content:sub(5, end_pos - 1)
  local meta = {}
  local current_map_key = nil

  for line in fm:gmatch("[^\n]+") do
    if line:match("^  %S") and current_map_key then
      local key, val = line:match("^  (%S+):%s*(.*)$")
      if key then
        meta[current_map_key][key] = M._coerce(val)
      end
    else
      local key, val = line:match("^(%S+):%s*(.*)$")
      if key then
        current_map_key = nil
        if val == "" or val == nil then
          meta[key] = nil
          current_map_key = key
          meta[key] = {}
        else
          meta[key] = M._coerce(val)
        end
      end
    end
  end

  -- clean up empty maps that were just nil values
  for k, v in pairs(meta) do
    if type(v) == "table" and next(v) == nil then
      meta[k] = vim.NIL
    end
  end

  local body = content:sub(end_pos + 5)
  if body:sub(1, 1) == "\n" then
    body = body:sub(2)
  end
  return meta, body
end

function M._coerce(val)
  if val == "true" then return true end
  if val == "false" then return false end
  if val == "null" or val == "" then return vim.NIL end
  local num = tonumber(val)
  if num then return num end
  return val
end

function M.serialize(meta, body)
  local lines = { "---" }

  local key_order = {
    "id", "kind", "title", "status", "runtime_state", "block_reason",
    "parent_id", "position", "index", "on_error", "retry_budget",
    "master", "agent", "source_task", "attempt_count",
    "summary_updated_at", "updated_at",
  }

  local seen = {}
  for _, key in ipairs(key_order) do
    local val = meta[key]
    if val ~= nil then
      M._write_field(lines, key, val)
      seen[key] = true
    end
  end

  for key, val in pairs(meta) do
    if not seen[key] then
      M._write_field(lines, key, val)
    end
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  if body and body ~= "" then
    table.insert(lines, body)
  end

  return table.concat(lines, "\n")
end

function M._write_field(lines, key, val)
  if val == vim.NIL then
    table.insert(lines, key .. ":")
  elseif type(val) == "table" then
    table.insert(lines, key .. ":")
    for k, v in pairs(val) do
      if v == vim.NIL then
        table.insert(lines, "  " .. k .. ":")
      else
        table.insert(lines, "  " .. k .. ": " .. tostring(v))
      end
    end
  elseif type(val) == "boolean" then
    table.insert(lines, key .. ": " .. (val and "true" or "false"))
  else
    table.insert(lines, key .. ": " .. tostring(val))
  end
end

return M
