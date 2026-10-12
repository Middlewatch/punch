-- Plain-Lua test runner for the punch core: lua test/run.lua from the repo
-- root (make test). No framework; each check prints on failure and the
-- process exits non-zero if any failed.
local root = (arg[0]:match("^(.*)/test/run%.lua$")) or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local punch = require("punch")
local parser, dates, index, edit, registry = punch.parser, punch.dates, punch.index, punch.edit, punch.registry

local failed, passed = 0, 0
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "") .. "\n")
  end
end
local function eq(name, got, want)
  check(name, got == want, "got " .. tostring(got) .. " want " .. tostring(want))
end

local states = registry.parse_states(nil)
local fixtures = root .. "/test/fixtures"
local permits = punch.util.read_lines(fixtures .. "/permits.md")

-- parser -------------------------------------------------------------------
do
  local f = parser.parse(permits, states)
  eq("file title", f.fields.title, "Site 12 permits")
  eq("file tags", table.concat(f.tags, ","), "county,site-12")
  eq("entry count", #f.entries, 4)
  local e = f.entries[1]
  eq("state", e.state, "TODO")
  eq("title", e.title, "Call the county about the culvert permit")
  eq("tags", table.concat(e.tags, ","), "permits")
  eq("scheduled", e.fields.scheduled, "2026-09-01")
  eq("fields_end", e.fields_end, 7)
  eq("subtree_end", e.subtree_end, 16)
  eq("depth2 subtree_end", f.entries[2].subtree_end, 16)
  eq("checkboxes", #f.checkboxes, 2)
  eq("checkbox done", f.checkboxes[1].done, true)
  eq("checkbox text", f.checkboxes[2].text, "confirm the fee schedule")
  eq("checkbox owner", f.checkboxes[2].entry, e)
  eq("stateless heading", f.entries[3].state, nil)
  eq("stateless title", f.entries[3].title, "Plain heading with no state")
  eq("links", #f.links, 1)
  eq("link target", f.links[1].target, "notes")
  eq("entry_at body", parser.entry_at(f, 10), e)

  local n = parser.parse(punch.util.read_lines(fixtures .. "/notes.md"), states)
  eq("front matter title", n.fields.title, "notes")
  eq("front matter entries", #n.entries, 1)
  eq("front matter links", #n.links, 4)
  eq("id link", n.links[2].id, "child-1")
  eq("heading link", n.links[1].heading, "Call the county about the culvert permit")

  -- a tag-only line is not a heading, a heading is not a tag
  local t = parser.parse({ "#tag", "# TODO Title #x", "#notatag text" }, states)
  eq("tag line", t.tags[1], "tag")
  eq("tag line not heading", #t.entries, 1)
end

-- dates --------------------------------------------------------------------
do
  eq("ts date", dates.format_timestamp(dates.parse_timestamp("2026-02-28")), "2026-02-28")
  eq("ts time", dates.format_timestamp(dates.parse_timestamp("2026-02-28T09:05")), "2026-02-28T09:05")
  eq("ts invalid", dates.parse_timestamp("2026-02-30"), nil)
  local r = dates.parse_repeat("2w from done")
  eq("repeat count", r.count, 2)
  eq("repeat anchor", r.anchor, "done")
  eq("repeat pin", dates.parse_repeat("1m on 31").pin, 31)
  eq("repeat bad", dates.parse_repeat("2x"), nil)
  local function adv(ts, rep, now)
    return dates.format_timestamp(dates.advance(dates.parse_timestamp(ts), dates.parse_repeat(rep), now))
  end
  eq("month clamp", adv("2026-01-31", "1m", nil), "2026-02-28")
  eq("pin survives clamp", adv("2026-02-28", "1m on 31", nil), "2026-03-31")
  local now = { year = 2026, month = 10, day = 12, hour = 9, min = 0 } -- a Monday
  eq("from done", adv("2026-09-01T14:00", "2w from done", now), "2026-10-26T14:00")
  eq("from due", adv("2026-09-01", "2w", now), "2026-09-15")
  local function sh(v) local ts = dates.parse_shorthand(v, now); return ts and dates.format_timestamp(ts) end
  eq("sh today", sh("today"), "2026-10-12")
  eq("sh tomorrow", sh("tomorrow"), "2026-10-13")
  eq("sh +3d", sh("+3d"), "2026-10-15")
  eq("sh +1w", sh("+1w"), "2026-10-19")
  eq("sh +1m", sh("+1m"), "2026-11-12")
  eq("sh fri", sh("fri"), "2026-10-16")
  eq("sh next mon", sh("next mon"), "2026-10-19")
  eq("sh mon wraps", sh("mon"), "2026-10-19")
  eq("sh oct 15", sh("oct 15"), "2026-10-15")
  eq("sh past month rolls", sh("jan 5"), "2027-01-05")
  eq("sh time", sh("fri 14:30"), "2026-10-16T14:30")
  eq("sh surface", sh("2026-12-01"), "2026-12-01")
  eq("sh junk", sh("whenever"), nil)
end

-- index --------------------------------------------------------------------
do
  local scan = index.scan({ fixtures }, states)
  eq("scan files", #scan.files, 2)
  eq("scan entries", #scan.entries, 5)
  local child
  for _, e in ipairs(scan.entries) do
    if e.title == "Child inherits owner and plain tag" then child = e end
  end
  eq("inherit field", child.fields.owner, "jake")
  eq("inherit tags", table.concat(child.tags, ","), "county,site-12,plain")
  eq("reserved not inherited", child.fields.scheduled, nil)
  eq("own_fields", child.own_fields.owner, nil)
  local today = index.today(scan.entries, states, { year = 2026, month = 10, day = 12 })
  eq("today count", #today, 2)
  eq("today order", today[1].title, "Call the county about the culvert permit")
  eq("today none yet", #index.today(scan.entries, states, { year = 2026, month = 8, day = 1 }), 0)
  eq("deadline list", #index.deadline(scan.entries, states), 2)
  eq("tagged", #index.tagged(scan.entries, states, "plain"), 1)
  eq("tagged closed excluded", #index.tagged(scan.entries, states, "county"), 2)
  eq("open checkboxes", #index.open_checkboxes(scan.checkboxes), 2)
  local report = index.check(scan)
  eq("dangling", #report.dangling, 2)
  eq("dangling first", report.dangling[1].file, fixtures .. "/notes.md")
  eq("duplicate ids", #report.duplicate_ids, 0)
end

-- edit ---------------------------------------------------------------------
do
  local now = { year = 2026, month = 10, day = 12, hour = 9, min = 30 }
  eq("toggle on", edit.toggle_checkbox("- [ ] x"), "- [x] x")
  eq("toggle off", edit.toggle_checkbox("  - [x] x"), "  - [ ] x")
  eq("toggle non", edit.toggle_checkbox("plain"), nil)

  local cap = edit.capture({ "# TODO first" }, { title = "second", tags = { "a", "b" }, scheduled = "2026-10-15" })
  eq("capture", table.concat(cap, "|"), "# TODO first||# TODO second #a #b|scheduled: 2026-10-15")
  eq("capture empty", table.concat(edit.capture({}, { title = "x" }), "|"), "# TODO x")

  local sf = edit.set_field({ "# TODO a", "scheduled: 2026-01-01", "", "body" }, 4, "deadline", "2026-02-02", states)
  eq("set_field insert", sf[3], "deadline: 2026-02-02")
  local sf2 = edit.set_field(sf, 1, "scheduled", "2026-03-03", states)
  eq("set_field replace", sf2[2], "scheduled: 2026-03-03")
  eq("set_field len", #sf2, 5)

  -- cycle: plain close, reopen, remove state, back to TODO
  local c1 = edit.cycle({ "# TODO a", "", "body" }, 1, states, now)
  eq("close heading", c1[1], "# DONE a")
  eq("close stamp", c1[2], "closed: 2026-10-12T09:30")
  local c2 = edit.cycle(c1, 1, states, now)
  eq("cycle past last removes state", c2[1], "# a")
  eq("reopen drops stamp", c2[2], "")
  local c3 = edit.cycle(c2, 1, states, now)
  eq("cycle around", c3[1], "# TODO a")
  eq("cycle non-heading", edit.cycle({ "text" }, 1, states, now), nil)

  -- cycle: repeating entry advances in place and keeps the state open
  local rep = { "# TODO meds", "scheduled: 2026-10-10T08:00", "repeat: 1d from done", "", "body" }
  local r1 = edit.cycle(rep, 1, states, now)
  eq("repeat state stays", r1[1], "# TODO meds")
  eq("repeat advanced", r1[2], "scheduled: 2026-10-13T08:00")
  eq("repeat history", r1[4], "closed: 2026-10-12T09:30")
  eq("repeat body intact", r1[6], "body")

  -- cut / paste / refile across files
  local remaining, block = edit.cut(permits, 4, states)
  eq("cut block len", #block, 12)
  eq("cut block first", block[1], "# TODO Call the county about the culvert permit #permits")
  eq("cut remaining first heading", remaining[4], "# Plain heading with no state #plain")
  local dst = { "# Inbox triage" }
  local pasted = edit.paste(dst, block, 1, states)
  eq("paste depth", pasted[3], "## TODO Call the county about the culvert permit #permits")
  eq("paste child depth", pasted[13], "### DONE Gather the parcel drawings")
  eq("paste blank sep", pasted[2], "")
  local top = edit.paste({ "## deep" }, { "### x", "#### y" }, nil, states)
  eq("paste top rebases", top[3] .. "|" .. top[4], "# x|## y")

  local src2, dst2 = edit.refile(permits, 4, dst, nil, states)
  eq("refile src shrinks", #src2, #permits - 13)
  eq("refile dst grows", dst2[3], "# TODO Call the county about the culvert permit #permits")

  -- same-file refile: move the child under the first heading
  local same = { "# A", "", "# B", "", "## C", "body" }
  local s1 = edit.refile(same, 3, same, 1, states)
  eq("same-file", table.concat(s1, "|"), "# A||## B||### C|body")
  local same2 = { "# A", "", "# B", "", "## C" }
  local s2 = edit.refile(same2, 1, same2, 3, states)
  eq("same-file forward", table.concat(s2, "|"), "# B||## C||## A")
  eq("refile into own subtree", edit.refile(same2, 3, same2, 5, states), nil)
end

io.write(string.format("%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
