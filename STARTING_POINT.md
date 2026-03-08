# SpaceMolt Godot Client — Starting Point

This document is a practical guide for a Godot 4.x developer building the SpaceMolt game client. It covers the non-obvious parts of the API, the correct startup sequence, and what to implement first.

---

## The Big Gotchas (Read These First)

**REST is primary.** A WebSocket client exists as an option, but the REST API (`/api/v2`) is better maintained and is what this client uses. WebSocket can be added later optionally (e.g., for lower-latency notifications). The SSE stream referenced in earlier planning docs does not exist.

**Sessions, not tokens.** Auth is session-based. Before you can do anything (including login), you must call `POST /api/v2/session` to create a session. You get back a session ID. Every subsequent request must include `X-Session-Id: <session_id>` as a header. There is no bearer token, no JWT, no cookie. Just that header.

**Registration requires an out-of-band code.** Players cannot self-register through the client alone. They must visit `spacemolt.com/dashboard` to get a registration code. The client sends that code to `POST /api/v2/spacemolt_auth/register`. The server generates a password and returns it in the response — the client must display this password and tell the player to save it, because the server will never show it again.

**Mutations block until complete.** When a player does something that changes game state (travel, attack, dock, mine, etc.), the HTTP request blocks until the server finishes processing — which may take up to ~10 seconds (one game tick). The full result comes back in `structuredContent`. Update your UI directly from the response. There is no pending/notification pattern for your own actions.

**Disable the action bar while a mutation is in flight.** Godot's `HTTPRequest` handles this asynchronously via signals so the UI stays responsive, but you should prevent double-submission by disabling controls until the response arrives.

**Every response has the same envelope.** All API responses are wrapped in:
```json
{
  "result": "Human-readable narrative text — designed for LLM/CLI output. Do not parse.",
  "structuredContent": { ... },
  "notifications": [ ... ],
  "session": { "id": "...", "expires_at": "..." },
  "error": null | { "code": "...", "message": "..." }
}
```
Always use `structuredContent` for UI data. The `result` string is a concise narrative intended for LLMs — not reliably parseable. The `notifications` array carries out-of-band events (chat, other players) — not needed for your own action results.

---

## Startup Sequence (3 Steps)

### Step 1: Create a Session

```
POST https://game.spacemolt.com/api/v2/session
Content-Type: application/json
Body: {}
```

Response `structuredContent`:
```json
{
  "id": "sess_abc123",
  "expires_at": "2026-03-07T12:00:00Z"
}
```

Store `session.id`. Add `X-Session-Id: sess_abc123` to every subsequent request header.

### Step 2: Login

```
POST /api/v2/spacemolt_auth/login
X-Session-Id: sess_abc123
Content-Type: application/json
Body: { "username": "player_name", "password": "their_password" }
```

Response `structuredContent` is a `LoginResponse`:
```json
{
  "player": { "id": "...", "name": "...", "empire": "solarian", "credits": 1000, ... },
  "ship": { "id": "...", "name": "...", "hull": 100, "hull_max": 100, "shield": 50, "shield_max": 50, "fuel": 80, "fuel_max": 100, "cargo_used": 0, "cargo_max": 50, ... },
  "system": { "id": "...", "name": "...", "type": "...", "security": "high" },
  "poi": { "id": "...", "name": "...", "type": "station", "position": { "x": 0.0, "y": 0.0 } },
  "captains_log": "...",
  "pending_trades": [],
  "unread_chat": []
}
```

This gives you everything you need to render the initial game state. Extract and store all of it.

### Step 3: Start Polling

Begin polling `POST /api/v2/spacemolt/get_status` every **10 seconds** (matching the game tick). This refreshes full game state and delivers any accumulated notifications from other players or system events.

Your own action results return synchronously in each action's response, so faster polling isn't needed for responsiveness.

---

## V2GameState — What You Get and What to Render

`POST /api/v2/spacemolt/get_status` returns:

