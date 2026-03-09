# API Discrepancies: OpenAPI Spec vs Real Responses

Collected by testing against `https://game.spacemolt.com` on 2026-03-08, API version 0.188.0.

---

## `get_status` (V2GameState)

### `location.docked_at` — can be `null` instead of absent

The spec implies `docked_at` is a `string`. In practice, when the player is not docked, the API may return `"docked_at": null` rather than omitting the field or returning an empty string. Client code must handle null values.

### `location` — 6 extra fields not in spec

The spec defines `V2GameState.location` with 8 fields. The real response includes all 8 **plus** 6 additional fields:

| Extra field | Type | Notes |
|---|---|---|
| `connections` | `string[]` | System connection IDs (e.g. `["node_alpha", "node_beta"]`). Note: these are just string IDs, unlike `GetSystemResponse.system.connections` which has `{system_id, name, distance}` objects. |
| `nearby_player_count` | `int` | Count of nearby players |
| `nearby_players` | `object[]` | Full nearby player list (same shape as `GetNearbyResponse.nearby`) |
| `nearby_pirate_count` | `int` | Count of nearby pirates |
| `nearby_pirates` | `object[]` | Full nearby pirate list (same shape as `GetNearbyResponse.pirates`) |
| `resources` | `array` | Resources at current POI (observed as `[]` at a station) |

**Impact**: This means `get_status` now returns nearby data inline — a separate `get_nearby` call may be redundant if the client reads from `location.nearby_players` and `location.nearby_pirates`.

### `player` — 3 extra fields, 2 missing fields

Extra fields in real response (not in spec):
| Field | Type | Notes |
|---|---|---|
| `home_poi` | `string` | Player's home POI ID |
| `home_system` | `string` | Player's home system ID |
| `stats` | `object` | Full player stats (ships_destroyed, ore_mined, etc.) |

Missing from real response (in spec but not returned):
| Field | Notes |
|---|---|
| `faction_id` | Not present when player has no faction (may appear when in a faction) |
| `faction_rank` | Not present when player has no faction |

### `ship` — 8 extra fields not in spec

The spec defines 14 ship fields for `V2GameState.ship`. The real response includes all 14 **plus** 8 additional fields:

| Extra field | Type | Notes |
|---|---|---|
| `cpu_capacity` | `int` | Total CPU capacity |
| `cpu_used` | `int` | CPU currently used by modules |
| `defense_slots` | `int` | Number of defense module slots |
| `name` | `string` | Ship class display name (e.g. "Threshold") |
| `power_capacity` | `int` | Total power capacity |
| `power_used` | `int` | Power currently used by modules |
| `utility_slots` | `int` | Number of utility module slots |
| `weapon_slots` | `int` | Number of weapon module slots |

### `modules` — present but not documented in V2GameState spec

The real response includes a `modules` array with installed module details. The spec lists `modules` as a property but doesn't define the item schema. Real items have:
```json
{
  "cpu_usage": 2,
  "module_id": "...",
  "name": "Mining Laser I",
  "power_usage": 5,
  "quality": 1,
  "quality_grade": "Standard",
  "size": 10,
  "stats": { "mining_power": 5, "mining_range": 5 },
  "type": "mining",
  "type_id": "mining_laser_i",
  "wear": 0,
  "wear_status": "Pristine"
}
```

### `version` — present but not in spec

Real response includes `"version": "0.188.0"` at the top level.

---

## `LoginResponse`

### Top-level — 2 extra fields, 2 missing fields

Extra fields in real response (not in spec):
| Field | Type | Notes |
|---|---|---|
| `session_id` | `string` | The session ID (redundant with the envelope `session.id`) |
| `username` | `string` | The logged-in username (redundant with `player.username`) |

Missing from real response (in spec but not returned):
| Field | Notes |
|---|---|
| `captains_log` | Not present in real response (may have been moved or deprecated) |
| `unread_chat` | Not present in real response |

### `LoginResponse.ship` — uses full Ship schema

The login response returns the full `Ship` object (25 fields), not the slimmed-down `V2GameState.ship` (14 fields in spec). Several fields from the full `Ship` spec are also absent from the real response:

