#!/usr/bin/env python3
"""Check every tool/action pair the client sends against the server's v2 OpenAPI spec.

Reads the live spec by default (SPACEMOLT_SERVER_URL or game.spacemolt.com); pass a
path to use a saved spec instead. Exits 1 and lists each pair the server does not know.
"""
import glob
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLS = {
    "send_command": "spacemolt",
    "send_battle_command": "spacemolt_battle",
    "send_market_command": "spacemolt_market",
    "send_storage_command": "spacemolt_storage",
    "send_transfer_command": "spacemolt_transfer",
    "send_social_command": "spacemolt_social",
    "send_salvage_command": "spacemolt_salvage",
    "send_ship_command": "spacemolt_ship",
    "send_faction_command": "spacemolt_faction",
    "send_facility_command": "spacemolt_facility",
    "send_intel_command": "spacemolt_intel",
}


def load_spec(source: str) -> dict:
    if os.path.exists(source):
        with open(source) as f:
            return json.load(f)
    with urllib.request.urlopen(source, timeout=30) as resp:
        return json.load(resp)


def main() -> int:
    base = os.environ.get("SPACEMOLT_SERVER_URL", "https://game.spacemolt.com").rstrip("/")
    source = sys.argv[1] if len(sys.argv) > 1 else base + "/api/v2/openapi.json"
    spec = load_spec(source)
    known = set()
    for path in spec["paths"]:
        m = re.match(r"/api/v2/(spacemolt[a-z_]*)/([a-z_]+)$", path)
        if m:
            known.add((m.group(1), m.group(2)))
    pattern = re.compile(r"(%s)\(\"([a-z_]+)\"" % "|".join(TOOLS))
    unknown = []
    for f in sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)):
        if f.endswith("network_manager.gd"):
            continue
        with open(f) as fh:
            for lineno, line in enumerate(fh, 1):
                for fn, action in pattern.findall(line):
                    if (TOOLS[fn], action) not in known:
                        unknown.append((os.path.relpath(f, ROOT), lineno, TOOLS[fn], action))
    for f, lineno, tool, action in unknown:
        print("%s:%d  %s/%s is not in the server spec" % (f, lineno, tool, action))
    print("%d unknown tool/action pairs" % len(unknown))
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
