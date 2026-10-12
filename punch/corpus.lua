-- Corpus entries to file set. Directories expand recursively to every *.md
-- beneath them (POSIX find, so no C module is needed inside vis); files are
-- taken as-is; missing paths contribute nothing. Order is stable and
-- duplicates are dropped.
local util = require("punch.util")

local M = {}

local function find_md(dir)
  local out = {}
  local p = io.popen("find " .. util.shell_quote(dir) .. " -type f -name '*.md' 2>/dev/null | sort")
  if not p then
    return out
  end
  for line in p:lines() do
    out[#out + 1] = line
  end
  p:close()
  return out
end

function M.files(paths)
  local seen, out = {}, {}
  for _, raw in ipairs(paths) do
    local path = util.expand(raw)
    local found
    if util.is_dir(path) then
      found = find_md(path)
    elseif util.is_file(path) then
      found = { path }
    else
      found = {}
    end
    for _, file in ipairs(found) do
      if not seen[file] then
        seen[file] = true
        out[#out + 1] = file
      end
    end
  end
  return out
end

return M
