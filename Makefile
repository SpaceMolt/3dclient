# SpaceMolt Godot Client

# Detect Godot binary (honors $GODOT from environment)
GODOT ?= $(or $(shell command -v godot 2>/dev/null), \
	$(wildcard /Applications/Godot.app/Contents/MacOS/Godot), \
	$(wildcard bin/godot))

ifeq ($(GODOT),)
ifneq ($(MAKECMDGOALS),godot)
$(error Godot not found. Run "make godot" to download it, or set GODOT=/path/to/godot)
endif
endif

.PHONY: run test validate coverage parity help import godot dev

help: ## Show this help
	@grep -E '^[a-z][a-z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

import: ## Build .godot/ import cache (class_name registration, resource import)
	@if [ ! -d .godot ]; then \
		echo "Building import cache..."; \
		$(GODOT) --headless --import; \
	fi

godot: ## Download Godot 4.6.1 into ~/.cache/godot and link it as bin/godot-bin
	bash bin/install.sh

dev: ## Launch for autonomous dev loops: env login + dev control port (see scripts/tools/devctl.py)
	./scripts/tools/dev_run.sh

run: import ## Launch the game client (logs to output.log)
	$(GODOT) --path . 2>&1 | tee output.log

test: ## Run all tests (unit + integration)
	$(GODOT) --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--add "res://test/unit/" --add "res://test/integration/" \
		--ignoreHeadlessMode

validate: ## Parse-check all GDScript files
	$(GODOT) --headless --import 2>&1 | grep -E "SCRIPT ERROR|Failed to load" | grep -v addons/ && exit 1 || echo "All scripts valid."

coverage: ## Check that all scripts have test files
	./scripts/tools/check_test_coverage.sh

parity: ## Check every tool/action the client sends against the live v2 OpenAPI spec
	python3 scripts/tools/check_api_parity.py
