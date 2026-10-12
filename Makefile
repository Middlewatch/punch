LUA ?= lua
BINDIR ?= $(HOME)/.local/bin

.PHONY: test lint install

test:
	$(LUA) test/run.lua
	bash test/cli.sh

lint:
	luacheck punch test bin/punch

install:
	ln -sf $(CURDIR)/bin/punch $(BINDIR)/punch
