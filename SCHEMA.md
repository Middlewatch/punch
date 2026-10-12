# The punch schema: a markdown profile for tasks, notes, and agenda

The shared data shape for punch: a CLI and a vis plugin built on one
Lua core. Files are ordinary markdown; punch recognizes a small set of
structures inside them and ignores everything else. A format change after
the Lua core ships is a rewrite of two front ends, so this document settles
the shape first.

Vocabulary is neutral throughout: entries, headings, states, fields, corpus.

Revision 2026-10-12: rebased from the org-style `.dl` format (star
headings, `.dl` extension) onto markdown. Semantics are unchanged; only the
heading sigil, the file extension, and the corpus rule moved. The reasons:
the task layer is a `TODO.md` per project, the wiki and plan documents are
already markdown, `mdq` and every renderer already understand it, and one
format for all of it beats two.

## Corpus

The corpus is a named list of paths, independent of any workspace, kept
in one data file, `corpus`, in the punch home (`$PUNCH_HOME`, default
`~/punch/`). The list is machine-local data rather than configuration:
it names what exists on this machine, so it lives beside the files it
indexes and no dotfile manager carries it. Each entry is a path:

- a directory expands recursively to every `*.md` beneath it
- a file is taken as-is

Only listed paths are in the corpus; a markdown file elsewhere on disk is
not. Normalization from entry to file set happens in exactly one place (the
indexer); no downstream tool distinguishes the two shapes. With no
`corpus` file the corpus is the punch home itself, which holds the capture
inbox (`inbox.md`) and any files that belong to no project. A project's
`TODO.md` enters the corpus by listing the file or its directory
(`punch add PATH`). The state registry (`states`) and inbox override
(`inbox`) are files in the same directory, all optional.

## File format

A punch file is UTF-8 markdown: an optional file-level field block, then
headings with their fields and body text. Anything punch does not recognize is
body text and is left alone.

```
title: Site 12 permits
#county #site-12

# TODO Call the county about the culvert permit #permits
scheduled: 2026-09-01
deadline: 2026-09-15
repeat: 2w from done

Free body text belongs to the nearest heading above it.

- [x] pull the parcel number
- [ ] confirm the fee schedule

## DONE Gather the parcel drawings
closed: 2026-08-24T19:30
```

### Headings

A heading line is: one or more `#`, a space, an optional state, title text,
and optional trailing tags. Hash count is nesting depth, markdown
convention. A `#` with no following space is never a heading start; see
Tags.

### State

State is the first token of the title position: when that token is
uppercase and matches a name in the state registry, it is the state;
otherwise the heading has no state and the token is title text. State
names are uppercase (`TODO`, `DONE`) so the rule is mechanical and states
pop visually.

States are registry data, hot-reloaded, not hardcoded. The registry defines
each state's name, whether it is open or closed, and which state is the
default open state.

### Tags

Tags are `#`-sigil tokens with no space after the sigil: `#permits`,
`#site-12`. A tag token is recognized in two places only: trailing on a
heading line, and alone on a line in the file-level block. A `#word` with
title text after it is title text; a `#word` in body text is prose. Tags
inherit downward through the subtree at index time.

The heading and tag sigils share a character and never collide: a heading
is `#` followed by a space at line start, a tag is `#` followed by a word
character.

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

Field lines above the first heading are file-level fields. They inherit
into every heading in the file under the same rules, and `title` names the
file. A trailing tag line in the file-level block applies file tags the
same way. The block may be wrapped in a pair of `---` lines (YAML front
matter as other markdown tooling writes it); the fences are ignored and the
lines between them are read as field lines, so an existing wiki note with
front matter parses without edits. Front matter values are read as plain
strings; YAML lists and nesting are not interpreted.

### Timestamps

One timestamp type: local wall time, everywhere. The surface format is
`YYYY-MM-DD` with optional `THH:MM` time (`2026-09-01`,
`2026-09-01T14:00`). Date is required, time is optional. Times are
interpreted in the machine's local zone; an explicit offset suffix is
reserved as a future escape hatch. No stored weekday; weekday is rendered
at display time.

Tools may accept shorthand on input (`+3d`, `fri`, `next mon`, `oct 15`)
but always write the surface format. Shorthand never appears in a file.

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
`- [ ]` (open) or `- [x]` (done) is a checkbox item. They are the
lightweight task form: a checkbox needs no heading, no state, and no
fields, and belongs to the nearest heading above it (or to the file when
there is none). A project `TODO.md` can be nothing but checkboxes and still
be in the corpus; the agenda lists open checkboxes under their file and
heading.

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
agenda queries (today, scheduled, deadline, tag, open checkboxes),
backlinks, dangling-link and duplicate-id reports. Files are the source of
truth; the index is never authoritative, and no process holds it between
invocations: the CLI rebuilds it per run and the editor plugin rebuilds it
on demand. There is no daemon.

## Deferred, additive by design

These need no grammar change when they arrive: priorities (`priority:`
field), deadline warning lead time (`warn:` duration field), archiving
(subfolder convention plus a field), dependencies and ordering
(`depends-on:` multi-value field), clocking (repeated range-valued `clock:`
field).
