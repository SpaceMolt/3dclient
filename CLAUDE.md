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
