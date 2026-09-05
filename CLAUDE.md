# SpaceMolt Godot Client

## Stack
- **Godot 4.4+** (GdUnit4 v6 requires 4.5+, use the latest stable Godot you have)
- **GDScript** throughout — no C#
- **GdUnit4 v6** for testing (`addons/gdUnit4/`)
- **WebSocket v2** (`/ws/v2`) for all game actions and server pushes. HTTP is used only by the dashboard API-key flow (player list, ws-token). Protocol reference: `gameserver/internal/docs/websocket-v2.md` (served at `/ws.md`).

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
- Every command is a frame `{tool, action, payload, request_id}`; NetworkManager correlates replies by `request_id`
- Queries answer with a `result` frame; use `structuredContent`, never parse the `result` text
- Mutations answer with a pending ack, then an `action_result` frame carrying a state delta (or `action_error`). NetworkManager applies the delta to StateManager and only then calls the caller's `on_complete` with the outcome `details`
- There is no status polling: state changes arrive as deltas and push frames. Call `get_status` only to seed or resync
- `request_started` / `request_completed` fire when the in-flight set becomes non-empty / empty; panels lock on them
- Login: `login` (password), `login_token` (dashboard API key), or the `login_link` device flow, all over the socket. Unauthenticated sockets close after 30 s, so the device flow reconnects while it polls

## Runtime Log

`make run` tees all stdout/stderr to `output.log`. When the user asks you to "check the log" or "look at the output," read this file. It is gitignored and overwritten on each run.

## Autonomous Dev Loop (agents: use this)

You can run and drive the client without a human. Everything goes through the
dev control server (`scripts/autoload/dev_server.gd`), which listens on
127.0.0.1 only when `SPACEMOLT_DEV_PORT` is set.

1. One-time: `make godot` downloads Godot 4.6.1 into `~/.cache/godot` and links `bin/godot-bin`.
2. Put credentials in `.test_credentials` (gitignored), one `KEY=VALUE` per line:
   `SPACEMOLT_USERNAME` + `SPACEMOLT_PASSWORD` for a direct password login, and/or
   `SPACEMOLT_API_KEY` (dashboard key) with optional `SPACEMOLT_PLAYER` (username to auto-select).
   Password wins when both are present; `SPACEMOLT_USERNAME= make dev` forces the API-key path.
3. `make dev` launches the client, logs in with those credentials, and waits for the dev port.
   Under WSL the window opens on the Windows desktop through WSLg (`DISPLAY=:0`).
4. Drive it with `scripts/tools/devctl.py`:
   - `devctl.py screenshot screenshots/name.png` — exact viewport capture, then Read the PNG
   - `devctl.py key D` / `devctl.py key Escape` — key press (names from `OS.find_keycode_from_string`)
   - `devctl.py click X Y` / `devctl.py scroll X Y up 3` / `devctl.py type hello`
   - `devctl.py nodes Button` — visible controls with screen rects, for finding what to click
   - `devctl.py state` or `devctl.py state ship` — StateManager dump
   - `devctl.py quit`
5. `output.log` holds the run log. `SPACEMOLT_SERVER_URL` overrides the server (local gameserver).

`make run` is the human launch path and still uses the browser device login.

## Build & Validation Tools

All scripts in `scripts/tools/`:

- **`validate_scripts.sh`** — Parse-checks all GDScript files. Also runs as a pre-commit hook. Run after editing scripts.
- **`check_test_coverage.sh`** — Verifies every non-exempt script has a corresponding test file.
- **`check_api_parity.py`** (`make parity`) — Checks every `send_*_command("action")` in the client against the live v2 OpenAPI spec. Run it before a PR: the server renames and removes actions between releases.
- **`build_windows.sh`** — Validates scripts, then exports a Windows .exe.
- **`capture_screenshot.gd`** — Visual testing: `./bin/godot --windowed --resolution 800x600 -s scripts/tools/capture_screenshot.gd`. Saves PNGs to `screenshots/`.
- **`dev_run.sh`** / **`devctl.py`** — the autonomous dev loop described in the section that precedes this one.

### Build workflow
1. `./scripts/tools/validate_scripts.sh` — fix any parse errors
2. Run tests: `make test`
3. `./scripts/tools/build_windows.sh` — export the Windows exe

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
