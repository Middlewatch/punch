LUA ?= lua

.PHONY: test lint

test:
	$(LUA) test/run.lua

lint:
	luacheck punch test
