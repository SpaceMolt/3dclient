#!/usr/bin/env bash
# Runs the GdUnit4 suites and exits non-zero when any test fails or errors.
# Usage: scripts/tools/run_tests.sh [res://test/unit/ ...]   (default: unit + integration)
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$(command -v godot || echo bin/godot)}"
if [[ $# -eq 0 ]]; then
	set -- res://test/unit/ res://test/integration/
fi
args=()
for suite in "$@"; do
	args+=(--add "$suite")
done
log="$(mktemp)"
"$GODOT" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd "${args[@]}" --ignoreHeadlessMode 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee "$log" | grep -E "FAILED|Overall Summary|SCRIPT ERROR|Parse Error"
summary="$(grep -E "Overall Summary" "$log" | tail -1)"
rm -f "$log"
if [[ -z "$summary" ]] || ! grep -qE "\| 0 errors \| 0 failures" <<<"$summary"; then
	echo "TESTS FAILED"
	exit 1
fi
