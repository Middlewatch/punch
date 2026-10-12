-- Small helpers shared by the punch core. Plain Lua 5.4, no vim, no C
-- modules, so the same code runs under the CLI interpreter and inside vis.
local M = {}

function M.trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

function M.split_ws(s)
  local out = {}
  for token in s:gmatch("%S+") do
    out[#out + 1] = token
  end
  return out
end

function M.copy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

-- Shallow merge, later tables win.
function M.merge(...)
  local out = {}
  for _, t in ipairs({ ... }) do
    for k, v in pairs(t) do
      out[k] = v
    end
  end
  return out
end

function M.contains(list, x)
  for _, v in ipairs(list) do
    if v == x then
      return true
    end
  end
  return false
end

function M.expand(path)
  if path:sub(1, 1) == "~" then
    return (os.getenv("HOME") or "") .. path:sub(2)
  end
  return path
end

-- The inverse of expand for display: a path under $HOME shown as ~/...
function M.contract(path)
  local home = os.getenv("HOME")
  if home and home ~= "" and path:sub(1, #home + 1) == home .. "/" then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

function M.shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.is_dir(path)
  return os.execute("test -d " .. M.shell_quote(path)) == true
end

function M.is_file(path)
  return os.execute("test -f " .. M.shell_quote(path)) == true
end

function M.mkdir_p(path)
  return os.execute("mkdir -p " .. M.shell_quote(path)) == true
end

function M.read_lines(path)
  local f, err = io.open(path, "r")
  if not f then
    return nil, err
  end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()
  return lines
end

function M.write_lines(path, lines)
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(table.concat(lines, "\n"))
  if #lines > 0 then
    f:write("\n")
  end
  f:close()
  return true
end

function M.basename(path)
  return (path:match("([^/]+)$"))
end

function M.dirname(path)
  return (path:match("^(.*)/[^/]*$")) or "."
end

return M
