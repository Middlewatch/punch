# punch

A punch list is the items left to close out. punch is a CLI and a vis plugin
over one Lua core that reads tasks, notes, and agenda data out of ordinary
markdown files: stated headings, trailing `#tags`, `key: value` fields,
checkboxes, and wiki links. Everything else in a file is prose and is left
alone. Files are the only state; there is no database and no daemon.

## Contents

- `SCHEMA.md`: the format of record, a markdown profile. Rebased from the
  earlier org-style `.dl` format on 2026-10-12; semantics unchanged.
- `PLAN.md`: decisions, architecture, and slices.
- `punch/`: the Lua 5.4 core (parser, corpus, index, dates, edit, registry).
  Plain Lua with no C modules so the same code runs under `lua` and inside
  vis. `require("punch")` loads every module.
- `bin/punch`: the CLI. `punch "text"` captures to the inbox; `agenda`,
  `list`, `inbox`, `done`, `refile`, `check` read and edit the corpus
  listed in `~/.config/punch/corpus`. `punch help` has the flags.
  `make install` symlinks it into `~/.local/bin`.
- `test/`: plain-Lua tests over fixture files plus a shell run of every
  CLI verb against a throwaway corpus. `make test`, `make lint` (luacheck).
- `reference/`: third-party format references, cloned locally and kept out
  of git (neorg's layered spec, worth reading for how to structure a
  machine-parseable format document).

## Status

Slices 1 (library port) and 2 (CLI) landed 2026-10-12. Next: the vis
plugin (PLAN.md slice 3).
The earlier Neovim implementation at `~/.config/nvim/lua/jake/dl/` was the
port source and is not maintained.
