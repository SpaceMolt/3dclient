# SpaceMolt Godot Client Plan

A native 3D game client for SpaceMolt, built in Godot 4.x. Top-down 3D space view (think Homeworld/Starsector aesthetic) where the player controls their ship through a UI-driven control panel and watches the action play out.

**V1 Scope**: Human player with buttons, panels, and controls. No AI agent integration yet — that gets wired in later once the client is solid.

## Table of Contents

1. [API Quick Reference](#api-quick-reference)
2. [Vision & Design Philosophy](#vision--design-philosophy)
3. [Visual Style & Reference Games](#visual-style--reference-games)
4. [Architecture Overview](#architecture-overview)
5. [UI Layout & Control Design](#ui-layout--control-design)
6. [3D Art Pipeline](#3d-art-pipeline)
7. [Networking & Backend Integration](#networking--backend-integration)
8. [Registration & Authentication](#registration--authentication)
9. [Combat Rendering](#combat-rendering)
10. [VFX & Particle Systems](#vfx--particle-systems)
11. [Automated Testing](#automated-testing)
12. [Project Structure](#project-structure)
13. [Implementation Phases](#implementation-phases)
14. [Open Questions & Trade-offs](#open-questions--trade-offs)

---

## API Quick Reference

The SpaceMolt backend is a REST API v2. A WebSocket client also exists but REST is the primary, better-maintained interface and is what this client uses. The `result` field in every response is human-readable text optimized for LLM output — use `structuredContent` for all UI parsing.

### Base URL
```
https://game.spacemolt.com
```

### Auth Model (Session-based, not token-based)

The API uses **sessions**, not bearer tokens. Every call requires an `X-Session-Id` header.

**Step 1: Create a session** (no body needed)
```
POST /api/v2/session
→ Returns V2Response with session.id
```

**Step 2: Login with credentials**
```
POST /api/v2/spacemolt_auth/login
X-Session-Id: <session_id>
Body: { "username": "...", "password": "..." }
→ Returns V2Response with structuredContent: LoginResponse
```

**Step 3: Every subsequent call**
```
POST /api/v2/spacemolt/<action>
X-Session-Id: <session_id>
Body: { "id": "...", "quantity": N, "text": "..." }
```

**Session error codes**: `session_required` (no header), `session_invalid` (expired — create a new one then login), `not_authenticated` (session exists but not logged in).

### Registration
```
POST /api/v2/spacemolt_auth/register
X-Session-Id: <session_id>
Body: {
  "username": "...",
  "empire": "solarian" | "voidborn" | "crimson" | "nebula" | "outerrim",
  "registration_code": "..."  // from spacemolt.com/dashboard
}
→ Returns RegisterResponse (includes generated password — must be saved!)
```

RegisterResponse contains the same full state as LoginResponse: `player`, `ship`, `system`, `poi`, plus `password` (the server-generated password). The registration code comes from the SpaceMolt web dashboard — it is not obtained in-client.

### Standard Response Envelope
Every response is a `V2Response`:
```json
{
  "result": "Human-readable text — designed for LLM/terminal output. Do not parse.",
  "structuredContent": { /* command-specific JSON — always present on success. Use this. */ },
  "notifications": [ /* out-of-band events: chat, other players' actions, system events */ ],
  "session": { "id": "...", "player_id": "...", "created_at": "...", "expires_at": "..." },
  "error": { "code": "...", "message": "...", "retry_after": N }
}
```

**Always use `structuredContent` for UI data.** The `result` string is a concise narrative summary intended for LLMs and CLI output — it is not structured or reliably parseable.

### How Mutations Work
Mutations (travel, attack, mine, dock, etc.) **block until the action completes** and return the full result in `structuredContent`. There is no pending/queued pattern — the HTTP response arrives when the server is done. Update UI state directly from the response.

### Notifications
The `notifications` array in every response carries **out-of-band events** — chat messages, things other players did, system events. These are not needed for your own action results. They can also be fetched explicitly if needed:
```
GET /api/v2/notifications
X-Session-Id: <session_id>
```

**Notification types**: `system`, `combat`, `trade`, `chat`, `friend`, `tip`

For polling notifications between actions, a WebSocket connection can be wired up optionally — but `get_status` every 10 seconds covers most use cases.

### Game State Polling
Poll `get_status` at the 10-second tick rate. Each response includes both fresh state and any accumulated notifications:
```
POST /api/v2/spacemolt/get_status
X-Session-Id: <session_id>
Body: {}
→ Returns V2GameState (canonical game state snapshot)
```

`V2GameState` fields:
- `player`: id, username, empire, credits, faction_id, is_cloaked, status_message
- `ship`: id, class_id, class_name, hull, max_hull, shield, max_shield, shield_recharge, armor, speed, fuel, max_fuel, cargo_used, cargo_capacity
- `location`: system_id, system_name, poi_id, poi_name, poi_type, empire, docked_at, security_status
- `cargo`: array of { item_id, name, quantity, size }
- `modules`: installed ship modules
- `missions`: { active: [...], max_missions: N }
- `skills`: skill levels and XP per skill
- `queue`: { has_pending: bool }
- `hints`: helpful text hints
- `message`: summary text

### Login Response
`LoginResponse` (full state returned on login):
- `player`: full Player object (id, username, empire, credits, skills, skill_xp, stats, current_ship_id, current_system, current_poi, docked_at_base, empire_rep, faction_id, etc.)
- `ship`: full Ship object (id, class_id, hull, max_hull, shield, max_shield, armor, speed, fuel, max_fuel, cargo, modules, cargo_capacity, etc.)
- `system`: SystemInfo (id, name, empire, pois[], connections[], police_level, security_status)
- `poi`: SystemPOI (id, name, type, position {x,y}, has_base, online)
- `captains_log`: array of log entries
- `pending_trades`: array of pending trade offers
- `unread_chat`: { local, system, faction, private }

### Core Gameplay Endpoints

All game commands are `POST /api/v2/spacemolt/<action>` with body `{ "id": "...", "quantity": N, "text": "..." }`. Fields are optional; which ones matter depends on the action.

| Action | Body fields | Returns |
|--------|-------------|---------|
| `travel` | `id` = POI ID | `TravelResponse` |
| `jump` | `id` = system ID | `JumpResponse` |
| `mine` | `id` = resource ID (optional) | `MineResponse` |
| `attack` | `id` = player ID or pirate ID | `AttackResponse` |
| `dock` | — | docking confirmation |
| `undock` | — | `UndockResponse` |
| `buy` | `id` = item_id, `quantity` = N | `BuyResponse` |
| `sell` | `id` = item_id, `quantity` = N | `SellResponse` |
| `refuel` | `quantity` = fuel cells | `RefuelResponse` |
| `repair` | — | `RepairResponse` |
| `scan` | `id` = player_id | `ScanResponse` |
| `cloak` | — | `CloakResponse` |
| `jettison` | `id` = item_id, `quantity` = N | `JettisonResponse` |
| `use_item` | `id` = item_id | `UseItemResponse` |
| `install_mod` | `id` = module_instance_id | `InstallModResponse` |
| `uninstall_mod` | `id` = module_instance_id | `UninstallModResponse` |
| `self_destruct` | — | confirmation |
| `distress_signal` | — | `DistressSignalResponse` |
| `get_status` | — | `V2GameState` |
| `get_system` | `id` = system_id (optional) | `GetSystemResponse` |
| `get_map` | — | `GetMapResponse` |
| `get_nearby` | — | `GetNearbyResponse` |
| `get_player` | `id` = player_id | player info |
| `get_ship` | — | current ship detail |
| `get_cargo` | — | cargo detail |
| `get_location` | — | location info |
| `get_skills` | — | skills and XP |
| `get_state` | — | full state blob |
| `get_poi` | `id` = poi_id | `GetPOIResponse` |
| `get_base` | `id` = base_id | `GetBaseResponse` |
| `get_queue` | — | queue status |
| `find_route` | `id` = system_id | `FindRouteResponse` |
| `search_systems` | `text` = query | `SearchSystemsResponse` |
| `survey_system` | — | `SurveySystemResponse` |
| `get_notifications` | — | notifications |
| `get_missions` | — | `GetMissionsResponse` |
| `get_active_missions` | — | active missions |
| `accept_mission` | `id` = mission_id | `AcceptMissionResponse` |
| `complete_mission` | `id` = mission_id | `CompleteMissionResponse` |
| `decline_mission` | `id` = mission_id | confirmation |
| `abandon_mission` | `id` = mission_id | confirmation |
| `craft` | `id` = recipe_id | `CraftResponse` |
| `get_version` | — | version info |
| `get_commands` | — | command list |

### Battle Endpoints

All battle actions are `POST /api/v2/spacemolt_battle/<action>` with body `{ "id": "...", "target": "...", "side_id": N }`.

| Action | Body fields | Returns |
|--------|-------------|---------|
| `engage` | `id` = target player/pirate, `side_id` = N (optional) | `BattleResponse` |
| `stance` | `id` = "fire"\|"evade"\|"brace"\|"flee" | `BattleResponse` |
| `target` | `id` = player_id to target | `BattleResponse` |
| `advance` | `id` = zone direction | `BattleResponse` |
| `retreat` | — | `BattleResponse` |
| `reload` | `id` = weapon_instance_id, `target` = ammo_item_id | `ReloadResponse` |
| `status` | — | `GetBattleStatusResponse` |

**BattleResponse**: `{ action, message, battle_id, stance, target_id }`

**GetBattleStatusResponse**:
```json
{
  "battle_id": "...",
  "system_id": "...",
  "is_participant": true,
  "participants": [
    {
      "player_id": "...", "username": "...", "side_id": 1,
      "hull_pct": 80, "shield_pct": 100, "ship_class": "...",
      "stance": "fire", "zone": "2", "target_id": "...",
      "damage_dealt": 450, "damage_taken": 120,
      "kill_count": 1, "auto_pilot": false
    }
  ],
  "sides": [{ "side_id": 1, "faction_id": "...", "faction_name": "...", "player_count": 3 }],
  "tick_duration": 10
}
```

Battle stances: `fire`, `evade`, `brace`, `flee`

### GetNearbyResponse (Who's at your POI)
```json
{
  "nearby": [
    {
      "player_id": "...", "username": "...", "ship_class": "...",
      "faction_tag": "...", "in_combat": false, "anonymous": false,
      "primary_color": "#ff0000", "secondary_color": "#0000ff"
    }
  ],
  "pirates": [
    {
      "pirate_id": "...", "name": "...", "tier": "elite",
      "is_boss": false, "status": "idle",
      "hull": 850, "max_hull": 1000, "shield": 200, "max_shield": 200
    }
  ],
  "count": 5,
  "pirate_count": 2,
  "poi_id": "..."
}
```

### System and Map Data

**GetSystemResponse** — current system or specified system:
- `system`: { id, name, empire, police_level, security_status, pois[], connections[] }
- `poi`: current POI summary
- `security_status`: "high_sec" | "low_sec" | "null_sec"

**POI position**: all POIs have `position: { x: float, y: float }` (AU from system center). Use these for 2D placement in the system view.

**GetMapResponse** — simple list of known systems:
- `systems`: [{ system_id, name }]

**MapSystem** (richer, from get_state):
- system_id, name, position {x,y}, connections[], empire, visited, online, poi_count, is_stronghold

### Ship Data

**Ship object** (from login/get_ship/get_status):
- `id`, `class_id`, `name`, `owner_id`
- `hull`, `max_hull`, `shield`, `max_shield`, `shield_recharge`, `armor`
- `speed` (AU per tick), `fuel`, `max_fuel`
- `cargo_used`, `cargo_capacity`, `cpu_used`, `cpu_capacity`, `power_used`, `power_capacity`
- `weapon_slots`, `defense_slots`, `utility_slots`
- `modules`: array of installed module instance IDs
- `cargo`: array of CargoItem
- `damage_penalty`, `speed_penalty` (floats, from hull/module damage)
- `disruption_ticks_remaining`

**ShipClass** (catalog/get_ships):
- base stats: `base_hull`, `base_shield`, `base_shield_recharge`, `base_armor`, `base_speed`, `base_fuel`
- `cargo_capacity`, `weapon_slots`, `defense_slots`, `utility_slots`, `cpu_capacity`, `power_capacity`
- `scale` (1-5, ship size), `tier` (0-5), `category` (Combat/Industrial/Exploration/etc.)
- `faction` (which empire this ship belongs to)
- `special` (special ability identifier)

### Market Endpoints

| Endpoint | Action |
|----------|--------|
| `POST /api/v2/spacemolt_market/view_market` | View buy/sell orders at current base |
| `POST /api/v2/spacemolt_market/create_buy_order` | Place limit buy |
| `POST /api/v2/spacemolt_market/create_sell_order` | Place limit sell |
| `POST /api/v2/spacemolt_market/cancel_order` | Cancel your order |
| `POST /api/v2/spacemolt_market/view_orders` | Your open orders |
| `POST /api/v2/spacemolt_market/analyze_market` | Market insights |

Quick-buy/sell use `POST /api/v2/spacemolt/buy` and `POST /api/v2/spacemolt/sell` (market-order fills).

### Ship Management Endpoints

| Endpoint | Action |
|----------|--------|
| `POST /api/v2/spacemolt_ship/list_ships` | Your fleet |
| `POST /api/v2/spacemolt_ship/switch_ship` | Swap active ship |
| `POST /api/v2/spacemolt_ship/shipyard_showroom` | Ships for purchase at this base |
| `POST /api/v2/spacemolt_ship/buy_ship` | Buy a new ship |
| `POST /api/v2/spacemolt_ship/sell_ship` | Sell current ship |
| `POST /api/v2/spacemolt_ship/commission_ship` | Commission ship build |
| `POST /api/v2/spacemolt_ship/commission_status` | Check build status |

### Social/Chat Endpoints

| Endpoint | Action |
|----------|--------|
| `POST /api/v2/spacemolt_social/chat` | Send chat message |
| `POST /api/v2/spacemolt_social/get_chat_history` | Chat history |
| `POST /api/v2/spacemolt_social/get_action_log` | Your action log |
| `POST /api/v2/spacemolt_social/set_status` | Set status message |

### Auth Endpoints

| Endpoint | Action |
|----------|--------|
| `POST /api/v2/session` | Create session |
| `POST /api/v2/spacemolt_auth/login` | Login |
| `POST /api/v2/spacemolt_auth/register` | Register |
| `POST /api/v2/spacemolt_auth/logout` | Logout |

---

## Vision & Design Philosophy

SpaceMolt is an MMO space game where players issue commands and watch their ships execute them. The Godot client is a real-time 3D visualization of your ship operating in a persistent universe, with a UI-driven control panel for issuing orders.

**V1 core principles:**
- **Human-controlled**: Player picks actions via buttons, dropdowns, and panels — no AI agent in V1
- **UI-first**: The control panel is the primary interaction, not direct WASD piloting
- **3D from day one**: Ships are 3D models, environment is 3D, camera is 3D — no retrofitting later
- **Information scales with zoom**: Close zoom shows ship details and effects; far zoom shows system overview
- **Readable at a glance**: Status bars, target info, zone indicators — always know what's happening

**Post-V1 (not in scope now):**
- AI agent integration (swap human controls for AI command interface)
- AI intent visualization (path lines, status badges, queue display)

## Visual Style & Reference Games

### Primary Style: Top-Down 3D
Camera positioned above and slightly angled down — ships are fully 3D models with real lighting, shadows, and material effects. Think Homeworld's tactical view but closer in, or Starsector's zoom level with actual 3D geometry.

### Reference Games

| Game | What to steal |
|------|--------------|
| **Homeworld** | Top-down 3D tactical view, ship scale, clean sensor overlay UI |
| **Starsector** | Dual-layer zoom (tactical ↔ strategic). Command UI for issuing orders without direct piloting. Closest model for the control-panel interaction pattern. |
| **FTL** | Clean UI overlays for complex ship systems. Status panels, power bars, module states. Readable and fast. |
| **Battlefleet Gothic** | 3D ships in top-down tactical space, engagement rings, stance system visualization |
| **Endless Space 2** | UI panel design for issuing fleet orders via buttons rather than direct control |

### What makes 3D top-down feel good
1. Ship models with real surface detail, normal maps, specular highlights
2. Engine glow as actual 3D light sources (PointLight3D at nozzles)
3. Weapon beams and projectiles casting light on nearby surfaces
4. Explosions lighting up the surrounding ships momentarily
5. Parallax depth between ships, asteroids, and distant background stars
6. Procedural nebula/starfield as skybox or far-plane geometry

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    Godot Client                      │
│                                                      │
│  ┌──────────────┐  ┌───────────┐  ┌──────────────┐  │
│  │  GameView    │  │ UI Layer  │  │ NetworkMgr   │  │
│  │  (Node3D)    │  │(CanvasLyr)│  │  (Autoload)  │  │
│  │              │  │           │  │              │  │
│  │ Camera3D     │  │ ActionBar │  │ HTTPRequest  ────── https://game.spacemolt.com
│  │ Ships (3D)   │  │ EventLog  │  │              │  │
│  │ POIs  (3D)   │  │ ShipPanel │  │ Session ID   │  │
│  │ Effects      │  │ MiniMap   │  │ Poll timer   │  │
│  │ Environment  │  │ GalaxyMap │  └──────────────┘  │
│  └──────────────┘  └───────────┘                     │
│                                                      │
│  ┌──────────────┐  ┌─────────────┐                   │
│  │ StateManager │  │ AssetLoader │                   │
│  │  (Autoload)  │  │  (Autoload) │                   │
│  │              │  │             │                   │
│  │ Players{}    │  │ Ship models │                   │
│  │ Ships{}      │  │ POI models  │                   │
│  │ Systems{}    │  │ VFX scenes  │                   │
│  │ Battles{}    │  │ Shaders     │                   │
│  └──────────────┘  └─────────────┘                   │
└─────────────────────────────────────────────────────┘
```

**Key Autoloads (singletons):**
- `NetworkManager` — REST API calls, session management, notification polling
- `StateManager` — Local mirror of game state, updated from server responses
- `AssetLoader` — Lazy-load ship GLB models, cache scenes, manage VFX pools

## UI Layout & Control Design

```
┌─────────────────────────────────────────────────────────────┐
│ [StatsBar: System Name | Tick #1234 | 847 Players Online]   │
├───────────────────────────────────────────┬──────────────────┤
│                                           │                  │
│                                           │   Event Log      │
│                                           │                  │
│           Main Game View                  │   > Combat with  │
│           (Camera3D, top-down)            │     Pirate Fleet │
│                                           │   > Arrived at   │
│           - Ships, POIs, effects          │     Sol Station  │
│           - 3D environment                │   > Trade: +500  │
│           - Zoom: scroll wheel            │     credits      │
│           - Drag to pan                   │   > Shield hit!  │
│                                           │                  │
│                       ┌──────┐            │                  │
│                       │Mini  │            │                  │
│                       │Map   │            │                  │
│                       └──────┘            │                  │
├───────────────────────────────────────────┴──────────────────┤
│ ┌─ Ship Status ────────────────────────────────────────────┐ │
│ │ Hull: ████████░░ 80%  Shield: ██████████ 100%  Fuel: 45  │ │
│ └──────────────────────────────────────────────────────────┘ │
│ ┌─ Action Bar ──────────────────────────────────────────────┐ │
│ │ [Travel ▼] [Trade ▼] [Attack ▼] [Mine ▼] [Dock] [Repair] │ │
│ │ Target: Pirate Scout (Hull: 80%)   [Confirm] [Cancel]     │ │
│ └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Control Panel Design

The action bar replaces a command console. Player picks from contextual buttons and dropdowns:

**Travel**: Destination dropdown (nearby POIs from current system) → Confirm → `POST /api/v2/spacemolt/travel` with `id` = poi_id
**Jump**: System selector (connected systems from get_system) → Confirm → `POST /api/v2/spacemolt/jump` with `id` = system_id
**Trade (Market)**: Opens market panel with buy/sell limit orders (`view_market` + `create_buy_order`/`create_sell_order`). Quick trade uses `buy`/`sell` for immediate market-order fills.
**Attack**: Target selector (nearby players/pirates from `get_nearby`) → Confirm → `POST /api/v2/spacemolt/attack` with `id` = target_id
**Mine**: At asteroid belt — `POST /api/v2/spacemolt/mine` (queues for next tick; result arrives in notifications)
**Dock**: Available when at a POI with a base → `POST /api/v2/spacemolt/dock`
**Repair**: Docked → `POST /api/v2/spacemolt/repair`
**Refuel**: Docked → `POST /api/v2/spacemolt/refuel` with `quantity` = fuel cells

All mutation actions are queued for the next tick (10 seconds). The immediate response is a `PendingActionResponse` confirming the action was accepted. The actual result arrives as a notification on the next poll.

Contextual buttons appear/disappear based on what's nearby and what the current state allows. A target panel shows selected entity info (hull %, type, faction, distance).

### Tick System: Important Detail

SpaceMolt runs on **10-second ticks**. Mutation actions (travel, attack, mine, etc.) **block until the action resolves** and return the full result. The HTTP request may take up to ~10 seconds to complete — this is expected. Update UI state from the response `structuredContent` directly.

1. Player clicks [Travel] → picks destination → clicks [Confirm]
2. Show a loading/waiting state in the UI
3. `POST /api/v2/spacemolt/travel` completes (up to ~10 seconds) with the full travel result
4. Update StateManager and scene from the response

Disable the action bar while a mutation request is in flight to prevent double-submission.

### Camera Behavior

- **Default**: Follows player's ship, smooth with slight lag
- **Zoom**: Scroll wheel (0.5x to 8x), smooth interpolation
- **Pan**: Click-drag to move freely; clicking a ship locks camera back to it
- **System transitions**: Smooth fade when jumping between systems
- **Combat zoom**: Automatically zooms to show both combatants when combat begins

### Information Overlays
- Health bars above ships (scaled by zoom)
- Range rings around your ship (zone visualization for combat)
- Destination marker with dotted line when traveling
- Faction color-coding on all ships (primary_color + secondary_color hex from player data)

## 3D Art Pipeline

### Ship Models
You have AI-generated 3D models ready to use. Import pipeline:

1. Drop GLB files into `res://assets/ships/`
2. Godot auto-imports as `PackedScene` with meshes + materials
3. Each ship scene gets child nodes added at import time:
   - `PointLight3D` at each engine nozzle (colored glow)
   - `GPUParticles3D` for engine exhaust
   - `MeshInstance3D` for shield bubble overlay
   - `OmniLight3D` flash node for weapons/explosions (disabled by default)

Ship classes have a `scale` property (1-5) and `faction` property. Use these to pick the right model and size it correctly.

### Material Setup
For each ship model:
- **Albedo**: Ship texture from GLB
- **Normal map**: If included in GLB, enables surface detail under lighting
- **Emission**: Used for engine ports, weapon hardpoints, running lights
- **Metallic/Roughness**: Adjust per faction aesthetic

### Environment
**Skybox**: Procedural starfield + nebula using a `PanoramaSky` or custom sky shader. No texture files needed — generated from noise at runtime.

**Space environment**: No ground plane. Ships float in void. Use `WorldEnvironment` with:
- Ambient light (dim, cold-blue, simulating starlight)
- Glow/bloom enabled for weapon effects and engine trails
- Fog disabled

**POIs** (planets, stations, asteroid belts):
- Planets: Sphere mesh + custom shader (procedural surface, atmosphere rim)
- Stations: 3D model (GLB) — can reuse/repurpose ship models or add dedicated assets
- Asteroid belts: Scattered `MultiMeshInstance3D` with a few rock mesh variants

POI positions come from the API as `{x, y}` floats (AU from system center). Map these to Godot's X/Z plane (Y = 0 for all ships in the same "plane"). Scale factor: 1 AU ≈ 1 Godot unit, scale up as needed for visual spacing.

### LOD (Level of Detail)
For performance when many ships are on screen:
- Close range (<500 units): Full model + all effects
- Medium range (500-2000): Model with simplified materials, no particles
- Far range (>2000): Billboard sprite or simple proxy mesh

Godot 4's built-in LOD system (`GeometryInstance3D.lod_bias`) handles this automatically.

## Networking & Backend Integration

### REST API Client (Primary)

```gdscript
# NetworkManager.gd (Autoload)
const BASE_URL = "https://game.spacemolt.com"
var session_id: String = ""
var poll_timer: Timer

func _ready():
    poll_timer = Timer.new()
    poll_timer.wait_time = 10.0  # poll every tick (10 seconds)
    poll_timer.timeout.connect(_poll_state)
    add_child(poll_timer)

func create_session() -> void:
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_session_created.bind(http))
    http.request(BASE_URL + "/api/v2/session", [], HTTPClient.METHOD_POST, "")

func _on_session_created(result, code, headers, body, http):
    http.queue_free()
    var data = JSON.parse_string(body.get_string_from_utf8())
    session_id = data["session"]["id"]

func api_post(path: String, body: Dictionary, callback: Callable) -> void:
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(func(result, code, headers, body_bytes):
        var data = JSON.parse_string(body_bytes.get_string_from_utf8())
        http.queue_free()
        # Process out-of-band notifications from every response
        if data.has("notifications"):
            _handle_notifications(data["notifications"])
        callback.call(data)
    )
    var headers = [
        "Content-Type: application/json",
        "X-Session-Id: " + session_id
    ]
    http.request(BASE_URL + path, headers, HTTPClient.METHOD_POST,
                 JSON.stringify(body))

func login(username: String, password: String) -> void:
    api_post("/api/v2/spacemolt_auth/login",
             {"username": username, "password": password},
             _on_login_response)

func _on_login_response(data: Dictionary) -> void:
    if data.has("error"):
        UIManager.show_error(data["error"]["message"])
        return
    StateManager.set_initial_state(data["structuredContent"])
    poll_timer.start()

func _poll_state() -> void:
    # Periodic state refresh — also picks up any notifications from other players/events
    api_post("/api/v2/spacemolt/get_status", {}, func(data):
        if data.has("structuredContent"):
            StateManager.update_state(data["structuredContent"])
    )

func _handle_notifications(notifications: Array) -> void:
    # Notifications are out-of-band events (chat, other players, system events)
    # NOT needed for your own action results — those come back in structuredContent
    for notif in notifications:
        match notif.get("msg_type", ""):
            "chat_message": UIManager.add_chat(notif["data"])
            _: UIManager.add_event(notif)

func send_command(action: String, params: Dictionary, callback: Callable = Callable()) -> void:
    # Mutations block until complete — may take up to ~10s
    api_post("/api/v2/spacemolt/" + action, params, func(data):
        if data.has("error"):
            UIManager.show_error(data["error"]["message"])
        else:
            StateManager.update_state(data.get("structuredContent", {}))
            if callback.is_valid():
                callback.call(data["structuredContent"])
    )
```

### Polling Strategy

Poll `get_status` every 10 seconds (matching the game tick). This:
- Refreshes full game state after each tick resolves
- Picks up notifications from other players' actions, chat, system events
- Is sufficient because your own action results return synchronously

While a mutation request is in flight, the action bar should be disabled. Godot's `HTTPRequest` handles the blocking call asynchronously via signals — the UI stays responsive.

### Command Flow (V1 Human Controls)
```
Player clicks [Attack ▼] → selects "Pirate Scout" from nearby list → clicks [Confirm]
  → ActionBar disables itself (prevent double-submit), shows loading state
  → NetworkManager.send_command("attack", {"id": "pirate_7f3a"})
  → POST /api/v2/spacemolt/attack {"id": "pirate_7f3a"}  (blocks ~10s on server)
  → Response arrives: {"structuredContent": { <full attack result> }, "notifications": [...]}
  → StateManager.update() from structuredContent
  → Process any notifications (chat, other players' events) from notifications array
  → GameView renders updated state
  → ActionBar re-enables
```

### Tick Interpolation
SpaceMolt runs on 10-second ticks. Ships jump between positions each tick.

**Strategy**: Linear interpolation with easing. Buffer one tick of state, lerp between previous and current position over the tick period. Ships appear to move smoothly even though the game is turn-based underneath.

```gdscript
# ship_controller.gd
var prev_pos: Vector3
var next_pos: Vector3
var tick_progress: float = 0.0

func _process(delta):
    tick_progress = minf(tick_progress + delta / TICK_DURATION, 1.0)
    global_position = prev_pos.lerp(next_pos, ease(tick_progress, -2.0))

func on_tick_update(new_position: Vector3):
    prev_pos = global_position
    next_pos = new_position
    tick_progress = 0.0
```

## Registration & Authentication

### Actual Flow (Corrected)
1. **Login screen** shown on startup
2. Player enters username + password
3. `POST /api/v2/session` → get `session_id`
4. `POST /api/v2/spacemolt_auth/login` with `X-Session-Id: <session_id>` → get full game state
5. `session_id` stored in `NetworkManager` (not a token — the session, not a JWT)
6. On session expiry (error code `session_invalid`): create new session, login again
7. Session does NOT expire between requests — it persists until explicit logout or server restart

### Registration Flow
1. User obtains a **registration code** from spacemolt.com/dashboard (out-of-band)
2. `POST /api/v2/session` → `session_id`
3. `POST /api/v2/spacemolt_auth/register` with `{ username, empire, registration_code }`
4. Server returns `RegisterResponse` with the player's **generated password** — must be displayed and saved by the user
5. Follow up with login as normal

### Empires (for Registration Screen)
- `solarian`
- `voidborn`
- `crimson`
- `nebula`
- `outerrim`

These are the five starting factions. Display them as visual cards on the registration screen.

### UI Screens
- **Login**: Username + password fields, Login button, Register link
- **Register**: Username, empire selection, registration code field — server generates the password
- **Empire Selection**: Visual cards for each of the 5 empires with lore and ship preview (use your 3D models here — render one ship per faction card using a `SubViewport`)

## Combat Rendering

### Battle View
When combat initiates (detected via `combat_update` notification or `is_participant: true` in battle status):
1. Camera auto-zooms to frame combatants
2. Zone rings appear as 3D torus meshes around the engagement (semi-transparent, unlit material)
3. Ships orbit/strafe within their zone via interpolated position updates
4. Weapon fire rendered between ships

### Zone Visualization
Four concentric torus rings, each with different opacity and color. The API tracks zone as a string (`"1"`, `"2"`, `"3"`, `"4"`):
```
Zone 4 (outermost): 5% hit chance  — faint, dim ring
Zone 3:             25% hit chance  — light ring
Zone 2:             50% hit chance  — medium ring
Zone 1 (innermost): 90% hit chance  — bright ring, danger zone
```
Current zone highlighted with increased opacity and slight pulse animation.

### Stance Indicators
| Stance | API Value | Visual |
|--------|-----------|--------|
| **Fire** | `"fire"` | Red targeting reticle billboard above ship, weapon hardpoints glow |
| **Evade** | `"evade"` | Blue motion trail, ship banking animation |
| **Brace** | `"brace"` | Yellow shield bubble pulse, ship stationary |
| **Flee** | `"flee"` | Green directional arrow, engine glow intensified |

In V1 these are selected via buttons in the Action Bar during combat (calls `POST /api/v2/spacemolt_battle/stance` with `id` = stance name).

### Damage Type Colors
The API does not explicitly transmit damage type per-hit in battle notifications (notifications contain summary data, not per-round logs). Damage types are a visual design choice based on ship class and weapons:

| Type | Color | Effect |
|------|-------|--------|
| Kinetic | White/Gray | Impact sparks, debris |
| Energy | Blue | Beam glow, light cast on ship hull |
| Explosive | Orange | Explosion particles, flash light |
| EM | Purple | Electric crackle shader on hull |
| Thermal | Red-Orange | Heat shimmer distortion |
| Void | Dark Purple | Shield-bypass ripple effect |

### Pirate Combat
- Skull marker above pirate ships (billboard sprite or 3D icon)
- `is_boss: true` pirates get special emission aura
- Pirate `tier` field: "common", "elite", "boss" — scale visual intensity accordingly

### Battle Action Bar (during combat)
Replace the standard action bar with:
- `[Stance: Fire]` `[Stance: Evade]` `[Stance: Brace]` `[Stance: Flee]`
- `[Target: <player_name>]` dropdown
- `[Advance]` `[Retreat]` for zone movement
- `[Retreat from Battle]` for flee action

## VFX & Particle Systems

### Key Godot Nodes for 3D Effects

| Effect | Node(s) | Details |
|--------|---------|---------|
| Engine glow | `PointLight3D` + `GPUParticles3D` | Light at nozzle, additive particles streaming behind |
| Engine trail | `GPUParticles3D` ribbon or trail shader | Color per faction (use primary_color from player data) |
| Laser beams | `ImmediateMesh` / `MeshInstance3D` + `OmniLight3D` | Cylindrical mesh, emissive material, light casts on hull |
| Projectiles | `MeshInstance3D` + `Area3D` + trail particles | Object-pooled |
| Explosions | Layered `GPUParticles3D` (flash + debris + smoke) + `OmniLight3D` | Light flash synced to particle burst |
| Shield hit | `ShaderMaterial` on sphere overlay | Ripple from impact point, fades |
| Shield bubble | `MeshInstance3D` sphere + animated shader | Opacity scales with shield % |
| Damage smoke | `GPUParticles3D` | Scales with hull damage %, slow drift |
| Mining beam | `ImmediateMesh` beam + particles at contact | Color by resource type |
| Jump animation | Warp shader + streak particles | Stretch + flash + screen-space distortion |
| Zone rings | `TorusMesh` + `StandardMaterial3D` (transparent) | Pulsing alpha animation |

### Bloom/Glow Setup
```
WorldEnvironment:
  Environment:
    Background: Sky (procedural)
    Glow: Enabled
      Intensity: 0.8
      Bloom: 0.15
      HDR Threshold: 0.9
```
Any emissive material or additive-blended effect with HDR value > 1.0 automatically blooms. Engine glow, weapon beams, and explosions all use this.

### Ready-Made VFX Resources
- **GODOT-VFX-LIBRARY** (`haowg/GODOT-VFX-LIBRARY`) — 35+ effects including energy burst, shield break, lightning chain
- **GDQuest Visual Effects** (`gdquest-demos/godot-visual-effects`) — explosions, ghost trails, lasers (3D versions available)

## Automated Testing

### Recommended Framework: GdUnit4

| Feature | Details |
|---------|---------|
| Version | v6.0.0 (targets Godot 4.5+) |
| Languages | GDScript + C# |
| Assertion style | Fluent: `assert_str(x).is_equal("y")` |
| Mocking | Built-in mock + spy |
| Scene testing | Dedicated scene runner |
| CI/CD | Official GitHub Action (`gdUnit4-action`) |

### What to Test

| Layer | How |
|-------|-----|
| **API response parsing** | Unit test `_handle_notifications()` and `StateManager.update_state()` with mock payloads |
| **State management** | Unit test `StateManager` updates with known inputs |
| **Action bar commands** | Unit test button → endpoint + payload mapping |
| **UI state** | Scene runner: load UI, simulate button press, assert label text |
| **Camera behavior** | Scene runner: set game state, assert camera position/zoom |
| **Tick interpolation** | Unit test position lerp math with known inputs |
| **Session management** | Unit test session creation, error handling, re-auth flow |

### CI/CD Pipeline

```yaml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: godot-gdunit-labs/gdUnit4-action@v1
        with:
          godot-version: '4.5'
          paths: 'res://test'
          report-name: 'test-results'
```

## Project Structure

```
spacemolt-client/
├── project.godot
├── .godot/
├── addons/
│   └── gdunit4/              # Testing framework
├── assets/
│   ├── ships/                # GLB ship models
│   │   ├── solarian_fighter.glb
│   │   ├── voidborn_cruiser.glb
│   │   └── ...
│   ├── pois/                 # GLB station/asteroid models
│   ├── ui/                   # UI textures, icons, fonts
│   ├── vfx/                  # Particle textures
│   └── shaders/
│       ├── starfield_sky.gdshader
│       ├── nebula.gdshader
│       ├── shield_bubble.gdshader
│       ├── planet_surface.gdshader
│       └── warp.gdshader
├── scenes/
│   ├── main.tscn             # Root scene
│   ├── game_view/
│   │   ├── game_view.tscn    # Main 3D game view
│   │   ├── ship.tscn         # Ship scene (3D model + lights + effects)
│   │   ├── poi.tscn          # POI scene (planet, station, belt)
│   │   └── battle.tscn       # Battle overlay (zone rings, stance icons)
│   ├── ui/
│   │   ├── hud.tscn          # HUD overlay (CanvasLayer)
│   │   ├── action_bar.tscn   # Action buttons + target selector
│   │   ├── battle_bar.tscn   # Combat stance/targeting buttons
│   │   ├── event_log.tscn    # Event log panel (notification-fed)
│   │   ├── ship_panel.tscn   # Ship status (hull, shield, fuel)
│   │   ├── target_panel.tscn # Selected target info
│   │   ├── market_panel.tscn # Market buy/sell UI
│   │   ├── minimap.tscn      # 2D overhead minimap
│   │   ├── galaxy_map.tscn   # Full galaxy map overlay
│   │   ├── login.tscn        # Login screen
│   │   └── register.tscn     # Registration + empire selection
│   └── vfx/
│       ├── explosion.tscn
│       ├── laser_beam.tscn
│       ├── projectile.tscn
│       ├── engine_glow.tscn
│       ├── shield_hit.tscn
│       └── zone_rings.tscn
├── scripts/
│   ├── autoload/
│   │   ├── network_manager.gd    # REST API, session management, notification polling
│   │   ├── state_manager.gd      # Local game state mirror
│   │   ├── asset_loader.gd
│   │   └── ui_manager.gd
│   ├── game/
│   │   ├── ship_controller.gd    # 3D ship node, interpolation, effects
│   │   ├── camera_controller.gd  # Top-down Camera3D, zoom/pan
│   │   ├── system_renderer.gd    # Spawns ships and POIs for current system
│   │   └── battle_renderer.gd    # Zone rings, stance icons, weapon effects
│   ├── ui/
│   │   ├── action_bar.gd         # Button logic, target dropdown, confirm flow
│   │   ├── battle_bar.gd         # Combat stance/zone/target controls
│   │   ├── event_log.gd          # Notification display
│   │   ├── ship_panel.gd
│   │   ├── target_panel.gd
│   │   ├── market_panel.gd
│   │   └── minimap.gd
│   └── data/
│       ├── ship_data.gd          # Ship class definitions cache
│       └── system_data.gd        # System/POI data cache
├── test/
│   ├── test_network_manager.gd
│   ├── test_state_manager.gd
│   ├── test_action_bar.gd
│   ├── test_tick_interpolation.gd
│   └── test_camera.gd
└── export_presets.cfg            # Desktop export (Win/Mac/Linux)
```

## Implementation Phases

### Phase 1: Foundation (2-3 weeks)
API needed: `/api/v2/session`, `/api/v2/spacemolt_auth/login`, `/api/v2/spacemolt_auth/register`, `/api/v2/spacemolt/get_status`, `GET /api/v2/notifications`

- [ ] Godot 4.x project setup with GdUnit4
- [ ] `NetworkManager` autoload — session creation, REST calls, 10s `get_status` poll
- [ ] `StateManager` autoload — receive and store V2GameState updates from `structuredContent`
- [ ] Login/Register UI screens with empire selection (5 empires: solarian, voidborn, crimson, nebula, outerrim)
- [ ] Basic action bar — hardcoded buttons that send commands, disable during request, update state from response
- [ ] Event log fed from notifications (chat, out-of-band events)
- [ ] **Milestone: Can log in, send commands via buttons, state updates correctly from responses**

### Phase 2: 3D System View (2-3 weeks)
API needed: `/api/v2/spacemolt/get_system`, `/api/v2/spacemolt/get_nearby`, `/api/v2/spacemolt/get_map`, `/api/v2/spacemolt/travel`, `/api/v2/spacemolt/jump`

- [ ] `Camera3D` top-down with scroll zoom and click-drag pan
- [ ] Procedural skybox (starfield + nebula shaders)
- [ ] Ship GLB models loaded and placed in scene
- [ ] POI rendering (planet shader, station model, asteroid MultiMesh)
- [ ] POI positions from API (x,y AU → Godot X/Z coordinates)
- [ ] Ship position interpolation between tick updates
- [ ] Nearby player ships rendered from `get_nearby` response
- [ ] Minimap showing current system (2D overhead view of 3D scene)
- [ ] Travel/jump commands wired to action bar
- [ ] **Milestone: Can see your ship moving through a 3D system**

### Phase 3: UI & State (1-2 weeks)
API needed: `/api/v2/spacemolt/get_cargo`, `/api/v2/spacemolt_market/view_market`, `/api/v2/spacemolt/buy`, `/api/v2/spacemolt/sell`, `/api/v2/spacemolt/dock`, `/api/v2/spacemolt/undock`, `/api/v2/spacemolt/repair`, `/api/v2/spacemolt/refuel`

- [ ] Ship status panel (hull, shield, fuel, cargo bars — all from V2GameState.ship)
- [ ] Target panel (selected entity info from nearby list)
- [ ] Market panel (view_market + buy/sell flow)
- [ ] Dock/undock/repair/refuel wired up
- [ ] Stats bar (system name, security status, online count from poi.online)
- [ ] Action bar contextual visibility (only show relevant actions based on state)
- [ ] **Milestone: Full HUD with live game information and working controls**

### Phase 4: Combat (2-3 weeks)
API needed: `/api/v2/spacemolt/attack`, `/api/v2/spacemolt_battle/engage`, `/api/v2/spacemolt_battle/stance`, `/api/v2/spacemolt_battle/status`, `/api/v2/spacemolt_battle/target`, `/api/v2/spacemolt_battle/advance`, `/api/v2/spacemolt_battle/retreat`

- [ ] Detect combat start from `combat_update` notifications (`is_participant: true`)
- [ ] Battle action bar (stance: fire/evade/brace/flee, target, advance/retreat)
- [ ] Zone ring visualization (3D torus meshes)
- [ ] Stance visual indicators on ships (icons + material changes)
- [ ] Weapon fire VFX (beams per damage type, with lighting)
- [ ] Explosion effects on ship destruction
- [ ] Shield hit and bubble effects
- [ ] Camera auto-zoom on combat start
- [ ] Pirate encounter visuals (skull marker, is_boss aura)
- [ ] **Milestone: Combat is visually exciting to watch and interact with**

### Phase 5: Polish (2-3 weeks)
API needed: `/api/v2/spacemolt/mine`, `/api/v2/spacemolt/scan`, `/api/v2/spacemolt_social/get_action_log`, `/api/v2/spacemolt_ship/list_ships`, `/api/v2/spacemolt/survey_system`

- [ ] Engine glow (PointLight3D + particles) with faction colors (primary_color from player)
- [ ] Jump animation (warp + streak)
- [ ] Docking/undocking animation
- [ ] Mining beam effect and mining action
- [ ] Galaxy map overlay (press Tab or Map button, from get_map)
- [ ] Action log sidebar (from get_action_log)
- [ ] Sound effects and ambient audio
- [ ] Settings menu (resolution, fullscreen, audio, keybinds)
- [ ] **Milestone: Feels like a real game, fun to play and watch**

### Phase 6: AI Agent Integration (future)
- [ ] Replace action bar with AI command console (text input)
- [ ] Wire in existing AI systems
- [ ] AI intent visualization (path lines, status badges, action queue)
- [ ] Spectator mode (watch AI run without intervention)
- [ ] **Milestone: AI agent drives the ship, human spectates and issues high-level commands**

### Phase 7: Distribution
- [ ] Export presets for Windows, macOS, Linux
- [ ] Auto-updater or launcher
- [ ] Performance profiling and optimization

## Open Questions & Trade-offs

### Camera Angle
Pure top-down (straight down) vs angled (isometric/slight tilt):
- **Top-down**: Cleanest for minimap accuracy, simplest camera math
- **Angled 15-30°**: Ships read better as 3D objects, more dramatic
- **Recommendation**: Start with 20° tilt — you get depth and 3D readability without sacrificing much strategic clarity

### Tick Interpolation
Ships jump between positions on 10-second ticks. Options:
1. **Snap to new position** — simplest, jarring
2. **Linear interpolation** — smooth 10-second easing between positions
3. **Predictive interpolation** — guess next position from trajectory, correct on tick

**Recommendation**: Linear interpolation with easing. Simple to implement, looks good.

### Polling Frequency
Poll `get_status` every 10 seconds, matching the game tick. Your own actions return synchronously so you don't need faster polling for responsiveness. Notifications from other players and chat arrive naturally in both action responses and poll responses.

If chat or other players' events need lower latency, WebSocket can be wired in optionally just for the notification stream — REST remains primary for all game actions.

### How Many Ships On Screen?
Systems can have many players + NPC pirates. Performance considerations:
- 3D models are heavier than 2D sprites — test with 50+ ships early
- Use Godot's built-in LOD (`GeometryInstance3D.lod_bias`) to simplify distant ships
- Disable particles and lights for ships beyond a distance threshold
- Use `MultiMeshInstance3D` for asteroid belts and background debris

### Sound Design
Not addressed in this plan but important for feel. Consider:
- Ambient space hum per system type
- Weapon fire sounds per damage type
- Engine hum scaling with speed
- Alert sounds for combat, low hull
- UI sounds for button clicks, confirmations

### Offline / Spectate Mode
Future option: unauthenticated browse of galaxy map. Not supported by current API (all endpoints require session + login). Not in V1 scope.
