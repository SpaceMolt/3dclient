# SpaceMolt Godot Client

## Stack
- **Godot 4.4+** (GdUnit4 v6 requires 4.5+, use the latest stable Godot you have)
- **GDScript** throughout — no C#
- **GdUnit4 v6** for testing (`addons/gdUnit4/`)
- **REST API** only — no WebSocket for game actions (see PLAN.md and STARTING_POINT.md)

## Testing Policy (Non-Negotiable)

**TDD is the default workflow.** Write the test before or alongside the code, not after.

- Every new script with logic gets tests. No exceptions.
- Tests live in `test/unit/` (pure logic) or `test/integration/` (scene runner / UI)
- Run tests before committing. Don't commit red tests.
- Run `./scripts/tools/validate_scripts.sh` after editing scripts to catch parse errors. A pre-commit hook also runs this automatically.
- If you write code that's hard to test, that's a signal the code needs to be restructured.

### What to test
- All data transformation logic (state parsing, percentage calculations, signal emissions)
- All UI state logic (which buttons are visible, what disables what)
- Network response parsing and error handling paths
- Anything with a conditional — test both branches

### What not to bother testing
- Godot engine rendering behaviour
- Raw HTTP success/failure (test the parsing, not the wire)
- Trivial getters with no logic

## Architecture
See `PLAN.md` for the full plan and `STARTING_POINT.md` for API details.

Key autoloads (singletons): `NetworkManager`, `StateManager`, `UIManager`, `AssetLoader`

**StateManager is the source of truth.** UI reads from it and listens to its signals. Nothing reads directly from the network response except NetworkManager and StateManager.

## API Conventions
- Always use `structuredContent` from responses — never parse the `result` text field
- Mutations block until complete; disable UI during in-flight requests
- Poll `get_status` every 10 seconds; reset timer after each mutation response
- Session ID stored in NetworkManager; passed as `X-Session-Id` header on every request

## Build & Validation Tools

All scripts in `scripts/tools/`:

- **`validate_scripts.sh`** — Parse-checks all GDScript files. Also runs as a pre-commit hook. Run after editing scripts.
- **`check_test_coverage.sh`** — Verifies every non-exempt script has a corresponding test file.
- **`build_windows.sh`** — Validates scripts, then exports a Windows .exe to `D:\Development\spacemolt\godot\SpaceMolt.exe`. **Always run this after code changes to give Craig a testable build.**
- **`capture_screenshot.gd`** — Visual testing: `./bin/godot --windowed --resolution 800x600 -s scripts/tools/capture_screenshot.gd`. Saves PNGs to `screenshots/`.

### Build workflow
1. `./scripts/tools/validate_scripts.sh` — fix any parse errors
2. Run tests: `./bin/godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add "res://test/unit/" --ignoreHeadlessMode`
3. `./scripts/tools/build_windows.sh` — export the Windows exe for Craig to test

## Visual Animation Rules (Non-Negotiable)

**No snaps or lerps to cover up incorrect math.** If a transition requires a "settle animation," "brief lerp at the end," or any other smoothing step to hide the fact that the start and end states are geometrically inconsistent, that is a signal the math is wrong — not a signal to add a transition. Fix the underlying coordinate system so that things are in the right place from the start. A correct solution animates smoothly because the geometry is right, not because the discontinuity is hidden.

## Git LFS

This repo uses Git LFS for all binary assets. Tracked extensions (see `.gitattributes`):

`*.glb *.gltf *.fbx *.obj *.jpg *.jpeg *.png *.webp *.svg *.hdr *.exr *.dds *.wav *.mp3 *.ogg *.ttf *.otf *.woff *.woff2 *.res`

- **Adding new binary types:** Run `git lfs track "*.ext"` and commit `.gitattributes`
- **Code-only clone:** `GIT_LFS_SKIP_SMUDGE=1 git clone ...` skips downloading LFS objects
- **Pulling LFS objects later:** `git lfs pull` to fetch all, or `git lfs pull --include="assets/ships/*"` for a subset
- Git objects (code/scenes/configs) are ~1MB; LFS objects (3D models, textures) are ~700MB

## Godot Documentation (DeepWiki MCP)

When you need to look up Godot 4.x APIs, classes, or engine behavior, use the DeepWiki MCP server (configured in user scope). The docs repo is `godotengine/godot-docs`.

- **Browse topics:** `read_wiki_structure(repoName: "godotengine/godot-docs")`
- **Read a specific page:** `read_wiki_contents(repoName: "godotengine/godot-docs", path: "<page-path>")` — get the path from `read_wiki_structure`
- **Ask a question:** `ask_question(repoName: "godotengine/godot-docs", question: "How do I use HTTPRequest in GDScript?")` — returns an AI-generated answer grounded in the docs

Use `godotengine/godot` (the engine source repo) instead of `godot-docs` when you need implementation details rather than user-facing documentation.

## API Discrepancies Tracking
- Maintain `API_DISCREPANCIES.md` with any differences between the OpenAPI spec (`openapi.json`) and real API responses
- When you discover a new mismatch during development or testing, add it to the file immediately
- This file will be submitted as a bulk bug report — keep it accurate and detailed
