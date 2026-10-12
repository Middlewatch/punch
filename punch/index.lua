-- The derived, disposable index: scans the corpus, applies tag and field
-- inheritance, and answers agenda and integrity queries. Files are the
-- source of truth; nothing here persists between calls.
local util = require("punch.util")
local parser = require("punch.parser")
local dates = require("punch.dates")
local corpus = require("punch.corpus")

local M = {}

local function union(inherited, own)
  local seen, out = {}, {}
  for _, list in ipairs({ inherited, own }) do
    for _, tag in ipairs(list) do
      if not seen[tag] then
        seen[tag] = true
        out[#out + 1] = tag
      end
    end
  end
  return out
end

local function non_reserved(fields, into)
  for key, value in pairs(fields) do
    if not parser.reserved[key] then
      into[key] = value
    end
  end
  return into
end

local function resolve(path, file, out)
  local stack = {}
  local file_fields = non_reserved(file.fields, {})
  local by_raw = {}
  for _, entry in ipairs(file.entries) do
    while #stack > 0 and stack[#stack].depth >= entry.depth do
      table.remove(stack)
    end
    local top = stack[#stack]
    local inherited_tags = top and top.tags or file.tags
    local inherited_fields = top and top.fields or file_fields

    local resolved = util.copy(entry)
    resolved.file = path
    resolved.tags = union(inherited_tags, entry.tags)
    resolved.fields = util.merge(inherited_fields, entry.fields)
    resolved.own_fields = entry.fields
    out.entries[#out.entries + 1] = resolved
    by_raw[entry] = resolved

    stack[#stack + 1] = {
      depth = entry.depth,
      tags = resolved.tags,
      fields = non_reserved(entry.fields, util.copy(inherited_fields)),
    }
  end
  for _, box in ipairs(file.checkboxes) do
    local b = util.copy(box)
    b.file = path
    b.entry = box.entry and by_raw[box.entry] or nil
    out.checkboxes[#out.checkboxes + 1] = b
  end
  for _, link in ipairs(file.links) do
    local l = util.copy(link)
    l.file = path
    l.entry = link.entry and by_raw[link.entry] or nil
    out.links[#out.links + 1] = l
  end
  out.files[#out.files + 1] = { path = path, title = file.fields.title, entries = file.entries }
end

-- Scans corpus paths (default: the registry's) into
-- { entries, checkboxes, links, files }; each entry carries file, lnum,
-- depth, state, title, tags (inherited), fields (inherited), own_fields.
function M.scan(paths, states)
  local out = { entries = {}, checkboxes = {}, links = {}, files = {} }
  for _, path in ipairs(corpus.files(paths)) do
    local lines = util.read_lines(path)
    if lines then
      resolve(path, parser.parse(lines, states), out)
    end
  end
  return out
end

-- Earliest valid value wins when a date field was repeated.
function M.field_date(entry, key)
  local value = entry.fields[key]
  if value == nil then
    return nil
  end
  local values = type(value) == "table" and value or { value }
  local best
  for _, item in ipairs(values) do
    local ts = dates.parse_timestamp(item)
    if ts and (best == nil or dates.datenum(ts) < dates.datenum(best)) then
      best = ts
    end
  end
  return best
end

function M.open(entries, states)
  local out = {}
  for _, entry in ipairs(entries) do
    local state = entry.state and states.by_name[entry.state]
    if state and state.open then
      out[#out + 1] = entry
    end
  end
  return out
end

local function by_position(a, b)
  if a.file ~= b.file then
    return a.file < b.file
  end
  return a.lnum < b.lnum
end

local function by_date(a, b)
  if a.sort_date ~= b.sort_date then
    return a.sort_date < b.sort_date
  end
  return by_position(a, b)
end

local function dated(entries, states, key, limit)
  local out = {}
  for _, entry in ipairs(M.open(entries, states)) do
    local ts = M.field_date(entry, key)
    if ts and (limit == nil or dates.datenum(ts) <= limit) then
      local e = util.copy(entry)
      e.sort_date, e.sort_key = dates.datenum(ts), key
      out[#out + 1] = e
    end
  end
  table.sort(out, by_date)
  return out
end

-- Open entries whose scheduled or deadline date has arrived, earliest
-- first; an entry with both appears once.
function M.today(entries, states, today)
  local limit = dates.datenum(today)
  local seen, out = {}, {}
  for _, key in ipairs({ "deadline", "scheduled" }) do
    for _, entry in ipairs(dated(entries, states, key, limit)) do
      local id = entry.file .. ":" .. entry.lnum
      if not seen[id] then
        seen[id] = true
        out[#out + 1] = entry
      end
    end
  end
  table.sort(out, by_date)
  return out
end

function M.scheduled(entries, states, limit)
  return dated(entries, states, "scheduled", limit)
end

function M.deadline(entries, states, limit)
  return dated(entries, states, "deadline", limit)
end

function M.tagged(entries, states, tag)
  local out = {}
  for _, entry in ipairs(M.open(entries, states)) do
    if util.contains(entry.tags, tag) then
      out[#out + 1] = entry
    end
  end
  table.sort(out, by_position)
  return out
end

function M.open_checkboxes(checkboxes)
  local out = {}
  for _, box in ipairs(checkboxes) do
    if not box.done then
      out[#out + 1] = box
    end
  end
  table.sort(out, by_position)
  return out
end

-- Integrity report: { dangling = { link... }, duplicate_ids = { { id, entries } },
-- bad_fields = { { file, lnum, key, value } } }. A [[file]] target matches a
-- corpus file by title field or by basename without .md; a heading part
-- matches a heading title in that file. A bad field is a date field that
-- is not a timestamp or a repeat that is not a recurrence.
function M.check(scan)
  local bad_fields = {}
  for _, e in ipairs(scan.entries) do
    for _, f in ipairs(e.field_lines) do
      local ok = true
      if f.key == "scheduled" or f.key == "deadline" or f.key == "closed" then
        ok = dates.parse_timestamp(f.value) ~= nil
      elseif f.key == "repeat" then
        ok = dates.parse_repeat(f.value) ~= nil
      end
      if not ok then
        bad_fields[#bad_fields + 1] = { file = e.file, lnum = f.lnum, key = f.key, value = f.value }
      end
    end
  end
  table.sort(bad_fields, by_position)
  local ids, dup = {}, {}
  for _, e in ipairs(scan.entries) do
    local id = e.own_fields.id
    if type(id) == "string" then
      ids[id] = ids[id] or {}
      ids[id][#ids[id] + 1] = e
    end
  end
  local duplicate_ids = {}
  for id, list in pairs(ids) do
    if #list > 1 and not dup[id] then
      dup[id] = true
      duplicate_ids[#duplicate_ids + 1] = { id = id, entries = list }
    end
  end
  local by_name = {}
  for _, f in ipairs(scan.files) do
    by_name[util.basename(f.path):gsub("%.md$", "")] = f
    if type(f.title) == "string" then
      by_name[f.title] = f
    end
  end
  local dangling = {}
  for _, link in ipairs(scan.links) do
    local ok
    if link.id then
      ok = ids[link.id] ~= nil
    else
      local f = by_name[link.target]
      ok = f ~= nil
      if ok and link.heading then
        ok = false
        for _, e in ipairs(f.entries) do
          if e.title == link.heading then
            ok = true
            break
          end
        end
      end
    end
    if not ok then
      dangling[#dangling + 1] = link
    end
  end
  table.sort(dangling, by_position)
  return { dangling = dangling, duplicate_ids = duplicate_ids, bad_fields = bad_fields }
end

return M
