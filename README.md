# dl-mode

The dl schema and the plan for the tools that read it. dl is a markdown
profile: ordinary `.md` files in which a small set of structures (stated
headings, trailing `#tags`, `key: value` fields, checkboxes, wiki links)
carry tasks, notes, and agenda data. Everything else in the file is prose
and is left alone.

## Contents

- `SCHEMA.md`: the format of record. Rebased from the org-style `.dl`
  format onto markdown on 2026-10-12; semantics unchanged.
- `PLAN.md`: decisions, architecture, and slices for the tools: one Lua
  core shared by a CLI and a vis plugin, no daemon, files as the only state.
- `reference/`: third-party format references, cloned locally and kept out
  of git. Currently holds [neorg](https://github.com/nvim-neorg/neorg), whose
  layered, versioned spec is worth reading for how to structure a
  machine-parseable format document.

## Consumers

- The Lua core, CLI, and vis plugin described in `PLAN.md` (not yet built).
- `~/.config/nvim/lua/jake/dl/`: the earlier Neovim implementation of the
  `.dl` form (parser, index, agenda, cycle, registry). It is the port
  source for the Lua core and is not maintained as a consumer.

## Current phase

Planning closed 2026-10-12 (D1 markdown profile, D2 Lua core). Next slice is
the library port, PLAN.md slice 1. The tool name is still open.
