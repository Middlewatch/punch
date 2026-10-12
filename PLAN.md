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
- **D6. punch owns its lists; chezmoi carries nothing.** Decided
  2026-10-12. The corpus list names what exists on one machine, so it is
  data, not configuration: it lives at `~/punch/corpus` beside the inbox
  (`$PUNCH_HOME` relocates the whole directory), and `punch add PATH`
  writes it. The state registry is the same kind of file in the same
  place and has no reason to travel while the defaults serve. The CLI
  installs from `bin/install`; the vis plugin is vendored into the vis
  config like any other plugin. If a setting that must be identical on
  every machine ever appears, that one file goes to chezmoi then.

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
  registry.lua states, corpus, inbox path from ~/punch/ ($PUNCH_HOME)
  util.lua     trim, split, file io, shell quoting
bin/punch     CLI entry, argument parsing only, calls the library
vis/punch.lua vis plugin: :punch delegates capture to bin/punch; cycle,
              toggle, scheduled, deadline apply edit.* to the buffer
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
- `punch add PATH...`: append to the corpus in `~` form, skipping paths
  already listed; a missing path is noted and joins when created.
- `punch corpus`: one row per corpus entry with files, open entries, open
  checkboxes, and late entries: the by-project view beside the agenda's
  by-date view.

### vis plugin surface

Decided 2026-10-12: vis is not an editor the owner lives inside, so the
agenda, list, inbox, and check views stay in the CLI; vis gets capture
(an idea mid-edit) and the edits that are better made in the buffer than
by `punch done FILE:LINE` after a save. Refile stays in the CLI until the
dogfood says otherwise. No default key maps; visrc binds the functions
under its own leader groups.

Facts checked in `~/projects/vis/vis-lua.c` on 2026-10-12: `file.lines[i]`
reads and replaces one line, `file:insert(pos, text)` and
`file:delete(pos, len)` take byte offsets, `#file.lines` ignores the
trailing newline, `vis:pipe(cmd)` returns status, stdout, stderr, and a
`:` command handler receives `(argv, force, win, selection, range)`. There
is no prompt primitive; the `:` line is the prompt.

- `:punch TEXT... [flags]`: capture. Every argument goes to `bin/punch`
  unchanged, so the CLI's flags and date shorthand apply; the CLI's
  one-line result shows in the status line.
- `:punch-cycle`: `edit.cycle` on the entry at or above the cursor.
- `:punch-toggle`: `edit.toggle_checkbox` on the cursor line.
- `:punch-scheduled DATE` / `:punch-deadline DATE`: `edit.set_field` with
  shorthand on the entry at or above the cursor.

The buffer glue reads `win.file.lines` into a table, applies the edit
function, and writes back only the window of lines that changed, so undo
holds one step and the cursor stays put. The plugin finds the library
through `$PUNCH_ROOT`, a `punch/` directory beside its own file (the
vendored layout), or the directory above `vis/` (the repo).

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
   end by `test/cli.sh` under a throwaway HOME. `bin/install [PREFIX]`
   installs it the way the vis and tmux forks do (CLI in `PREFIX/bin`,
   core in `PREFIX/share/punch`); chezmoi does not deploy the CLI.
3. vis plugin (done 2026-10-12): `vis/punch.lua` in this repo, checked by
   `test/vis.lua` against a stub of the vis API. Deployed the way vis-lspc
   is: `make vendor` copies plugin and library into the chezmoi source
   as `~/.config/vis/plugins/punch/` with a `VENDORED.md`, visrc loads
   `require("plugins/punch")` and binds the `Space n` group. Capture
   runs the installed `punch` from PATH.
4. Corpus seeding (done 2026-10-12): `~/punch/inbox.md`, `~/punch/corpus`
   listing the chezmoi repo's `TODO.md` (folded from `followup-items.md`)
   and pkgit's. Further projects join one at a time with `punch add`.
5. Two-week dogfood; gripes are captured as `punch "..." -t gripe` and
   read back with `punch list '#gripe'`, so no extra file or heading.
   Harvest feeds the next schema revision.

## Open items

- Whether `TODO.md` is committed or lives in `<slug>/.local/`; per-project
  choice, default committed for public projects.