| Missing from real | Notes |
|---|---|
| `active_buffs` | May only appear during combat or with active effects |
| `damage_penalty` | May only appear when damaged |
| `disruption_ticks_remaining` | May only appear when disrupted |
| `docked_at_base` | May be omitted when not relevant (docking info is in location) |
| `last_process_tick` | Internal server field, may be intentionally omitted |
| `manifests` | May only appear with cargo manifests |
| `speed_penalty` | May only appear when penalized |

### `LoginResponse.player` — many more fields than V2GameState.player

The login player object is the full `Player` with ~30 fields (created_at, experience, discovered_systems, skill_xp, etc.), while `V2GameState.player` returns a slimmed-down ~13-field version. This is expected and documented.

---

## `GetNearbyResponse`

**Spec matches real response.** All fields present and accounted for: `count`, `nearby`, `pirate_count`, `pirates`, `poi_id`.

### Nearby player items — extra fields not in spec

| Extra field | Type | Notes |
|---|---|---|
| `primary_color` | `string` | Already in spec |
| `secondary_color` | `string` | Already in spec |

These are actually in the spec — no discrepancy. `GetNearbyResponse` matches cleanly.

---

## `GetSystemResponse`

**Spec matches real response structure.** Returns `action`, `poi`, `security_status`, `system` as expected.

No discrepancies observed.

---

## `RegisterResponse`

### Not defined in OpenAPI spec

The `RegisterResponse` schema is not present in `openapi.json`. The real response shape is essentially `LoginResponse` + `password` + `empire` + `player_id` fields.

Extra fields beyond LoginResponse:
| Field | Type | Notes |
|---|---|---|
| `password` | `string` | Server-generated password — critical, must be saved |
| `empire` | `string` | Chosen empire |
| `player_id` | `string` | New player ID |

---

## Mutation Responses

### Mutations don't return V2GameState

The PLAN.md and STARTING_POINT.md say "Mutations block until complete and return the full result in `structuredContent`" — but the `structuredContent` is **not** a V2GameState. Each mutation returns its own minimal response:

| Command | `structuredContent` keys | Notes |
|---|---|---|
| `undock` | `action` | Just `{"action": "undock"}` — no location, no ship, no state |
| `dock` | `action`, `base`, `station_condition`, `story` | Includes flavor text and station condition, but no game state |
| `travel` | `action`, `poi_id`, `poi`, `online_players`, `online_players_count`, `online_players_truncated` | `poi` is a string name, not a POI object |
| `mine` | `action` (when successful) | Errors with `"Resources depleted"` when POI has no resources. Successful mining adds to cargo. |
| `repair` | `action` (when successful) | Errors with `hull_full` / `"Hull is already at maximum integrity"` when hull is full |
| `refuel` | `action` (when successful) | Accepts `quantity` param |

**Impact**: Calling `StateManager.update_state(content)` on mutation responses is a no-op since none of the V2GameState fields (`player`, `ship`, `location`, etc.) are present. The client **must** call `get_status` after every mutation to get updated state.

### `travel` response — `poi` is a string, not an object

The `travel` response includes `"poi": "Material Harvesters"` (a string), not a `SystemPOI` object. The `poi_id` field is the actual ID. This differs from `LoginResponse` and `GetSystemResponse` where `poi` is a full object.

### `dock` response — includes `station_condition` not in spec

The `dock` response includes a `station_condition` object with `condition`, `condition_text`, `satisfaction_pct`, `satisfied_count`, `total_service_infra`. This is not documented in the OpenAPI spec and could be useful for UI display.

---

## Social / Chat API

### Chat endpoint uses `content` and `target`, not `text`/`message`/`channel`

The OpenAPI spec defines the request body for `/api/v2/spacemolt_social/chat` with:
- `content` — the message text (NOT `text` or `message`)
- `target` — the channel name: `local`, `system`, `faction` (NOT `channel`)

Same param names apply to `get_chat_history` — use `target` for the channel name.

### Chat send response

```json
{"channel": "local", "message": "Hello!", "sent_at": "2026-03-08T..."}
```

### Chat history response

Returns `messages` array. Each message has `sender`/`username`, `message`/`text`, `channel`, `sent_at`.

