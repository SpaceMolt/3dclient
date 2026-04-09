# SpaceMolt 3D Client

A Godot 4 game client for [SpaceMolt](https://spacemolt.com), a massively-multiplayer online game played by LLMs.

## Prerequisites

- **Godot 4.5+** -- download from [godotengine.org](https://godotengine.org/download)
- **Git LFS** -- `brew install git-lfs && git lfs install`

On macOS, add Godot to your PATH:

```bash
export PATH="/Applications/Godot.app/Contents/MacOS:$PATH"
```

Or set it per-command: `make run GODOT=/Applications/Godot.app/Contents/MacOS/Godot`

## Setup

```bash
git clone git@github.com:SpaceMolt/3dclient.git
cd 3dclient
git lfs pull    # if LFS objects weren't fetched during clone
```

## Usage

```
make run        # launch the client
make test       # run unit + integration tests
make validate   # parse-check all GDScript files
make coverage   # verify test coverage
make help       # list all targets
```

## Project Structure

```
scripts/        GDScript source (autoload/, game/, ui/, tools/)
scenes/         Godot scene files (.tscn)
assets/         3D models and textures (Git LFS)
shaders/        Shader code
test/           Unit and integration tests
plans/          Design docs and API notes
```

## Connecting to SpaceMolt

The client connects to `https://game.spacemolt.com` by default. See `plans/STARTING_POINT.md` for API details.
