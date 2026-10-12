-- Mutations as pure functions over a table of lines: the CLI reads a file,
-- applies one, writes it back; the vis plugin applies the same function to
-- the open buffer. Neither front end carries format knowledge. Every
-- function returns a new table and leaves its input untouched.
local parser = require("punch.parser")
local dates = require("punch.dates")

local M = {}

local function copy_lines(lines)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = l
  end
  return out
end

function M.toggle_checkbox(line)
  local head, mark, tail = line:match(parser.CHECKBOX)
  if not head then
    return nil
  end
  return head .. (mark == " " and "x" or " ") .. tail
end

-- The heading line with its state replaced (state nil removes it).
local function heading_line(line, entry, state)
  local hashes, rest = line:match(parser.HEADING)
  if entry.state then
    rest = rest:sub(#entry.state + 2)
  end
  return hashes .. " " .. (state and (state .. " ") or "") .. rest
end

local function first_field(entry, key)
  for _, field in ipairs(entry.field_lines) do
    if field.key == key then
      return field
    end
  end
end

-- Registry order, then no state, then around again.
local function next_state(current, states)
  if current == nil then
    return states.order[1]
  end
  for i, name in ipairs(states.order) do
    if name == current then
      return states.order[i + 1]
    end
  end
  return states.order[1]
end

-- Builds the heading plus field lines for a new entry.
function M.entry_lines(opts)
  local depth = opts.depth or 1
  local head = string.rep("#", depth) .. " " .. (opts.state or "TODO") .. " " .. opts.title
  for _, tag in ipairs(opts.tags or {}) do
    head = head .. " #" .. tag
  end
  local out = { head }
  for _, key in ipairs({ "scheduled", "deadline", "repeat" }) do
    if opts[key] then
      out[#out + 1] = key .. ": " .. opts[key]
    end
  end
  return out
end

-- Appends a new entry at the end of the file, blank-line separated.
function M.capture(lines, opts)
  local out = copy_lines(lines)
  if #out > 0 and out[#out] ~= "" then
    out[#out + 1] = ""
  end
  for _, l in ipairs(M.entry_lines(opts)) do
    out[#out + 1] = l
  end
  return out
end

-- Sets (or replaces) one field on the entry at or above lnum.
function M.set_field(lines, lnum, key, value, states)
  local entry = parser.entry_at(parser.parse(lines, states), lnum)
  if not entry then
    return nil
  end
  local out = copy_lines(lines)
  local field = first_field(entry, key)
  if field then
    out[field.lnum] = key .. ": " .. value
  else
    table.insert(out, entry.fields_end + 1, key .. ": " .. value)
  end
  return out
end

-- Cycles the state of the heading on lnum through the registry order.
-- Closing stamps closed:, closing a repeating entry advances it in place,
-- reopening a non-repeating entry drops the stamp. Returns the new lines,
-- or nil when lnum is not a heading.
function M.cycle(lines, lnum, states, now)
  now = now or dates.now()
  local parsed = parser.parse(lines, states)
  local entry
  for _, e in ipairs(parsed.entries) do
    if e.lnum == lnum then
      entry = e
    end
  end
  if not entry then
    return nil
  end
  local out = copy_lines(lines)

  local target = next_state(entry.state, states)
  local closing = target ~= nil and not states.by_name[target].open
  local closed_value = string.format("%04d-%02d-%02dT%02d:%02d",
    now.year, now.month, now.day, now.hour or 0, now.min or 0)
  local repeat_field = first_field(entry, "repeat")
  local spec = repeat_field and dates.parse_repeat(repeat_field.value) or nil
  local indent = entry.field_lines[1] and lines[entry.field_lines[1].lnum]:match("^%s*") or ""
  local closed_line = indent .. "closed: " .. closed_value

  if closing and spec then
    for _, key in ipairs({ "scheduled", "deadline" }) do
      local field = first_field(entry, key)
      local ts = field and dates.parse_timestamp(field.value)
      if ts then
        out[field.lnum] = indent .. key .. ": " .. dates.format_timestamp(dates.advance(ts, spec, now))
      end
    end
    if entry.state ~= states.default_open then
      out[entry.lnum] = heading_line(out[entry.lnum], entry, states.default_open)
    end
    table.insert(out, entry.fields_end + 1, closed_line)
    return out
  end

  out[entry.lnum] = heading_line(out[entry.lnum], entry, target)
  if closing then
    local closed = first_field(entry, "closed")
    if closed then
      out[closed.lnum] = closed_line
    else
      table.insert(out, entry.fields_end + 1, closed_line)
    end
  elseif entry.state and not states.by_name[entry.state].open and not spec then
    for i = #entry.field_lines, 1, -1 do
      if entry.field_lines[i].key == "closed" then
        table.remove(out, entry.field_lines[i].lnum)
      end
    end
  end
  return out
end

-- Removes the entry at lnum with its subtree. Returns the remaining lines
-- and the removed block, or nil when lnum is not a heading.
function M.cut(lines, lnum, states)
  local parsed = parser.parse(lines, states)
  local entry
  for _, e in ipairs(parsed.entries) do
    if e.lnum == lnum then
      entry = e
    end
  end
  if not entry then
    return nil
  end
  local block, out = {}, {}
  for i, l in ipairs(lines) do
    if i >= entry.lnum and i <= entry.subtree_end then
      block[#block + 1] = l
    else
      out[#out + 1] = l
    end
  end
  while #block > 0 and block[#block] == "" do
    table.remove(block)
  end
  -- collapse the blank the cut left behind
  local at = entry.lnum
  if out[at] == "" and (at == 1 or out[at - 1] == "") then
    table.remove(out, at)
  end
  while #out > 0 and out[#out] == "" do
    table.remove(out)
  end
  return out, block
end

-- Shifts every heading in a block so its first heading has depth.
local function rebase(block, depth)
  local first = block[1] and block[1]:match("^(#+) ")
  if not first then
    return block
  end
  local delta = depth - #first
  local out = {}
  for i, l in ipairs(block) do
    local hashes, rest = l:match(parser.HEADING)
    if hashes then
      out[i] = string.rep("#", math.max(1, #hashes + delta)) .. " " .. rest
    else
      out[i] = l
    end
  end
  return out
end

-- Inserts a block under the heading at target_lnum (end of its subtree,
-- one level deeper) or, with target_lnum nil, at the end of the file as a
-- top-level entry.
function M.paste(lines, block, target_lnum, states)
  local out = copy_lines(lines)
  local at, depth
  if target_lnum then
    local parsed = parser.parse(lines, states)
    local target
    for _, e in ipairs(parsed.entries) do
      if e.lnum == target_lnum then
        target = e
      end
    end
    if not target then
      return nil
    end
    at, depth = target.subtree_end, target.depth + 1
    while at > target.lnum and out[at] == "" do
      at = at - 1
    end
  else
    while #out > 0 and out[#out] == "" do
      table.remove(out)
    end
    at, depth = #out, 1
  end
  local rebased = rebase(block, depth)
  local insert = {}
  if at > 0 then
    insert[#insert + 1] = ""
  end
  for _, l in ipairs(rebased) do
    insert[#insert + 1] = l
  end
  for i = #insert, 1, -1 do
    table.insert(out, at + 1, insert[i])
  end
  return out
end

-- Moves the entry at lnum from src into dst under target_lnum. When src and
-- dst are the same table the move happens within one file. Returns the new
-- src lines and dst lines (the same table twice for a same-file move).
function M.refile(src, lnum, dst, target_lnum, states)
  local remaining, block = M.cut(src, lnum, states)
  if not remaining then
    return nil
  end
  if src == dst then
    if target_lnum then
      if target_lnum > lnum then
        local parsed = parser.parse(src, states)
        local entry
        for _, e in ipairs(parsed.entries) do
          if e.lnum == lnum then
            entry = e
          end
        end
        if target_lnum <= entry.subtree_end then
          return nil -- cannot refile an entry under its own subtree
        end
        target_lnum = target_lnum - (#src - #remaining)
      end
    end
    local out = M.paste(remaining, block, target_lnum, states)
    return out, out
  end
  local pasted = M.paste(dst, block, target_lnum, states)
  if not pasted then
    return nil
  end
  return remaining, pasted
end

return M
