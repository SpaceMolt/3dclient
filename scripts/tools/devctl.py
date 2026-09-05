#!/usr/bin/env python3
"""Drive a running SpaceMolt client through its dev control server.

The client must be started with SPACEMOLT_DEV_PORT set (scripts/tools/dev_run.sh does this).

  devctl.py ping
  devctl.py wait [seconds]              wait for the dev port to accept connections
  devctl.py screenshot [path.png]       save the viewport (default screenshots/dev.png)
  devctl.py key <name> [shift] [ctrl]   press and release a key, e.g. key D, key Escape
  devctl.py click <x> <y> [button] [double]
  devctl.py scroll <x> <y> up|down [n]
  devctl.py drag <x> <y> <x2> <y2> [button=2]   right-drag orbits/tilts the camera
  devctl.py type <text>
  devctl.py state [key]                 dump StateManager (optionally one field)
  devctl.py nodes [pattern]             visible controls with screen rects
  devctl.py call <node> <method> [json args...]   e.g. call /root/NetworkManager disconnect_from_server
  devctl.py get <node> <property>       read a node property, e.g. get /root/Main/Game/GameView/Camera3D _orbit
  devctl.py quit
"""
import json
import os
import socket
import sys
import time

HOST = "127.0.0.1"
PORT = int(os.environ.get("SPACEMOLT_DEV_PORT", "7333"))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def send(cmd: dict, timeout: float = 10.0) -> dict:
    with socket.create_connection((HOST, PORT), timeout=timeout) as sock:
        sock.sendall((json.dumps(cmd) + "\n").encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
    return json.loads(buf.decode() or "{}")


def wait(seconds: float) -> None:
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            if send({"cmd": "ping"}, timeout=1).get("ok"):
                print("dev server ready")
                return
        except OSError:
            time.sleep(0.5)
    sys.exit("dev server did not come up on port %d within %ss" % (PORT, seconds))


def main(argv: list) -> None:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return
    name, args = argv[0], argv[1:]
    if name == "wait":
        wait(float(args[0]) if args else 60)
        return
    if name == "screenshot":
        path = os.path.abspath(args[0] if args else os.path.join(ROOT, "screenshots", "dev.png"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        cmd = {"cmd": "screenshot", "path": path}
    elif name == "key":
        cmd = {"cmd": "key", "key": args[0], "shift": "shift" in args[1:], "ctrl": "ctrl" in args[1:]}
    elif name == "click":
        cmd = {"cmd": "click", "x": float(args[0]), "y": float(args[1]),
               "button": int(args[2]) if len(args) > 2 else 1, "double": "double" in args}
    elif name == "drag":
        cmd = {"cmd": "drag", "x": float(args[0]), "y": float(args[1]), "x2": float(args[2]), "y2": float(args[3]),
               "button": int(args[4]) if len(args) > 4 else 2}
    elif name == "scroll":
        cmd = {"cmd": "scroll", "x": float(args[0]), "y": float(args[1]), "dir": args[2],
               "n": int(args[3]) if len(args) > 3 else 1}
    elif name == "type":
        cmd = {"cmd": "type", "text": " ".join(args)}
    elif name == "nodes":
        cmd = {"cmd": "nodes", "pattern": args[0] if args else ""}
    elif name == "get":
        cmd = {"cmd": "get", "node": args[0], "property": args[1]}
    elif name == "call":
        cmd = {"cmd": "call", "node": args[0], "method": args[1], "args": [json.loads(a) for a in args[2:]]}
    else:
        cmd = {"cmd": name}
    reply = send(cmd)
    if name == "state" and args:
        reply = reply.get("state", {}).get(args[0])
    print(json.dumps(reply, indent=2, sort_keys=True))


if __name__ == "__main__":
    main(sys.argv[1:])
