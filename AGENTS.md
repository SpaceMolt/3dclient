# Repository Guidelines

## Project Structure & Module Organization
`scripts/` contains all game code in GDScript, split by concern: `autoload/` for singletons such as `NetworkManager` and `StateManager`, `game/` for gameplay systems, `ui/` for HUD and panel logic, and `tools/` for repo automation. `scenes/` mirrors runtime content with `game/`, `ui/`, and `test/` scenes. Tests live under `test/unit/` for logic and `test/integration/` for scene, UI, and gameplay flows. Keep reusable art in `assets/`, shader code in `shaders/`, and rendered artifacts in `reports/` or `screenshots/` rather than beside source files.

## Build, Test, and Development Commands
Run `bash bin/install.sh` once after cloning to place the pinned Godot binary at `bin/godot`.

- `./bin/godot --path .` launches the project locally.
- `./scripts/tools/validate_scripts.sh` runs a headless import pass and fails on GDScript parse/load errors.
- `./bin/godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add "res://test/unit/" --add "res://test/integration/" --ignoreHeadlessMode` runs the automated test suite.
- `./scripts/tools/check_test_coverage.sh` verifies each non-exempt script in `scripts/` has a matching test.
- `./scripts/tools/build_windows.sh` exports the Windows build to the configured `/mnt/d/.../SpaceMolt.exe` path.

## Coding Style & Naming Conventions
Use tabs for indentation in `.gd` files, matching the existing codebase. Name scripts and scenes in `snake_case` (`ship_controller.gd`, `battle_panel.tscn`); use PascalCase only for inferred class names and Godot node types. Prefer small typed functions (`func _ready() -> void`) and keep `StateManager` as the client-side source of truth rather than reading network payloads directly in UI code. Edit `project.godot` through the Godot editor when possible.

## Testing Guidelines
Testing is mandatory for new logic. Add unit tests for pure state or calculation code and integration tests for scene interactions, signals, and UI flows. Follow the existing `test_<subject>.gd` file pattern and descriptive test names such as `test_update_state_emits_ship_updated_when_ship_changes`. Run validation plus the relevant GdUnit command before committing, and update `scripts/tools/check_test_coverage.sh` only when a script is truly exempt.

## Commit & Pull Request Guidelines
Recent commits use short imperative subjects, for example `Fix POI click detection with manual raycasting` and `Add travel system, UI panels, visual effects, and mandatory test coverage`. Keep commits focused and explain behavior, not implementation trivia. Pull requests should include a concise summary, linked issue or plan entry when applicable, the commands you ran, and screenshots or GIFs for visible UI or animation changes. If you find API/spec mismatches, record them in `API_DISCREPANCIES.md` within the same change.
