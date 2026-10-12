-- Registry data: the state list, the corpus list, and the inbox path. Plain
-- text files in the punch home ($PUNCH_HOME, default ~/punch), beside the
-- inbox: one item per line, blank lines and # comments ignored. Built-in
-- defaults apply when a file is absent, so a fresh machine needs no file at
-- all. The lists are machine-local data, not configuration, which is why
-- they live with the corpus rather than under ~/.config. Files are re-read
-- on every call; they are tiny and this keeps the vis plugin hot-reloaded
-- without a cache.
local util = require("punch.util")

local M = {}

function M.home()
  local env = os.getenv("PUNCH_HOME")
  if env and env ~= "" then
    return util.expand(env)
  end
  return (os.getenv("HOME") or "") .. "/punch"
end

M.root = M.home()
M.states_file = M.root .. "/states"
M.corpus_file = M.root .. "/corpus"
M.inbox_file = M.root .. "/inbox"

local function data_lines(path)
  local raw = util.read_lines(path)
  if not raw then
    return nil
  end
  local lines = {}
  for _, line in ipairs(raw) do
    line = util.trim(line)
    if line ~= "" and line:sub(1, 1) ~= "#" then
      lines[#lines + 1] = line
    end
  end
  return lines
end

-- states file: one state per line, "NAME open|closed [default]".
function M.parse_states(lines)
  lines = lines or { "TODO open default", "DONE closed" }
  local states = { by_name = {}, order = {} }
  for _, line in ipairs(lines) do
    local tokens = util.split_ws(line)
    local name = tokens[1]
    if name and name:upper() == name then
      local state = { name = name, open = tokens[2] ~= "closed" }
      states.by_name[name] = state
      states.order[#states.order + 1] = name
      if state.open and tokens[3] == "default" then
        states.default_open = name
      end
    end
  end
  if not states.default_open then
    for _, name in ipairs(states.order) do
      if states.by_name[name].open then
        states.default_open = name
        break
      end
    end
  end
  return states
end

-- corpus file: one path per line; a directory expands recursively to every
-- *.md beneath it, a file is taken as-is (normalization is corpus.files).
-- The default corpus is the punch home itself.
function M.parse_corpus(lines)
  lines = lines or { M.root }
  local paths = {}
  for _, line in ipairs(lines) do
    paths[#paths + 1] = util.expand(line)
  end
  return paths
end

-- The corpus file's lines as written (comments and blanks included), or
-- nil when there is none.
function M.corpus_lines()
  return util.read_lines(M.corpus_file)
end

-- Appends paths to the corpus file in ~ form, skipping ones already
-- listed. Returns the added paths and the already-listed ones.
function M.add_corpus(paths)
  local lines = M.corpus_lines() or {}
  local listed = {}
  for _, line in ipairs(data_lines(M.corpus_file) or {}) do
    listed[util.expand(line)] = true
  end
  local added, dup = {}, {}
  for _, raw in ipairs(paths) do
    local full = util.expand(raw)
    if listed[full] then
      dup[#dup + 1] = full
    else
      listed[full] = true
      lines[#lines + 1] = util.contract(full)
      added[#added + 1] = full
    end
  end
  if #added > 0 then
    util.mkdir_p(M.root)
    local ok, err = util.write_lines(M.corpus_file, lines)
    if not ok then
      return nil, err
    end
  end
  return added, dup
end

function M.states()
  return M.parse_states(data_lines(M.states_file))
end

function M.corpus()
  return M.parse_corpus(data_lines(M.corpus_file))
end

-- inbox file: one line, the capture target. Default inbox.md in the home.
function M.inbox()
  local lines = data_lines(M.inbox_file)
  return util.expand(lines and lines[1] or (M.root .. "/inbox.md"))
end

return M
