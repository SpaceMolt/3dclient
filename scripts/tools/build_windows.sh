#!/bin/bash
# Build a Windows .exe export of SpaceMolt
# Output: D:\Development\spacemolt\godot\SpaceMolt.exe

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="$PROJECT_DIR/bin/godot"
OUTPUT_DIR="/mnt/d/Development/spacemolt/godot"
OUTPUT_EXE="$OUTPUT_DIR/SpaceMolt.exe"

mkdir -p "$OUTPUT_DIR"

echo "Building SpaceMolt Windows export..."
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Windows Desktop" "$OUTPUT_EXE" 2>&1

echo ""
if [ -f "$OUTPUT_EXE" ]; then
    SIZE=$(du -h "$OUTPUT_EXE" | cut -f1)
    echo "Build successful: $OUTPUT_EXE ($SIZE)"
    echo "Windows path: D:\\Development\\spacemolt\\godot\\SpaceMolt.exe"
else
    echo "Build failed — no output file found"
    exit 1
fi