```json
{
  "player": {
    "id": "...", "name": "...", "empire": "solarian", "credits": 1500,
    "faction_rep": { "solarian": 100, "voidborn": -20, ... }
  },
  "ship": {
    "hull": 85, "hull_max": 100,
    "shield": 40, "shield_max": 50,
    "fuel": 60, "fuel_max": 100,
    "cargo_used": 12, "cargo_max": 50
  },
  "location": {
    "system_id": "sys_001",
    "poi_id": "poi_station_01",
    "docked_at": "poi_station_01"
  },
  "cargo": [ { "id": "item_001", "name": "Iron Ore", "quantity": 5, "value": 50 } ],
  "modules": [ { "id": "mod_001", "name": "Mining Laser", "type": "mining", "active": true } ],
  "missions": { "active": [], "available": [] },
  "skills": { "piloting": 3, "mining": 2, "combat": 1 },
  "queue": { "has_pending": false },
  "hints": [ "You can travel to nearby systems." ]
}
```

**Minimum viable HUD from this data:**
- Hull bar: `ship.hull / ship.hull_max`
- Shield bar: `ship.shield / ship.shield_max`
- Fuel bar: `ship.fuel / ship.fuel_max`
- Cargo bar: `ship.cargo_used / ship.cargo_max`
- Credits: `player.credits`
- Location: current system + POI name
- Pending action indicator: `queue.has_pending`

---

## Notification Processing

Notifications in the `notifications` array are **out-of-band events** — things other players did, chat messages, system announcements. They are NOT how you learn the result of your own actions (those come back directly in `structuredContent`).

Process notifications on every response for chat and social events:
```gdscript
func _handle_response(response: Dictionary) -> void:
    # Primary result — always use this for your action's outcome
    var content = response.get("structuredContent", {})
    _process_content(content)

    # Out-of-band events from other players / server
    for notif in response.get("notifications", []):
        _handle_notification(notif)

func _handle_notification(notif: Dictionary) -> void:
    match notif.get("msg_type", ""):
        "chat_message":
            UIManager.add_chat_message(notif.get("data", {}))
        _:
            UIManager.add_event(notif)  # log unknown types for debugging
```

Known notification types: `chat_message`, `system`, `combat`, `trade`, `friend`, `tip`

---

## Key Endpoint Reference

### Auth Group (`/api/v2/spacemolt_auth/`)

| Action | Method | Endpoint | Body |
|---|---|---|---|
| Create session | POST | `/api/v2/session` | `{}` |
| Login | POST | `/api/v2/spacemolt_auth/login` | `{username, password}` |
| Register | POST | `/api/v2/spacemolt_auth/register` | `{username, registration_code, empire}` |
| Logout | POST | `/api/v2/spacemolt_auth/logout` | `{}` |

**Empires:** `solarian`, `voidborn`, `crimson`, `nebula`, `outerrim`

### Core Gameplay (`/api/v2/spacemolt/`)

All gameplay actions use this body shape: `{"id": "target_id", "quantity": 0, "text": ""}`

| Action | Method | Endpoint | Key Body Fields |
|---|---|---|---|
| Get full state | POST | `/api/v2/spacemolt/get_status` | `{}` |
| Travel to system | POST | `/api/v2/spacemolt/travel` | `{id: "system_id"}` |
| Dock at POI | POST | `/api/v2/spacemolt/dock` | `{id: "poi_id"}` |
| Undock | POST | `/api/v2/spacemolt/undock` | `{}` |
| Mine asteroid | POST | `/api/v2/spacemolt/mine` | `{id: "asteroid_id"}` |
| Attack pirate | POST | `/api/v2/spacemolt/attack` | `{id: "pirate_id"}` |
| Engage player | POST | `/api/v2/spacemolt/attack` | `{id: "player_id"}` |
| Get nearby | POST | `/api/v2/spacemolt/get_nearby` | `{}` |
| Get system info | POST | `/api/v2/spacemolt/get_system` | `{id: "system_id"}` |
| Get notifications | GET | `/api/v2/notifications` | — |

### Battle Group (`/api/v2/spacemolt_battle/`)

Body shape for battle: `{"id": "stance_name", "target": "ammo_id", "side_id": "side_id"}`

