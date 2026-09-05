#!/usr/bin/env bash
# Downloads the Godot 4.6.1 Linux x86_64 binary into a shared cache and links it as bin/godot-bin.
# Run once per checkout: make godot   (or: bash bin/install.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_VERSION="4.6.1-stable"
FILE="Godot_v${GODOT_VERSION}_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${FILE}.zip"
CACHE_DIR="${GODOT_CACHE_DIR:-$HOME/.cache/godot}"
DEST="$SCRIPT_DIR/godot-bin"

mkdir -p "$CACHE_DIR"
if [[ ! -x "$CACHE_DIR/$FILE" ]]; then
	echo "Downloading Godot ${GODOT_VERSION} to $CACHE_DIR..."
	curl -fL "$URL" -o "$CACHE_DIR/$FILE.zip"
	unzip -q -o "$CACHE_DIR/$FILE.zip" -d "$CACHE_DIR"
	rm "$CACHE_DIR/$FILE.zip"
	chmod +x "$CACHE_DIR/$FILE"
fi
ln -sfn "$CACHE_DIR/$FILE" "$DEST"
echo "Godot linked at $DEST -> $CACHE_DIR/$FILE"
