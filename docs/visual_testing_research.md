# Visual Testing & LLM Game Dev Research

## Camera Bug Root Cause (Fixed)

The camera's `look_at` target was calculated as a point only `zoom * 0.1` units from the camera position. At height 20, this meant looking at a spot just 2 units away horizontally — 5.7° from straight down. Orbit appeared as translation rather than rotation because the view was nearly top-down.

**Fix**: Changed `look_at` to target the actual follow target position. The tilt parameter now naturally controls the viewing angle:
- `tilt=0.4` (default) → 22° from vertical
- `tilt=1.0` (low angle) → 45° from vertical
- `tilt=0.15` (top-down) → 8.5° from vertical

## Current Visual Testing Pipeline

### Programmatic Screenshot Capture

`scripts/tools/capture_screenshot.gd` — standalone GDScript that:
- Creates a minimal 3D scene with colored reference markers and grid (no autoload dependencies)
- Applies camera at various orbit/tilt/zoom states
- Saves PNGs to `screenshots/` directory
- Run with: `./bin/godot --windowed --resolution 800x600 -s scripts/tools/capture_screenshot.gd`
- Renders via llvmpipe (software rendering) in WSL2
- Claude can view resulting PNGs with the Read tool

### Script Validation

- `./scripts/tools/validate_scripts.sh` — runs Godot editor headless to catch parse/compile errors
- `.git/hooks/pre-commit` — blocks commits when staged `.gd` files have errors
- Both use: `./bin/godot --headless -e --quit-after 1` and grep for SCRIPT ERROR

### Limitations

- Standalone scripts (`-s` flag) don't load autoloads — must build scenes manually
- `--headless` disables all rendering — cannot be used for screenshot capture
- Xvfb has known compatibility issues with Godot 4.x (BadAtom error)

## MCP Servers for Godot

### Most Promising

| Server | URL | Features |
|--------|-----|----------|
| **GoPeak** | github.com/HaD0Yun/godot-mcp | 95+ tools: screenshot capture, input injection, GDScript LSP, DAP debugger, ClassDB introspection |
| **GDAI MCP** | gdaimcp.com | Commercial. Auto-captures screenshots of editor and running game. Reads errors, updates scripts, verifies via screenshots |
| **godot-runtime-mcp** | github.com/Erodenn/godot-runtime-mcp | Injects McpBridge autoload at runtime via UDP:9900. Viewport screenshots, input simulation, live scene tree, arbitrary GDScript execution |

### WSL-Specific Screenshot Tools

| Tool | URL | Notes |
|------|-----|-------|
| **mcp-windows-screenshots** | github.com/rubinsh/mcp-windows-screenshots | `claude mcp add windows-screenshots -s user -- npx mcp-windows-screenshots@latest`. Captures Windows display from WSL |
| **WSLSnapit-MCP** | github.com/peterparker57/WSLSnapit-MCP | PowerShell bridge, image compression, WSL/Windows path conversion |
| **Claude Code Image Paste (WSL)** | VS Code extension by melon-hub | Pastes clipboard images into VS Code terminal for Claude Code |

### Other Godot MCP Servers

| Server | URL |
|--------|-----|
| bradypp/godot-mcp | github.com/bradypp/godot-mcp |
| Coding-Solo/godot-mcp | github.com/Coding-Solo/godot-mcp |
| ee0pdt/Godot-MCP | github.com/ee0pdt/Godot-MCP |
| Godot MCP Pro | godot-mcp.abyo.net (commercial, 162 tools) |

## Visual Regression Testing in Game Engines

### Current State

No mature visual regression framework exists for game engines comparable to web tools (Playwright, Percy, Applitools).

- **Godot Proposal #1760** — proposes `--offscreen` CLI arg for deterministic screenshot capture without GPU. Not yet merged.
- **Godot Proposal #5790** — broader off-screen DisplayServer for headless CI. Not yet merged.
- **Unreal Engine** has a built-in Screenshot Comparison Tool with golden image management.
- **Unity** uses AltTester and GameDriver for automated visual testing.

### Practical Approach for Godot

1. Capture screenshots in-engine: `get_viewport().get_texture().get_image().save_png()`
2. Use `await RenderingServer.frame_post_draw` before capture to ensure frame is fully rendered
3. Compare against baseline using pixel diff (ImageMagick `compare`, pixelmatch, or GDScript Image class)
4. Store golden images in repo, diff on CI

## LLM Game Dev Best Practices

### Workflow Patterns

- **Treat LLM as pair programmer, not autonomous developer** — provide architecture constraints and reference implementations
- **TDD integrates well** — write test first, have agent implement, gives verification loop
- **Break UI into atomic components** — quality jumps from ~40% to ~90% vs single-prompt full-screen attempts
- **Separate AI-handled vs human-handled work**: AI excels at boilerplate, patterns, test generation, data parsing. Humans own visual design, game feel, architecture

### Why Godot Works Well with LLMs

- Almost all editor changes are reflected in text files (.tscn, .tres)
- GDScript is simple and well-documented
- Scene tree is inspectable and serializable
- Signal-driven architecture maps well to LLM understanding

### Cautionary Notes

- Fully offloading visual work to AI can lead to loss of codebase understanding (DataDeer RTS experiment)
- Use formal, detailed prompts — casual language causes inconsistent output
- Always verify visual results — LLMs cannot see what they render without explicit screenshot feedback loops

## Recommended Next Steps

1. **Immediate**: Continue using programmatic screenshot capture for camera/visual debugging
2. **Short-term**: Evaluate `mcp-windows-screenshots` for live game visibility during development
3. **Medium-term**: Evaluate GoPeak or godot-runtime-mcp for integrated screenshot + input simulation
4. **Long-term**: Build golden-image regression tests once Godot gets `--offscreen` rendering support
