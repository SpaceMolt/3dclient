#!/usr/bin/env bash
# Launch the client for autonomous dev loops: env-var login, dev control port, fixed window.
# Reads .test_credentials (gitignored) for SPACEMOLT_USERNAME / SPACEMOLT_PASSWORD.
# Any extra arguments are passed to Godot. Logs go to output.log.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ -f .test_credentials ]]; then
	# shellcheck disable=SC1091
	source .test_credentials
	export SPACEMOLT_USERNAME="${SPACEMOLT_USERNAME:-${username:-}}"
	export SPACEMOLT_PASSWORD="${SPACEMOLT_PASSWORD:-${password:-}}"
fi
export SPACEMOLT_DEV_PORT="${SPACEMOLT_DEV_PORT:-7333}"
export DISPLAY="${DISPLAY:-:0}"

GODOT="${GODOT:-$(command -v godot || echo bin/godot)}"
[[ -x "$GODOT" ]] || { echo "Godot not found. Run: make godot (or set GODOT=/path/to/godot)" >&2; exit 1; }

if [[ -f .dev_run.pid ]] && kill -0 "$(cat .dev_run.pid)" 2>/dev/null; then
	kill "$(cat .dev_run.pid)"
	sleep 1
fi
[[ -d .godot ]] || "$GODOT" --headless --import >/dev/null 2>&1 || true

"$GODOT" --path . --windowed --resolution "${SPACEMOLT_DEV_RESOLUTION:-1280x720}" "$@" > output.log 2>&1 &
echo $! > .dev_run.pid
python3 scripts/tools/devctl.py wait 90
