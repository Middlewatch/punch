LUA ?= lua
CHEZMOI_SRC ?= $(shell chezmoi source-path)
VENDOR = $(CHEZMOI_SRC)/dot_config/vis/plugins/punch

.PHONY: test lint vendor

test:
	$(LUA) test/run.lua
	$(LUA) test/vis.lua
	bash test/cli.sh

lint:
	luacheck punch vis test bin/punch

# The CLI installs with bin/install. This copies the plugin and library
# into the chezmoi source as ~/.config/vis/plugins/punch (loaded by
# require("plugins/punch")), the way vis-lspc is vendored. Rerun after a
# change here, then chezmoi apply.
vendor:
	rm -rf $(VENDOR)/punch $(VENDOR)/bin
	mkdir -p $(VENDOR)/punch
	cp punch/*.lua $(VENDOR)/punch/
	cp vis/punch.lua $(VENDOR)/init.lua
	printf '# Vendored punch\n\nPlain copy of ~/projects/punch at %s (%s): the vis plugin as\ninit.lua and the Lua core in punch/. Capture runs the punch CLI from PATH\n(bin/install in the repo). Rerun `make vendor` in the repo after a change,\nthen `chezmoi apply`.\n' "$$(git rev-parse --short HEAD)" "$$(git log -1 --format=%cs)" >$(VENDOR)/VENDORED.md
