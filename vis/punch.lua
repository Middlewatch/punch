-- punch for vis: capture from any buffer through the CLI, and buffer-local
-- edits (state cycle, checkbox toggle, scheduled/deadline) through the same
-- edit.* functions the CLI uses. Registers :punch, :punch-cycle,
-- :punch-toggle, :punch-scheduled, :punch-deadline and returns the module so
-- visrc can bind keys to its functions. No default key maps.
--
-- Two layouts: in the repo this file is vis/punch.lua and the library is
-- one directory up; vendored into ~/.config/vis/plugins/punch/ (make
-- vendor) it is init.lua with punch/ beside it, loaded by
-- require("plugins/punch"). $PUNCH_ROOT overrides either. Capture runs the
-- root's bin/punch when there is one (the repo), else punch on PATH
-- (bin/install).
-- luacheck: globals vis

local function exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function root_dir()
  local env = os.getenv("PUNCH_ROOT")
  if env and env ~= "" then
    return env
  end
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  local quoted = "'" .. source:gsub("'", "'\\''") .. "'"
  local p = io.popen("readlink -f " .. quoted)
  local real = p and p:read("l") or source
  if p then
    p:close()
  end
  local dir = real:match("^(.*)/[^/]*$") or "."
  if exists(dir .. "/punch/init.lua") then
    return dir
  end
  return dir:match("^(.*)/vis$") or dir
end

local root = root_dir()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local punch = require("punch")
local util, dates, parser, edit, registry = punch.util, punch.dates, punch.parser, punch.edit, punch.registry

local M = { root = root, bin = exists(root .. "/bin/punch") and (root .. "/bin/punch") or "punch" }

local function buffer_lines(file)
  local lines = {}
  for i = 1, #file.lines do
    lines[i] = file.lines[i]
  end
  return lines
end

-- Replaces the smallest window of the buffer that differs between old and
-- new, so an unchanged prefix and suffix are never rewritten.
function M.replace_lines(file, old, new)
  local n, m = #old, #new
  local head = 0
  while head < n and head < m and old[head + 1] == new[head + 1] do
    head = head + 1
  end
  local tail = 0
  while tail < n - head and tail < m - head and old[n - tail] == new[m - tail] do
    tail = tail + 1
  end
  local pos = 0
  for i = 1, head do
    pos = pos + #old[i] + 1
  end
  local len = 0
  for i = head + 1, n - tail do
    len = len + #old[i] + 1
  end
  if pos + len > file.size then
    len = file.size - pos
  end
  local text = {}
  for i = head + 1, m - tail do
    text[#text + 1] = new[i] .. "\n"
  end
  if len > 0 then
    file:delete(pos, len)
  end
  if #text > 0 then
    file:insert(pos, table.concat(text))
  end
end

-- Runs fn(lines, cursor_line, states) on the window's buffer and applies
-- the result. fn returns new lines, or nil and a message.
local function apply(win, fn)
  local file = win.file
  local old = buffer_lines(file)
  local states = registry.states()
  local new, msg = fn(old, win.selection.line, states)
  if not new then
    vis:info("punch: " .. (msg or "nothing to do"))
    return false
  end
  M.replace_lines(file, old, new)
  return true
end

function M.cycle(win)
  return apply(win or vis.win, function(lines, lnum, states)
    local entry = parser.entry_at(parser.parse(lines, states), lnum)
    if not entry then
      return nil, "no entry at or above line " .. lnum
    end
    local out = edit.cycle(lines, entry.lnum, states)
    if out then
      vis:info(out[entry.lnum])
    end
    return out
  end)
end

function M.toggle(win)
  return apply(win or vis.win, function(lines, lnum)
    local line = edit.toggle_checkbox(lines[lnum])
    if not line then
      return nil, "line " .. lnum .. " is not a checkbox"
    end
    local out = {}
    for i, l in ipairs(lines) do
      out[i] = l
    end
    out[lnum] = line
    return out
  end)
end

-- Sets a date field on the entry at the cursor; value takes shorthand.
function M.set_date(key, value, win)
  local ts = dates.parse_shorthand(value or "", dates.now())
  if not ts then
    vis:info("punch: bad date: " .. tostring(value))
    return false
  end
  return apply(win or vis.win, function(lines, lnum, states)
    local out = edit.set_field(lines, lnum, key, dates.format_timestamp(ts), states)
    if not out then
      return nil, "no entry at or above line " .. lnum
    end
    vis:info(key .. ": " .. dates.format_timestamp(ts))
    return out
  end)
end

-- Capture: every argument goes to bin/punch unchanged, so flags work as on
-- the command line. The CLI's one-line result shows in the status line.
function M.capture(argv)
  if #argv == 0 then
    vis:info("punch: usage: :punch TEXT... [-t TAG] [-s DATE] [-d DATE] [-r REPEAT] [-f FILE]")
    return false
  end
  local parts = { util.shell_quote(M.bin) }
  for _, a in ipairs(argv) do
    parts[#parts + 1] = util.shell_quote(a)
  end
  local status, out, err = vis:pipe(table.concat(parts, " "))
  local line = ((status == 0 and out or err) or ""):match("^[^\n]*")
  vis:info(line ~= "" and line or ("punch: exit " .. tostring(status)))
  return status == 0
end

vis:command_register("punch", function(argv)
  return M.capture(argv)
end, "punch: capture TEXT to the inbox (flags as the CLI)")

vis:command_register("punch-cycle", function(_, _, win)
  return M.cycle(win)
end, "punch: cycle the state of the entry at the cursor")

vis:command_register("punch-toggle", function(_, _, win)
  return M.toggle(win)
end, "punch: toggle the checkbox on the cursor line")

vis:command_register("punch-scheduled", function(argv, _, win)
  return M.set_date("scheduled", table.concat(argv, " "), win)
end, "punch: set scheduled on the entry at the cursor (shorthand ok)")

vis:command_register("punch-deadline", function(argv, _, win)
  return M.set_date("deadline", table.concat(argv, " "), win)
end, "punch: set deadline on the entry at the cursor (shorthand ok)")

return M