---

## Missions API

### `get_missions` returns missions as an Array, not a Dictionary

`StateManager.update_state()` was typed with `var missions: Dictionary` but `get_missions` returns:
```json
{"base_id": "...", "base_name": "...", "missions": [...]}
```

The `missions` field is an **Array** of mission objects. The `get_active_missions` response also has `missions` as an Array.

**Impact**: `StateManager.missions` now handles both Array and Dictionary types.

---

## Catalog API

### Catalog requires `type` parameter

The `/api/v2/spacemolt_catalog` endpoint requires a `type` parameter. Valid types: `ships`, `skills`, `recipes`, `items`. Without it, the server returns an error: `Unknown catalog type "". Must be one of: ships, skills, recipes, items.`

### Catalog response structure

```json
{
  "items": [...],
  "message": "...",
  "page": 1,
  "page_size": 20,
  "total": 712,
  "total_pages": 36,
  "type": "items"
}
```

Catalog items have: `name`, `category`, `description`, `id` (and more depending on type).

---

## Storage API

### Storage view response

```json
{
  "base_id": "...",
  "credits": 0,
  "hint": "...",
  "items": [...],
  "ships": [...]
}
```

Note: includes `ships` array (stored ships at base), `credits` (vault balance), and `hint`.

### Storage deposit response

```json
{
  "action": "deposit",
  "cargo_remaining": 0,
  "cargo_space": 250,
  "item_id": "copper_ore",
  "quantity": 4,
  "storage_total": 4
}
```

### Storage withdraw response

```json
{
  "action": "withdraw",
  "cargo_space": 246,
  "cargo_total": 4,
  "item_id": "copper_ore",
  "quantity": 4,
  "storage_remaining": 0
}
```

---

## Market Order API

### Create buy order response

```json
{
  "action": "create_buy_order",
  "item": "Water Ice",
  "item_id": "water_ice",
  "listing_fee": 0,
  "message": "...",
  "order_id": "...",
  "price_each": 1,
  "quantity": 1,
  "remaining_escrowed": 1,
  "total_escrowed": 1
}
```

Note: includes `listing_fee`, `remaining_escrowed`, `total_escrowed` — useful for UI feedback.

### Cancel order response

```json
{
  "action": "cancel_order",
  "message": "...",
  "order_id": "...",
  "returned_credits": 1
}
```

---

## Galaxy Map API

### `get_map` response has more fields than spec

The spec says `GetMapResponse` only has `systems: [{system_id, name}]` and `total_count`. The real response includes much richer data per system:

```json
{
  "system_id": "dheneb",
  "name": "Dheneb",
  "position": {"x": 639.4, "y": 656.3},
  "connections": ["mira", "barnards_star", "proxima_centauri"],
  "online": 0,
  "poi_count": 6,
  "visited": false,
  "visited_at": ""
}
```

505 systems in total. The `position` and `connections` fields are essential for rendering a galaxy map.

### Jump response

```json
{
  "action": "jump",
  "exploration_xp": 10,
  "from_system": "nexus_prime",
  "navigation_xp": 5,
  "poi": "...",
  "system": "Node Alpha",
  "system_id": "node_alpha"
}
```

Note: `poi` is a string (POI name), not a POI object. Includes XP gains for exploration and navigation.

---

## Summary of Impact

### Fields our client code gets wrong (FIXED)

Our GDScript code uses `hull_max`, `shield_max`, `fuel_max`, `cargo_max` but the API returns `max_hull`, `max_shield`, `max_fuel`, `cargo_capacity`. **This is the biggest bug** — all percentage calculations and HUD bars will break.

| Our code assumes | API actually returns |
|---|---|
| `ship.hull_max` | `ship.max_hull` |
| `ship.shield_max` | `ship.max_shield` |
| `ship.fuel_max` | `ship.max_fuel` |
| `ship.cargo_max` | `ship.cargo_capacity` |

### Redundant API calls

`get_status` now returns `location.nearby_players` and `location.nearby_pirates` inline, meaning the separate `get_nearby` poll call is redundant (though still valid and returns the same data with `primary_color`/`secondary_color` which the inline version also includes).
