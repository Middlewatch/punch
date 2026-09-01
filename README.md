# dl-mode

The `.dl` letter schema and its documentation, staged as its own project so
the format can evolve without being tied to the dead-letter editor's release
cadence. Two consumers exist today: the Neovim implementation at
`~/.config/nvim/lua/jake/dl/` (parser, index, agenda, cycle, registry), which
proves the schema in daily use, and the dead-letter editor at
`~/projects/dead-letter/`, which will adopt it natively once the shape settles.

## Contents

- `SCHEMA.md` — the schema itself, moved here from the dead-letter repo on
  2026-09-01. This is the document of record; dead-letter's README points here.
- `reference/` — third-party format references, cloned locally and kept out of
  git. Currently holds [neorg](https://github.com/nvim-neorg/neorg), whose
  layered, versioned spec is worth reading for how to structure a
  machine-parseable format document, even though its `.norg` format is a
  deliberate divergence from org rather than a model for dl semantics.

## Current phase

Daily-driving nvim-orgmode (installed 2026-09-01 in the Neovim config) for a
few weeks to feel real org behavior — agenda, capture, refile, repeaters —
before committing the dl schema to its equivalents. Friction observations go
to `~/dl/annoyances.dl` via the `<leader>og` gripe binding; the harvest of
that log seeds the next schema revision.
