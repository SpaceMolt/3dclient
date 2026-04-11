# SpaceMolt Godot Client

# Detect Godot binary (honors $GODOT from environment)
GODOT ?= $(or $(shell command -v godot 2>/dev/null), \
	$(wildcard /Applications/Godot.app/Contents/MacOS/Godot), \
	$(wildcard bin/godot))

ifeq ($(GODOT),)
$(error Godot not found. Install it or set GODOT=/path/to/godot)
endif

.PHONY: run test validate coverage help

help: ## Show this help
	@grep -E '^[a-z][a-z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

run: ## Launch the game client (logs to output.log)
	$(GODOT) --path . 2>&1 | tee output.log

test: ## Run all tests (unit + integration)
	$(GODOT) --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--add "res://test/unit/" --add "res://test/integration/" \
		--ignoreHeadlessMode

validate: ## Parse-check all GDScript files
	$(GODOT) --headless --import 2>&1 | grep -E "SCRIPT ERROR|Failed to load" | grep -v addons/ && exit 1 || echo "All scripts valid."

coverage: ## Check that all scripts have test files
	./scripts/tools/check_test_coverage.sh
