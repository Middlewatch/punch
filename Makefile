LUA ?= lua
BINDIR ?= $(HOME)/.local/bin
CHEZMOI_SRC ?= $(shell chezmoi source-path)
VENDOR = $(CHEZMOI_SRC)/dot_config/vis/plugins/punch

.PHONY: test lint install vendor

test:
	$(LUA) test/run.lua
	$(LUA) test/vis.lua
	bash test/cli.sh

lint:
	luacheck punch vis test bin/punch

install:
	ln -sf $(CURDIR)/bin/punch $(BINDIR)/punch

# Plain copy of the plugin, library, and CLI into the chezmoi source as
# ~/.config/vis/plugins/punch (loaded by require("plugins/punch")), the way
# vis-lspc is vendored. Rerun after a change here, then chezmoi apply.
vendor:
	rm -rf $(VENDOR)/punch $(VENDOR)/bin
	mkdir -p $(VENDOR)/punch $(VENDOR)/bin
	cp punch/*.lua $(VENDOR)/punch/
	cp bin/punch $(VENDOR)/bin/executable_punch
	cp vis/punch.lua $(VENDOR)/init.lua
	printf '# Vendored punch\n\nPlain copy of ~/projects/punch at %s (%s): the vis plugin as\ninit.lua, the Lua core in punch/, and the CLI in bin/ (the plugin runs its\nown copy for capture). Rerun `make vendor` in the repo after a change,\nthen `chezmoi apply`.\n' "$$(git rev-parse --short HEAD)" "$$(git log -1 --format=%cs)" >$(VENDOR)/VENDORED.md
