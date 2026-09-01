# The .dl letter schema

The shared data shape for dead letter's org-mode replacement. Neovim is the
first consumer and proves the schema before dead letter adopts it natively;
a format change after that point is a rewrite of both tools, so this document
settles the shape first.

Vocabulary is neutral throughout: entries, headings, states, fields, corpus.

## Corpus

The corpus is a named list of paths, independent of any workspace, configured
in one data file. Each entry is a path:

- a directory expands recursively to every `*.dl` beneath it
- a file is taken as-is

Normalization from entry to file set happens in exactly one place (the
indexer); no downstream tool distinguishes the two shapes. The default corpus
root is `~/dl/`.

## File format

A `.dl` file is UTF-8 plain text: an optional file-level field block, then
headings with their fields and body text.

```
title: Site 12 permits
#county #site-12

* TODO Call the county about the culvert permit #permits
  scheduled: 2026-09-01
  deadline: 2026-09-15
  repeat: 2w from done

  Free body text belongs to the nearest heading above it.

  - [x] pull the parcel number
  - [ ] confirm the fee schedule

** DONE Gather the parcel drawings
   closed: 2026-08-24T19:30
```

### Headings

A heading line is: one or more `*`, a space, an optional state, title text,
and optional trailing tags. Star count is nesting depth, org convention.

### State

State is the first token of the title position: when that token is uppercase
and matches a name in the state registry, it is the state; otherwise the
heading has no state and the token is title text. State names are uppercase
(`TODO`, `DONE`) so the rule is mechanical and states pop visually.

States are registry data, hot-reloaded, not hardcoded. The registry defines
each state's name, whether it is open or closed, and which state is the
default open state.

### Tags

Tags are `#`-sigil tokens at the end of the heading line: `#permits #site`.
Only trailing tokens are tags; a `#word` with title text after it is title
text. Tags inherit downward through the subtree at index time.

### Fields

A field line is `key: value` where key matches `[a-z][a-z0-9-]*`. Fields are
the contiguous run of field lines directly after a heading; the first blank
line or non-field line starts the body, and no field lines are recognized
after that. Capitalized body text like `Note: something` is therefore never
a field.

Fields are typed: the type registry maps key to type (timestamp, duration,
string, number, list). Unknown keys index as strings.

A repeated key is a multi-value field: all values are kept, indexed as a
list in file order.

Non-reserved fields inherit downward through the subtree at index time; a
child's own field overrides the inherited value. Reserved fields never
inherit: `scheduled`, `deadline`, `closed`, `repeat`, and `id` describe
exactly one entry.

Field lines above the first heading are file-level fields. They inherit into
every heading in the file under the same rules, and `title` names the file.
A trailing tag line in the file-level block applies file tags the same way.

### Timestamps

One timestamp type: local wall time, everywhere. The surface format is
`YYYY-MM-DD` with optional `THH:MM` time (`2026-09-01`,
`2026-09-01T14:00`). Date is required, time is optional. Times are
interpreted in the machine's local zone; an explicit offset suffix is
reserved as a future escape hatch. No stored weekday; weekday is rendered
at display time.

`scheduled` and `deadline` are distinct fields with distinct meanings:
scheduled is when work starts appearing on the agenda, deadline is when it
is late.

### Recurrence

Recurrence is a minimal interval algebra: a positive integer and a unit
(`d`, `w`, `m`, `y`), in a `repeat` field separate from the timestamp.

Both anchor semantics exist:

- repeat from completion: the next occurrence is interval after the entry
  was closed
- repeat from due: the next occurrence is interval after the current
  scheduled/deadline date, keeping the cadence regardless of when the work
  happened

The anchors are written in plain words: `repeat: 2w from done` and
`repeat: 2w from due`. A bare `repeat: 2w` means from due.

Advancement moves only the date; a timed field keeps its time of day
under either anchor. From done exists for cadences like medication,
where a late completion shifts the next date but the target time stays
put; changing the target time is a deliberate manual edit.

Month and year intervals preserve the scheduled day-of-month; when the
target month is shorter, the date clamps to month-end for that occurrence
only. An optional day pin, `repeat: 1m on 31`, fixes the nominal day so a
clamp never rewrites intent; `on 31` doubles as "last day of every month".

Closing a repeating entry advances it in place: no clone is created, the
scheduled and deadline dates move per the anchor rule, the state resets to
the registry's default open state, and a `closed:` line is appended per
completion, so the repeated field is the completion history.

### Body

Body text is free text and is not indexed for dates: only fields feed the
agenda. Timestamps typed in prose are just prose.

Checkbox lines are the one recognized body structure: a list line matching
`- [ ]` (open) or `- [x]` (done) is a checkbox item, reserved now so later
tooling support does not reinterpret existing prose.

### Links

Links are wiki style, in three forms:

- `[[file]]` links to a corpus file
- `[[file#heading text]]` links to a heading in that file by title
- `[[#id]]` links to the heading whose `id` field matches, wherever it
  lives; ids are corpus-unique, so id links survive file renames and
  headings moving between files

A `#` immediately after `[[` always means an id lookup; a file part always
means a title match. The `id` field is optional and assigned only when a
heading needs a stable target. The index derives backlinks and
dangling-link reports from all three forms.

## Index

The index is derived, disposable state built by scanning the corpus. It owns
normalization (corpus entries to file sets), tag and field inheritance,
agenda queries (today, scheduled, deadline, tag), backlinks, dangling-link
and duplicate-id reports. Files are the source of truth; the index is never
authoritative.

## Deferred, additive by design

These need no grammar change when they arrive: priorities (`priority:`
field), deadline warning lead time (`warn:` duration field), archiving
(subfolder convention plus a field), dependencies and ordering
(`depends-on:` multi-value field), clocking (repeated range-valued `clock:`
field).
