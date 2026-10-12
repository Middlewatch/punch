-- Timestamps, recurrence, and input shorthand. Surface form is
-- YYYY-MM-DD with optional THH:MM, local wall time (SCHEMA.md). Shorthand is
-- accepted on input only and always normalized to the surface form.
local util = require("punch.util")

local M = {}

local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function M.month_days(year, month)
  if month == 2 and (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) then
    return 29
  end
  return days_in_month[month]
end

-- Returns { year, month, day, has_time, hour?, min? } or nil.
function M.parse_timestamp(value)
  if type(value) ~= "string" then
    return nil
  end
  local y, m, d, h, min = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)$")
  local has_time = y ~= nil
  if not y then
    y, m, d = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  end
  if not y then
    return nil
  end
  local ts = { year = tonumber(y), month = tonumber(m), day = tonumber(d), has_time = has_time }
  if ts.month < 1 or ts.month > 12 or ts.day < 1 or ts.day > M.month_days(ts.year, ts.month) then
    return nil
  end
  if has_time then
    ts.hour, ts.min = tonumber(h), tonumber(min)
    if ts.hour > 23 or ts.min > 59 then
      return nil
    end
  end
  return ts
end

function M.format_timestamp(ts)
  if ts.has_time then
    return string.format("%04d-%02d-%02dT%02d:%02d", ts.year, ts.month, ts.day, ts.hour, ts.min)
  end
  return string.format("%04d-%02d-%02d", ts.year, ts.month, ts.day)
end

function M.datenum(ts)
  return ts.year * 10000 + ts.month * 100 + ts.day
end

-- Wall clock as a timestamp table; tests inject their own.
function M.now()
  local t = os.date("*t")
  return { year = t.year, month = t.month, day = t.day, has_time = true, hour = t.hour, min = t.min }
end

-- Date plus a number of days, normalized through os.time.
local function add_days(ts, days)
  local moved = os.date("*t", os.time({ year = ts.year, month = ts.month, day = ts.day + days, hour = 12 }))
  return { year = moved.year, month = moved.month, day = moved.day }
end

local function add_months(ts, months, pin)
  local total = ts.year * 12 + (ts.month - 1) + months
  local y = math.floor(total / 12)
  local m = total % 12 + 1
  local d = math.min(pin or ts.day, M.month_days(y, m))
  return { year = y, month = m, day = d }
end

-- "2w", "2w from done", "1m on 31", "1m on 31 from due". Returns
-- { count, unit, anchor = "done"|"due", pin? } or nil. Bare interval means
-- from due.
function M.parse_repeat(value)
  if type(value) ~= "string" then
    return nil
  end
  local tokens = util.split_ws(value)
  local count, unit = (tokens[1] or ""):match("^(%d+)([dwmy])$")
  if not count or tonumber(count) < 1 then
    return nil
  end
  local spec = { count = tonumber(count), unit = unit, anchor = "due" }
  local i = 2
  while i <= #tokens do
    local word, arg = tokens[i], tokens[i + 1]
    if word == "from" and (arg == "done" or arg == "due") then
      spec.anchor = arg
    elseif word == "on" and tonumber(arg) and tonumber(arg) >= 1 and tonumber(arg) <= 31 then
      spec.pin = tonumber(arg)
    else
      return nil
    end
    i = i + 2
  end
  return spec
end

-- Next occurrence for one date field: interval after the completion date
-- (from done) or after the field's own date (from due). Month and year
-- intervals clamp to month-end for that occurrence only; a day pin fixes the
-- nominal day. Time of day is kept from the original.
function M.advance(ts, spec, now)
  local base = spec.anchor == "done" and now or ts
  local moved
  if spec.unit == "d" or spec.unit == "w" then
    moved = add_days(base, spec.count * (spec.unit == "w" and 7 or 1))
  else
    moved = add_months(base, spec.count * (spec.unit == "y" and 12 or 1), spec.pin)
  end
  moved.has_time, moved.hour, moved.min = ts.has_time, ts.hour, ts.min
  return moved
end

local weekdays = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }
local months = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
                 jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }

local function weekday_of(ts)
  return os.date("*t", os.time({ year = ts.year, month = ts.month, day = ts.day, hour = 12 })).wday
end

-- Input shorthand, relative to now (a timestamp table). Accepted: the
-- surface form itself; today, tomorrow; +Nd +Nw +Nm +Ny; a weekday name
-- (first occurrence strictly after today; "next" prefix is an alias); a
-- month name and day (this year, or next year once past). A trailing HH:MM
-- adds a time. Returns a timestamp table or nil.
function M.parse_shorthand(value, now)
  if type(value) ~= "string" then
    return nil
  end
  local tokens = util.split_ws(value:lower())
  if #tokens == 0 then
    return nil
  end
  local hour, min
  local last = tokens[#tokens]
  local h, mi = last:match("^(%d%d?):(%d%d)$")
  if h then
    hour, min = tonumber(h), tonumber(mi)
    if hour > 23 or min > 59 then
      return nil
    end
    table.remove(tokens)
  end
  if tokens[1] == "next" then
    table.remove(tokens, 1)
  end
  local word = tokens[1]
  if not word then
    return nil
  end
  local ts
  local surface = M.parse_timestamp(value)
  if surface then
    return surface
  elseif #tokens == 1 and M.parse_timestamp(word) then
    ts = M.parse_timestamp(word)
  elseif word == "today" then
    ts = { year = now.year, month = now.month, day = now.day }
  elseif word == "tomorrow" then
    ts = add_days(now, 1)
  elseif word:match("^%+%d+[dwmy]$") then
    local n, unit = word:match("^%+(%d+)([dwmy])$")
    n = tonumber(n)
    if unit == "d" then
      ts = add_days(now, n)
    elseif unit == "w" then
      ts = add_days(now, 7 * n)
    elseif unit == "m" then
      ts = add_months(now, n)
    else
      ts = add_months(now, 12 * n)
    end
  elseif weekdays[word:sub(1, 3)] and #tokens == 1 then
    local target = weekdays[word:sub(1, 3)]
    local delta = (target - weekday_of(now)) % 7
    if delta == 0 then
      delta = 7
    end
    ts = add_days(now, delta)
  elseif months[word:sub(1, 3)] and tokens[2] and tokens[2]:match("^%d%d?$") then
    local m, d = months[word:sub(1, 3)], tonumber(tokens[2])
    local y = now.year
    if m < now.month or (m == now.month and d < now.day) then
      y = y + 1
    end
    if d < 1 or d > M.month_days(y, m) then
      return nil
    end
    ts = { year = y, month = m, day = d }
  else
    return nil
  end
  if hour then
    ts.has_time, ts.hour, ts.min = true, hour, min
  else
    ts.has_time = ts.has_time or false
  end
  return ts
end

return M
