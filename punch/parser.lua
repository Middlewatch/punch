-- Parses one markdown file's lines into raw entries per SCHEMA.md: hash
-- headings with state, title, and trailing tags; a field run after each
-- heading; a file-level block (optionally fenced as front matter); checkbox
-- lines; wiki links. Tag and field inheritance is the index's job.
local util = require("punch.util")

local M = {}

-- Reserved fields describe exactly one entry and never inherit.
M.reserved = { scheduled = true, deadline = true, closed = true, ["repeat"] = true, id = true }

M.HEADING = "^(#+) (.*)$"
M.FIELD = "^%s*([a-z][a-z0-9%-]*):%s*(.-)%s*$"
M.CHECKBOX = "^(%s*- %[)([ xX])(%] ?.*)$"
local LINK = "%[%[([^%]]+)%]%]"

local function is_tag(token)
  return token:match("^#[^%s#]+$") ~= nil
end

-- Splits heading text into state (first token, uppercase, in the registry),
-- title, and trailing tags.
function M.split_heading(text, states)
  local tokens = util.split_ws(text)
  local state
  if tokens[1] and tokens[1]:upper() == tokens[1] and states.by_name[tokens[1]] then
    state = table.remove(tokens, 1)
  end
  local tags = {}
  while #tokens > 0 and is_tag(tokens[#tokens]) do
    table.insert(tags, 1, table.remove(tokens):sub(2))
  end
  return state, table.concat(tokens, " "), tags
end

local function add_field(fields, key, value)
  local existing = fields[key]
  if existing == nil then
    fields[key] = value
  elseif type(existing) == "table" then
    existing[#existing + 1] = value
  else
    fields[key] = { existing, value }
  end
end

-- "[[file]]", "[[file#heading]]", "[[#id]]" into { target?, heading?, id? }
-- where target is the linked file's name (the link's own file is .file).
function M.parse_link(text)
  if text:sub(1, 1) == "#" then
    return { id = text:sub(2) }
  end
  local file, heading = text:match("^([^#]*)#(.*)$")
  if file then
    return { target = file, heading = heading }
  end
  return { target = text }
end

local function collect_links(file, line, lnum, entry)
  for target in line:gmatch(LINK) do
    local link = M.parse_link(target)
    link.lnum, link.entry = lnum, entry
    file.links[#file.links + 1] = link
  end
end

-- Parses lines into { fields, tags, entries, checkboxes, links }. Each entry:
-- { lnum, depth, state, title, tags, fields, field_lines, fields_end,
--   subtree_end, checkboxes } where field_lines records each field line in
-- order, fields_end is the last line of the field run (the heading line when
-- there are none), and subtree_end is the last line of the entry's subtree.
function M.parse(lines, states)
  local file = { fields = {}, tags = {}, entries = {}, checkboxes = {}, links = {} }
  local entry = nil
  local in_fields = true -- the file-level block counts as a field run
  local fence_open = false

  for lnum, line in ipairs(lines) do
    local hashes, rest = line:match(M.HEADING)
    local box_head, box_mark, box_tail = line:match(M.CHECKBOX)
    if hashes then
      entry = {
        lnum = lnum,
        depth = #hashes,
        tags = {},
        fields = {},
        field_lines = {},
        fields_end = lnum,
        checkboxes = {},
      }
      entry.state, entry.title, entry.tags = M.split_heading(rest, states)
      file.entries[#file.entries + 1] = entry
      in_fields = true
      collect_links(file, line, lnum, entry)
    elseif box_head then
      local box = { lnum = lnum, done = box_mark ~= " ", text = box_tail:match("^%] ?(.*)$"), entry = entry }
      file.checkboxes[#file.checkboxes + 1] = box
      if entry then
        entry.checkboxes[#entry.checkboxes + 1] = box
      end
      in_fields = false
      collect_links(file, line, lnum, entry)
    elseif entry == nil then
      -- file-level block: one contiguous run of field lines, optionally
      -- fenced by --- (front matter) and optionally ended by a trailing tag
      -- line; anything else closes the block
      if in_fields then
        if line == "---" and lnum == 1 then
          fence_open = true
        elseif line == "---" and fence_open then
          fence_open = false
          in_fields = false
        else
          local key, value = line:match(M.FIELD)
          if key then
            add_field(file.fields, key, value)
          else
            local tokens = util.split_ws(line)
            local all_tags = #tokens > 0
            for _, token in ipairs(tokens) do
              all_tags = all_tags and is_tag(token)
            end
            if all_tags then
              for _, token in ipairs(tokens) do
                file.tags[#file.tags + 1] = token:sub(2)
              end
            end
            in_fields = false
          end
        end
      end
      collect_links(file, line, lnum, nil)
    else
      if in_fields then
        local key, value = line:match(M.FIELD)
        if key then
          add_field(entry.fields, key, value)
          entry.field_lines[#entry.field_lines + 1] = { key = key, value = value, lnum = lnum }
          entry.fields_end = lnum
        else
          in_fields = false
        end
      end
      collect_links(file, line, lnum, entry)
    end
  end

  for i, e in ipairs(file.entries) do
    e.subtree_end = #lines
    for j = i + 1, #file.entries do
      if file.entries[j].depth <= e.depth then
        e.subtree_end = file.entries[j].lnum - 1
        break
      end
    end
  end
  return file
end

-- The entry whose heading is on lnum, or the nearest entry above it.
function M.entry_at(parsed, lnum)
  local found
  for _, e in ipairs(parsed.entries) do
    if e.lnum <= lnum then
      found = e
    else
      break
    end
  end
  return found
end

return M