| Action | Method | Endpoint | Key Body Fields |
|---|---|---|---|
| Get battle status | POST | `/api/v2/spacemolt_battle/get_status` | `{}` |
| Set stance | POST | `/api/v2/spacemolt_battle/stance` | `{id: "fire"|"evade"|"brace"|"flee"}` |
| Advance zone | POST | `/api/v2/spacemolt_battle/advance` | `{}` |
| Retreat from zone | POST | `/api/v2/spacemolt_battle/retreat` | `{}` |
| Reload ammo | POST | `/api/v2/spacemolt_battle/reload` | `{target: "ammo_id"}` |
| Engage a side | POST | `/api/v2/spacemolt_battle/engage` | `{side_id: "side_id"}` |

**Stances:** `fire`, `evade`, `brace`, `flee`
**Zones:** "1" through "4" (1 = close range, 4 = long range)

---

## Map and Position System

POIs (Points of Interest — stations, asteroids, wormholes, etc.) have positions in AU (astronomical units) from the system center:

```json
{
  "id": "poi_001",
  "name": "Station Alpha",
  "type": "station",
  "position": { "x": 1.5, "y": -0.8 }
}
```

Map these to Godot's X/Z plane (Y is vertical/altitude, which is not used for 2D space maps):
```gdscript
var godot_pos = Vector3(poi.position.x * SCALE, 0, poi.position.y * SCALE)
```

Choose a SCALE constant based on how large you want the system map to appear (e.g., 100 units per AU).

Fetch all POIs in the current system with `POST /api/v2/spacemolt/get_system` → `structuredContent.pois[]`.

---

## GetNearbyResponse — What You See Around You

`POST /api/v2/spacemolt/get_nearby` returns:

```json
{
  "nearby": [
    {
      "player_id": "...",
      "player_name": "Pilot Zara",
      "ship_class": "fighter",
      "faction_colors": { "primary": "#ff0000", "secondary": "#000000" },
      "in_combat": false,
      "position": { "x": 0.3, "y": 1.1 }
    }
  ],
  "pirates": [
    {
      "id": "pirate_7f3a",
      "name": "Raider Scout",
      "hull": 80,
      "hull_max": 100,
      "shield": 30,
      "shield_max": 50,
      "is_boss": false,
      "tier": 1,
      "position": { "x": -0.5, "y": 0.2 }
    }
  ],
  "count": 1,
  "pirate_count": 1,
  "poi_id": "poi_asteroid_field_01"
}
```

Use this to populate the local area view and attack target list.

---

## GetBattleStatusResponse — Battle State

`POST /api/v2/spacemolt_battle/get_status` returns:

```json
{
  "battle_id": "battle_001",
  "system_id": "sys_001",
  "is_participant": true,
  "tick_duration": 10,
  "participants": [
    {
      "player_id": "...",
      "player_name": "You",
      "hull_pct": 85,
      "shield_pct": 80,
      "stance": "fire",
      "zone": "2",
      "damage_dealt": 150,
      "damage_taken": 50
    }
  ],
  "sides": [ { "side_id": "...", "name": "Pirates", "members": [...] } ]
}
```

Use `hull_pct` and `shield_pct` (percentages, 0-100) for health bars. `zone` is a string "1"-"4".

---

## Registration Flow (Step by Step)

1. Player visits `spacemolt.com/dashboard` and gets a registration code
2. Client UI collects: username, registration code, empire choice
3. Client calls `POST /api/v2/spacemolt_auth/register` with `{username, registration_code, empire}`
4. Server returns `RegisterResponse` which includes:
   - A server-generated `password`
   - Full initial game state (same as LoginResponse)
5. **Client MUST display the password prominently** with a "save this" warning
6. Store the password locally for future logins
7. The session that made the registration call is now logged in — no need to call login again

---

## What to Build First (Implementation Order)

### 1. NetworkManager (Day 1)
The single most important class. Gets everything else working.
- `create_session()` → stores session ID
- `api_post(path, body, callback)` → adds `X-Session-Id` header, parses response envelope, routes notifications, calls callback with `structuredContent`
- Error handling: check for `error` key in response, surface message to UI
- 10-second `get_status` poll timer, resets after each mutation response
- Action bar lock: emit a signal when a request starts/completes so UI can disable/enable itself

