# Test suite: needs plenary.nvim, nvim-nio and neotest, cloned into ./.deps on first run.
DEPS ?= .deps

deps:
	@mkdir -p $(DEPS)
	@[ -d $(DEPS)/plenary.nvim ] || git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(DEPS)/plenary.nvim
	@[ -d $(DEPS)/nvim-nio ] || git clone --depth 1 https://github.com/nvim-neotest/nvim-nio $(DEPS)/nvim-nio
	@[ -d $(DEPS)/neotest ] || git clone --depth 1 https://github.com/nvim-neotest/neotest $(DEPS)/neotest

test: deps
	NEOTEST_CUCUMBER_DEPS=$(abspath $(DEPS)) nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua', sequential = true }"

.PHONY: deps test
