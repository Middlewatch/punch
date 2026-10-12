-- Loads vis/punch.lua against a stub of the vis Lua API and checks the
-- buffer glue: minimal window replacement, cycle, toggle, set date, and
-- capture's delegation to bin/punch. Run from the repo root (make test).
local root = (arg[0]:match("^(.*)/test/vis%.lua$")) or "."

local failed, passed = 0, 0
local function eq(name, got, want)
  if got == want then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write("FAIL " .. name .. ": got " .. tostring(got) .. " want " .. tostring(want) .. "\n")
  end
end

-- A File stub over one string with vis's byte-offset insert/delete and the
-- lines table semantics (#lines ignores the trailing newline).
local function new_file(text)
  local file = { text = text, inserts = 0, deletes = 0 }
  file.lines = setmetatable({}, {
    __index = function(_, i)
      local n = 0
      for line in (file.text .. "\n"):gmatch("(.-)\n") do
        n = n + 1
        if n == i then
          return line
        end
      end
    end,
    __len = function()
      local n = select(2, file.text:gsub("\n", ""))
      if #file.text > 0 and file.text:sub(-1) ~= "\n" then
        n = n + 1
      end
      return n
    end,
  })
  setmetatable(file, { __index = function(_, k)
    if k == "size" then
      return #file.text
    end
  end })
  function file:insert(pos, data)
    self.inserts = self.inserts + 1
    self.text = self.text:sub(1, pos) .. data .. self.text:sub(pos + 1)
  end
  function file:delete(pos, len)
    self.deletes = self.deletes + 1
    self.text = self.text:sub(1, pos) .. self.text:sub(pos + len + 1)
  end
  return file
end

local commands, infos, piped = {}, {}, {}
vis = { -- luacheck: ignore
  modes = { NORMAL = 1 },
  command_register = function(_, name, fn)
    commands[name] = fn
    return true
  end,
  info = function(_, msg)
    infos[#infos + 1] = msg
  end,
  pipe = function(_, cmd)
    piped[#piped + 1] = cmd
    return 0, "~/punch/inbox.md:1  # TODO x\n", ""
  end,
}
local function win(text, line)
  local w = { file = new_file(text), selection = { line = line } }
  vis.win = w
  return w
end

local plugin = dofile(root .. "/vis/punch.lua")
eq("registers commands", commands["punch-cycle"] ~= nil and commands["punch"] ~= nil, true)

-- replace_lines touches only the changed window
local f = new_file("a\nb\nc\n")
plugin.replace_lines(f, { "a", "b", "c" }, { "a", "B", "c" })
eq("replace middle", f.text, "a\nB\nc\n")
plugin.replace_lines(f, { "a", "B", "c" }, { "a", "B", "x", "c" })
eq("insert line", f.text, "a\nB\nx\nc\n")
eq("insert no delete", f.deletes, 1)
plugin.replace_lines(f, { "a", "B", "x", "c" }, { "a", "c" })
eq("delete lines", f.text, "a\nc\n")
plugin.replace_lines(f, { "a", "c" }, { "a", "c" })
eq("no-op", f.inserts, 2)
local g = new_file("# TODO a")
plugin.replace_lines(g, { "# TODO a" }, { "# DONE a", "closed: 2026-10-12T09:00" })
eq("no trailing newline", g.text, "# DONE a\nclosed: 2026-10-12T09:00\n")

-- cycle from a body line resolves to the heading and stamps closed
local w = win("# TODO a\n\nbody\n", 3)
eq("cycle ok", commands["punch-cycle"]({}, false, w), true)
eq("cycle heading", w.file.lines[1], "# DONE a")
eq("cycle stamp", w.file.lines[2]:match("^closed: %d%d%d%d%-") ~= nil, true)
eq("cycle body kept", w.file.lines[4], "body")
eq("cycle info", infos[#infos], "# DONE a")

-- toggle
w = win("- [ ] one\n- [x] two\n", 2)
eq("toggle ok", commands["punch-toggle"]({}, false, w), true)
eq("toggle line", w.file.text, "- [ ] one\n- [ ] two\n")
w = win("plain\n", 1)
eq("toggle refuses", commands["punch-toggle"]({}, false, w), false)

-- set date with shorthand
w = win("# TODO a\n\nbody\n", 3)
eq("scheduled ok", commands["punch-scheduled"]({ "2026-12-01" }, false, w), true)
eq("scheduled line", w.file.lines[2], "scheduled: 2026-12-01")
eq("deadline bad", commands["punch-deadline"]({ "whenever" }, false, w), false)

-- capture delegates to bin/punch with quoted arguments
eq("capture ok", commands["punch"]({ "call the county", "-s", "fri" }, false, w), true)
eq("capture cmd", piped[#piped], "'" .. plugin.root .. "/bin/punch' 'call the county' '-s' 'fri'")
eq("root absolute", plugin.root:sub(1, 1), "/")

-- vendored layout: init.lua beside punch/ and bin/
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p '" .. tmp .. "/punch' '" .. tmp .. "/bin' && cp '" .. plugin.root .. "'/punch/*.lua '" .. tmp
  .. "/punch/' && cp '" .. plugin.root .. "/bin/punch' '" .. tmp .. "/bin/' && cp '" .. plugin.root
  .. "/vis/punch.lua' '" .. tmp .. "/init.lua'")
local vendored = dofile(tmp .. "/init.lua")
eq("vendored root", vendored.root, tmp)
eq("vendored bin", vendored.bin, tmp .. "/bin/punch")
os.execute("rm -rf '" .. tmp .. "'")
eq("capture info", infos[#infos], "~/punch/inbox.md:1  # TODO x")
eq("capture usage", commands["punch"]({}, false, w), false)

io.write(string.format("vis: %d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