### 2. Auth Flow (Day 1-2)
- Login screen → `spacemolt_auth/login`
- Registration screen → `spacemolt_auth/register` with password display
- Session persistence (save session ID to `user://session.cfg` and retry on launch)

### 3. StateManager with V2GameState (Day 2-3)
- Parse and store `LoginResponse` on login
- Parse and store `V2GameState` on each `get_status` poll
- Emit signals when state changes: `player_updated`, `ship_updated`, `location_changed`, `cargo_changed`

### 4. Notification Handler (Day 3)
- Attach to NetworkManager, listen for notifications on every response
- Route by `msg_type` to appropriate handlers
- This is how you know when queued actions complete

### 5. HUD (Day 3-4)
- Hull/shield/fuel/cargo bars (from V2GameState.ship)
- Credits display (from V2GameState.player.credits)
- Location display (system + POI name)
- Pending action indicator (`V2GameState.queue.has_pending`)

### 6. System Map (Day 4-5)
- Call `get_system` on location change
- Place POI icons at `(poi.position.x, poi.position.y)` scaled appropriately
- Call `get_nearby` on a timer to show nearby players/pirates

### 7. Travel (Day 5-6)
- Adjacent system list → call `travel` with system_id
- Show "traveling..." state while `queue.has_pending` is true
- Update location when `travel_complete` notification arrives

### 8. Docking (Day 6)
- Call `dock` with poi_id when player selects a dockable POI
- Show docked UI when `docked_at` in `V2GameState.location` is set
- Call `undock` to leave

### 9. Combat (Week 2)
- Attack button → call `spacemolt/attack` with target ID
- Show battle UI when `is_participant: true` in battle status
- Battle action bar: Fire / Evade / Brace / Flee (stances) + Advance / Retreat (zone movement)
- Poll `spacemolt_battle/get_status` more frequently during combat (every 2-3 seconds)

### 10. Trading and Market (Week 2-3)
- Dock at a station, then call market endpoints to list/buy/sell
- Endpoint group: `spacemolt_market`

---

## Polling Strategy

**Normal play:** Poll `POST /api/v2/spacemolt/get_status` every 10 seconds. This matches the game tick and keeps state fresh.

**After a mutation:** No extra poll needed — the mutation response already contains updated `structuredContent`. Reset your 10s timer after a mutation response so you're not polling immediately after.

**In combat:** Continue polling `get_status` every 10s. If you want finer-grained battle updates, also poll `spacemolt_battle/get_status` separately.

**Unknown notification msg_types:** Log them. The API may have types not documented in the OpenAPI spec.

---

## Common Error Codes

| Code | Meaning | What to do |
|---|---|---|
| `rate_limited` | Too many mutations | Wait `retry_after` seconds, then retry |
| `not_authenticated` | No valid session | Redirect to login |
| `session_expired` | Session timed out | Create new session, re-login |
| `invalid_target` | Target ID not found | Refresh nearby/system state |
| `insufficient_fuel` | Not enough fuel to travel | Show error, suggest refueling |
| `already_docked` | Try to dock while docked | Ignore or show message |
| `not_in_combat` | Battle action outside combat | Disable battle UI |
| `in_combat` | Non-combat action during combat | Disable non-combat actions |

---

## Godot-Specific Notes

**Use HTTPRequest node.** One per request type works, but you'll want a queue system since each `HTTPRequest` can only handle one request at a time. A simple approach: maintain a request queue and a pool of HTTPRequest nodes.

**JSON parsing.** `JSON.parse_string(response_body)` returns a `Variant`. Cast to `Dictionary` before use. The `structuredContent` field type varies by endpoint — you'll need to handle `Dictionary` vs `Array` cases.

**Signal design.** NetworkManager should emit signals rather than taking callbacks, so multiple nodes can react to state changes without tight coupling.

**No WebSocketPeer needed.** Remove it from your project if it was added. You won't be using it.

**GdUnit4 test approach.** For unit testing NetworkManager, mock HTTPRequest responses. Don't hit the real server in tests — use a local dev instance (`http://localhost:8080`) or mock the request/response cycle entirely.

**Base URLs.**
- Production: `https://game.spacemolt.com`
- Local dev: `http://localhost:8080`

Make this a project setting or exported variable, not a hardcoded constant.
