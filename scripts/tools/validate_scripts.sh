#!/usr/bin/env bash
# Validate all GDScript files by running a full project import.
# Catches parse errors, type inference errors, and failed script loads.
#
# Usage:
#   ./scripts/tools/validate_scripts.sh          # validate everything
#   ./scripts/tools/validate_scripts.sh --quiet   # only print errors (for hooks)

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

GODOT="./bin/godot"
if [[ ! -x "$GODOT" ]]; then
    echo "Error: Godot binary not found at $GODOT"
    exit 1
fi

QUIET=false
if [[ "${1:-}" == "--quiet" ]]; then
    QUIET=true
fi

# Run a full import pass — this parses all scripts with autoloads available
OUTPUT=$("$GODOT" --headless --import 2>&1 || true)

# Extract script errors (parse errors, compile errors, failed loads)
# Exclude addons/ since those are third-party
ERRORS=$(echo "$OUTPUT" | grep -E "SCRIPT ERROR:.*(Parse Error|Compile Error)" | grep -v "addons/" || true)
FAILED=$(echo "$OUTPUT" | grep -E "ERROR: Failed to load script" | grep -v "addons/" || true)

if [[ -n "$ERRORS" || -n "$FAILED" ]]; then
    echo "GDScript validation FAILED:"
    echo ""
    if [[ -n "$ERRORS" ]]; then
        echo "$ERRORS"
    fi
    if [[ -n "$FAILED" ]]; then
        echo "$FAILED"
    fi
    echo ""
    echo "Fix the errors above before committing."
    exit 1
fi

if [[ "$QUIET" == false ]]; then
    echo "All scripts validated successfully."
fi
exit 0
