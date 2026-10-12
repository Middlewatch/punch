-- Registry data: the state list, the corpus list, and the inbox path. Plain
-- text files under $XDG_CONFIG_HOME/punch (default ~/.config/punch), one
-- item per line, blank lines and # comments ignored. Built-in defaults apply
-- when a file is absent. Files are re-read on every call; they are tiny and
-- this keeps the vis plugin hot-reloaded without a cache.
local util = require("punch.util")

local M = {}

function M.config_root()
  local xdg = os.getenv("XDG_CONFIG_HOME")
  local root = (xdg and xdg ~= "") and xdg or ((os.getenv("HOME") or "") .. "/.config")
  return root .. "/punch"
end

M.root = M.config_root()
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
function M.parse_corpus(lines)
  lines = lines or { "~/punch" }
  local paths = {}
  for _, line in ipairs(lines) do
    paths[#paths + 1] = util.expand(line)
  end
  return paths
end

function M.states()
  return M.parse_states(data_lines(M.states_file))
end

function M.corpus()
  return M.parse_corpus(data_lines(M.corpus_file))
end

-- inbox file: one line, the capture target. Default ~/punch/inbox.md.
function M.inbox()
  local lines = data_lines(M.inbox_file)
  return util.expand(lines and lines[1] or "~/punch/inbox.md")
end

return M
