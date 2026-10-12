# punch plan: one Lua core, a CLI, and a vis plugin

Status: planning, 2026-10-12. SCHEMA.md is the format of record; this file
holds the decisions, architecture, and slices for the tools that read it.

## Goal

Capture a thought from any terminal in one command, triage the inbox in
vis, keep a `TODO.md` beside each project, and see one agenda across all of
it. Markdown files are the only state. Success means the owner uses it
daily for two weeks without opening a database, a daemon, or Emacs.

## Decisions

- **D1. Markdown profile.** The punch schema is a profile over markdown
  (SCHEMA.md, revision 2026-10-12). Project task files are `TODO.md`.
- **D2. One Lua core, two front ends.** Parser, index, agenda, and refile
  live in a Lua 5.4 library. The CLI is a Lua script; the vis plugin
  `require`s the same library. Zig is not involved: it is reserved for a
  future editor and has no role in a text-munging tool whose host editor
  already embeds Lua.
- **D3. No daemon.** Each invocation rebuilds the index from the corpus.
  orgd's lease protocol existed because a daemon and an editor both held
  the file; with no daemon the editor owns an open buffer and the CLI owns
  nothing. If a corpus grows large enough that a rebuild per run hurts, a
  cache file keyed by mtime is the additive fix.
- **D4. Separate corpora, one format.** Tasks (`~/projects/*/TODO.md`),
  notebook (`~/notes/` or wherever), and inbox (`~/punch/inbox.md`) are
  separate corpus entries. The agenda is the only join. Calendar is the
  agenda filtered to `scheduled` and `deadline`; no notification or
  external calendar integration.
- **D5. Name: `punch`.** Decided 2026-10-12: a punch list is the items left to close out, and the hit reading fits capture. The repo, the schema, and the
  library namespace all carry the name; `dl-mode` was retired with it.

## Prior work and what it taught

- `~/.config/nvim/lua/jake/dl/` (636 lines: parser, index, agenda, cycle,
  registry). The port source. Pure Lua except for the Neovim glue; the
  parser's heading pattern changes from `^(%*+) (.*)$` to a hash form and
  the corpus glob from `*.dl` to listed `*.md`.
- orgd (`~/intake/desktop/orgd`, temporary): JSON-RPC daemon over headless
  Emacs with D-Bus surfaces, 7.6k lines of Zig. Kept from it: files are
  truth, stateless restartable, capture as a declared template rather
  than free-form flags. Rejected: the daemon, the Emacs oracle, the
  desktop surfaces, clocking.
- dead-letter and stormglass (same intake directory): editor archives.
  Nothing format-related to carry; the dl schema already moved out of
  dead-letter on 2026-09-01.
- The nvim-orgmode dogfood phase the old README planned never produced its
  gripe log (`~/dl/annoyances.dl` does not exist). The dogfood happens on
  the Lua tools instead.

## Architecture

```
punch/         Lua library (the core); require("punch") loads all
  parser.lua   lines -> raw entries (headings, fields, checkboxes, links)
  corpus.lua   corpus file -> list of markdown paths
  index.lua    inheritance, agenda queries, backlinks, id table
  dates.lua    timestamp parse/format, shorthand -> surface form, repeat
  edit.lua     text transforms on a file's lines: append capture,
               cut/paste an entry (refile), cycle state, set field
  registry.lua states, corpus, inbox path from ~/.config/punch/
  util.lua     trim, split, file io, shell quoting
bin/punch     CLI entry, argument parsing only, calls the library
vis/punch.lua vis plugin, key maps and commands only, calls the library
```

The rule that keeps the two front ends honest: every mutation is a
function in `edit.lua` that takes and returns a table of lines. The CLI
reads a file, applies it, writes the file. The vis plugin applies the same
function to the buffer's lines through `vis.win.file`. Neither front end
contains format knowledge.

### CLI surface (verbs, subject to the name)

- `punch "text"`: append a `# TODO text` entry to the inbox. Unquoted
  words join; a first word that is also a verb needs quotes or `--`. Flags
  `-t tag` (repeatable), `-s date`, `-d date`, `-r spec` set tags,
  `scheduled`, `deadline`, `repeat`; dates accept shorthand and are written
  in surface form. With `-f file` the entry goes straight to that corpus
  file instead of the inbox. No flags, no prompt: capture must be one line
  and done.
- `punch agenda [today|week|all]`: scheduled and deadline entries across
  the corpus, late items first, then open checkboxes by file.
- `punch list [#tag] [STATE]`: filtered entry list with file:line; open
  entries unless a state is named.
- `punch refile <file:line> <target-file> [heading]`: move an entry and
  its subtree; the heading matches exactly or as a unique substring, and a
  missing target file is created.
- `punch done <file:line>`: cycle state; advances a repeating entry. Any
  line of the entry resolves to its heading, so agenda output pastes back.
- `punch inbox`: count and list of inbox entries, the triage prompt.
- `punch check`: dangling links, duplicate ids, malformed date and repeat
  fields; exit 1 when anything is listed.

### vis plugin surface

Facts checked in `~/projects/vis/vis-lua.c` on 2026-10-12: the Lua API
exposes `vis:map`, `vis:command_register`, `vis:pipe`, `vis:communicate`,
`vis:message`, `vis:info`, `vis:feedkeys`, and the `win.file` line table.
There is no prompt or input primitive, so interactive input comes from two
existing patterns: a registered `:` command with arguments (what
`vis-lspc` does), and piping choices through `vis-menu` (what `vis-open`
does; `vis-menu` is on PATH at `~/.local/bin/vis-menu`).

- Leader+t on a selection or the current entry: refile. The plugin lists
  corpus files through `vis-menu`, then headings in the chosen file, then
  calls `edit.refile`. A path typed instead of picked creates the file.
- Leader+d: cycle state on the entry under the cursor.
- Leader+s / leader+e: set `scheduled` / `deadline` via a `:` command that
  accepts shorthand.
- `:punch agenda`: open the agenda as a read-only buffer with file:line
  targets; Enter jumps.
- Inbox triage is "open `inbox.md`, leader+t on each entry."

### Dates

Shorthand accepted on input: `+Nd/+Nw/+Nm`, weekday names (next
occurrence), `next <weekday>`, `today`, `tomorrow`, `<mon> <day>`. A
calendar picker is not planned; revisit only if shorthand fails in use.

## Slices

1. Library port (done 2026-10-12): the five nvim modules into `punch/`, swap the heading
   pattern and corpus rule, add `dates.lua` shorthand and `edit.lua`. Tests
   are plain `lua` scripts over fixture files in `test/`, run by `make
   test`; no test framework.
2. CLI (done 2026-10-12): all seven verbs in `bin/punch`, checked end to
   end by `test/cli.sh` under a throwaway HOME. `make install` symlinks it
   into `~/.local/bin`; move to the chezmoi `dot_local/bin` path once
   stable.
3. vis plugin: refile and cycle first, agenda buffer second. Lives in
   `~/.config/vis/plugins/punch/` beside `vis-lspc`.
4. Corpus seeding: `~/punch/inbox.md`, `TODO.md` in the active projects,
   `followup-items.md` from the chezmoi repo folded into its `TODO.md`.
5. Two-week dogfood with a gripe heading in the inbox; harvest feeds the
   next schema revision.

## Open items

- Where the corpus data file lives: `~/.config/punch/corpus` is the
  obvious XDG answer; it is machine-specific, so chezmoi templates it.
- Whether `TODO.md` is committed or lives in `<slug>/.local/`; per-project
  choice, default committed for public projects.
