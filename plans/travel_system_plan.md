# In-System Travel System Plan

## API Behavior (Verified via Testing)

- `POST /api/v2/spacemolt/travel` with `{"id": poi_id}` **blocks for the full travel duration**
- Adjacent POIs: ~10 seconds (one tick)
- Medium distance: **38 seconds** (multiple ticks)
- Longer trips could take 60+ seconds
- Response only arrives when travel is complete, with `TravelResponse` containing `poi` and `poi_id`
- During the blocking wait, `get_status` still shows the **origin POI** — no `in_transit` fields populated
- The OpenAPI spec defines `in_transit`, `transit_arrival_tick`, `transit_dest_poi_id` etc. on V2GameState.location but the **live server doesn't populate them**
- Fuel consumed per trip (2 fuel observed for a medium trip)
- Travel duration depends on distance between POIs
- We do NOT know duration in advance

## Current Bugs

1. Ships teleport on arrival — `_on_location_changed` destroys and recreates the player ship
2. POI click-to-select blocked by child meshes (fix in place but untested — `_add_visual_child` sets `input_ray_pickable = false`)
3. Long trips may cause session timeout → dump to login screen
4. Poll timer could fire during travel (mitigated: `is_request_pending` stays true)
5. `_update_player_ship()` fires on every `state_updated` and fights with travel animation

## Design Overview

### Principle
**StateManager owns travel state data; SystemRenderer owns travel animation.** UI layers (HUD, action_bar, galaxy_map) only call `begin_travel()` and handle the completion callback.

### New State on StateManager

```gdscript
var travel_dest_poi_id: String = ""
var travel_dest_poi_name: String = ""
var travel_origin_poi_id: String = ""

signal travel_started(dest_poi_id: String, dest_poi_name: String)
signal travel_aborted(origin_poi_id: String)

func begin_travel(dest_poi_id: String, dest_poi_name: String) -> void:
    travel_origin_poi_id = location.get("poi_id", "")
    travel_dest_poi_id = dest_poi_id
    travel_dest_poi_name = dest_poi_name
    is_traveling = true  # emits travel_started

func end_travel() -> void:
    travel_dest_poi_id = ""
    travel_dest_poi_name = ""
    travel_origin_poi_id = ""
    is_traveling = false  # emits travel_ended

func abort_travel() -> void:
    var origin := travel_origin_poi_id
    travel_dest_poi_id = ""
    travel_dest_poi_name = ""
    travel_origin_poi_id = ""
    is_traveling = false  # emits travel_ended
    travel_aborted.emit(origin)
```

Reset new fields in `reset()`.

## Exact Sequence of Events

### Travel Start
```
User clicks "Go" / selects from Travel dropdown
  -> StateManager.begin_travel(dest_id, dest_name)
    -> sets travel_origin_poi_id, travel_dest_poi_id, travel_dest_poi_name
    -> sets is_traveling = true
      -> travel_started.emit(dest_id, dest_name)
        -> system_renderer: start animation, create path line, highlight dest POI
        -> travel_effect: fade in warp lines
  -> NetworkManager.send_command("travel", ...)
    -> request_started.emit() -> action_bar: disable all buttons
    -> HTTP request blocks for 10-60+s
    -> _poll_state returns early (is_request_pending = true)
```

### During the Wait (10-60+ seconds)
- HTTP holds `is_request_pending = true`, suppressing polls
- `system_renderer._process()` drives asymptotic animation
- Ship starts fast, decelerates, never visually arrives
- Path line shrinks as ship moves
- `_update_player_ship()` is guarded — returns early when `_is_animating_travel`

### Travel Complete (Success)
```
HTTP response arrives
  -> send_command callback
    -> _refresh_state_then(get_status)
      -> StateManager.update_state(new_location)
        -> location_changed.emit(old_poi, new_poi)
          -> system_renderer: guarded by _is_animating_travel, only clears other ships
        -> state_updated.emit()
          -> system_renderer._update_player_ship: guarded, returns early
      -> on_complete callback fires
        -> StateManager.end_travel()
          -> travel_ended.emit()
            -> system_renderer: snap ship to dest, remove path line, clear animation
            -> travel_effect: fade out warp lines
```

### Travel Complete (Error)
```
HTTP response is error
  -> _handle_error shows UI message
  -> _on_error callback
    -> _refresh_state_then(get_status) -- location unchanged
    -> on_complete({}) fires
      -> Location hasn't changed, detect this:
        -> StateManager.abort_travel()
          -> travel_aborted.emit(origin_poi_id)
            -> system_renderer: snap ship back to origin, remove path line
            -> travel_effect: fade out (via travel_ended from is_traveling=false)
```

## Asymptotic Animation Algorithm

The ship must fly toward the destination without arriving, regardless of how long the API takes.

```gdscript
const TRAVEL_SPEED_FACTOR := 0.08

# In system_renderer._process():
_travel_elapsed += delta
var progress: float = 1.0 - exp(-TRAVEL_SPEED_FACTOR * _travel_elapsed)
progress = minf(progress, 0.95)
ship.global_position = _travel_origin_pos.lerp(_travel_dest_pos, progress)
```

Behavior at different durations:
- 10s elapsed: ~55% of the way (fast start)
- 30s elapsed: ~91% (slowing down)
- 60s elapsed: ~99% (capped at 95%)

Drive position directly from `system_renderer._process()`, bypassing ShipController's interpolation. Set `ship._tick_t = 1.0` to prevent ShipController from fighting.

## SystemRenderer Travel State

```gdscript
var _is_animating_travel: bool = false
var _travel_origin_pos: Vector3 = Vector3.ZERO
var _travel_dest_pos: Vector3 = Vector3.ZERO
var _travel_elapsed: float = 0.0
var _travel_path_line: MeshInstance3D = null
```

### `_process()` (new)
```gdscript
func _process(delta: float) -> void:
    if not _is_animating_travel:
        return
    _travel_elapsed += delta
    var progress := minf(1.0 - exp(-TRAVEL_SPEED_FACTOR * _travel_elapsed), 0.95)
    var own_id: String = StateManager.player.get("id", "")
    if _ships.has(own_id):
        var ship := _ships[own_id]
        var new_pos := _travel_origin_pos.lerp(_travel_dest_pos, progress)
        ship.global_position = new_pos
        ship._tick_t = 1.0
        ship._prev_pos = new_pos
        ship._next_pos = new_pos
        ship.engine_glow.light_energy = lerpf(3.0, 1.5, progress)
    if _travel_path_line:
        _update_travel_path(
            _ships[own_id].global_position if _ships.has(own_id) else _travel_origin_pos,
            _travel_dest_pos
        )
```

### Guards
```gdscript
func _update_player_ship() -> void:
    if _is_animating_travel:
        return  # Don't reposition during travel animation
    # ... existing code

func _on_location_changed(_old_poi, _new_poi) -> void:
    # Clear OTHER ships only
    var own_id := StateManager.player.get("id", "")
    for pid in _ships.keys():
        if pid != own_id:
            _ships[pid].queue_free()
            _ships.erase(pid)
    # Don't reposition player ship if travel animation is active
    if not _is_animating_travel and _ships.has(own_id):
        var new_pos := _get_player_world_pos()
        _ships[own_id].travel_to(new_pos)
    # Fetch fresh data
    NetworkManager.send_command("get_nearby", {}, ...)
    NetworkManager.send_command("get_system", {}, ...)
```

## Path Line Visualization

Use `ImmediateMesh` inside a `MeshInstance3D` for a dashed line from ship to destination.

```gdscript
func _create_travel_path() -> void:
    var mesh_instance := MeshInstance3D.new()
    var mesh := ImmediateMesh.new()
    mesh_instance.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(0.3, 0.8, 1.0, 0.6)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mesh_instance.material_override = mat
    add_child(mesh_instance)
    _travel_path_line = mesh_instance

func _update_travel_path(ship_pos: Vector3, dest_pos: Vector3) -> void:
    var mesh := _travel_path_line.mesh as ImmediateMesh
    mesh.clear_surfaces()
    mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    var direction := dest_pos - ship_pos
    var total_dist := direction.length()
    var dash_len := 1.0
    var gap_len := 0.5
    var segment_len := dash_len + gap_len
    var num_segments := int(total_dist / segment_len)
    var dir_norm := direction.normalized()
    for i in range(num_segments):
        var start := ship_pos + dir_norm * (i * segment_len)
        var end_pt := ship_pos + dir_norm * (i * segment_len + dash_len)
        mesh.surface_set_color(Color(0.3, 0.8, 1.0, 0.6))
        mesh.surface_add_vertex(start + Vector3(0, 0.1, 0))
        mesh.surface_add_vertex(end_pt + Vector3(0, 0.1, 0))
    mesh.surface_end()

func _remove_travel_path() -> void:
    if _travel_path_line:
        _travel_path_line.queue_free()
        _travel_path_line = null
```

## Destination Marker

Highlight the destination POI marker during travel:
```gdscript
# On travel start:
if _poi_markers.has(dest_poi_id):
    _poi_markers[dest_poi_id].set_selected(true)
# On travel end/abort:
# Deselect handled by cleanup
```

## UI Entry Point Refactoring

All three travel entry points converge on `begin_travel()`:

### HUD (`_on_target_travel`)
```gdscript
var origin_id := StateManager.location.get("poi_id", "")
StateManager.begin_travel(_selected_poi_id, _selected_poi_name)
NetworkManager.send_command("travel", {"id": _selected_poi_id}, func(_c):
    if StateManager.location.get("poi_id", "") == origin_id:
        StateManager.abort_travel()
    else:
        StateManager.end_travel()
)
```

### Action Bar (travel menu handler)
```gdscript
var origin_id := StateManager.location.get("poi_id", "")
StateManager.begin_travel(meta["id"], target_name)
NetworkManager.send_command("travel", {"id": meta["id"]}, func(content):
    if StateManager.location.get("poi_id", "") == origin_id:
        StateManager.abort_travel()
    else:
        StateManager.end_travel()
    _set_status("Arrived at %s." % target_name)
)
```

### Galaxy Map (jump — different flow)
Jumps use `is_jumping` and `jump_started`/`jump_ended` signals. The ship disappears, system re-renders. Keep existing jump flow but make it consistent with `begin_travel` pattern if desired.

## Inter-System Jump Handling

```gdscript
# system_renderer:
func _on_jump_started() -> void:
    for marker in _poi_markers.values():
        marker.visible = false
    for ship in _ships.values():
        ship.visible = false
```

On `jump_ended` + `location_changed`, everything clears and rebuilds naturally.

## NetworkManager Changes

Add public poll control (minor):
```gdscript
func pause_poll() -> void:
    _stop_poll()

func resume_poll() -> void:
    _reset_poll()
```

Called from StateManager's `is_traveling` setter or from system_renderer on travel signals.

## Edge Cases

1. **Double travel click**: Prevented — buttons disabled by `request_started`
2. **Session timeout during long travel**: `_handle_error` fires `session_expired` -> logout -> `reset()` clears travel state
3. **Travel to current POI**: Guard — don't initiate if dest == current poi_id
4. **Zero-distance path line**: Skip path creation if distance < 1.0
5. **State update during animation**: `_update_player_ship()` guarded
6. **Combat during travel**: Server prevents; if it happens, abort travel
7. **Logout during travel**: `reset()` clears everything

## Files to Change

| File | Changes |
|------|---------|
| `state_manager.gd` | Add travel dest fields, `begin_travel()`, `end_travel()`, `abort_travel()`, `travel_aborted` signal, modify `travel_started` signal signature, update `reset()` |
| `system_renderer.gd` | Add `_process()` with asymptotic animation, path line, guards on `_update_player_ship` and `_on_location_changed`, handle `travel_started`/`ended`/`aborted`, handle `jump_started`/`ended` |
| `ship_controller.gd` | Remove the `travel_to()` method added earlier (animation driven by system_renderer now). Keep `_travel_duration` removal clean. |
| `hud.gd` | Refactor `_on_target_travel()` to use `begin_travel()`/`end_travel()`/`abort_travel()` |
| `action_bar.gd` | Refactor travel menu to use `begin_travel()`/`end_travel()`/`abort_travel()` |
| `network_manager.gd` | Add `pause_poll()`/`resume_poll()` public methods |
| `galaxy_map.gd` | Minor — consistent jump state management |

## Test Plan

### Unit Tests (extend `test/unit/test_state_manager.gd`)
- `test_begin_travel_sets_state`: Verify fields set
- `test_begin_travel_emits_travel_started_with_dest`: Signal carries dest info
- `test_end_travel_clears_state`: Fields cleared, `travel_ended` emitted
- `test_abort_travel_emits_travel_aborted`: Signal with origin poi
- `test_abort_travel_clears_state`: State reset
- `test_reset_clears_travel_fields`: New fields cleared by `reset()`

### Unit Tests (new `test/unit/test_travel_animation.gd`)
- `test_asymptotic_progress_at_10s`: ~55%
- `test_asymptotic_progress_at_30s`: ~91%
- `test_asymptotic_progress_capped_at_95pct`: Never exceeds 0.95
- `test_travel_origin_and_dest_positions`: Verify lerp math

### Integration Tests
- `test_ship_not_repositioned_during_travel`: Guard behavior
- `test_travel_error_returns_ship_to_origin`: Abort flow
- `test_path_line_created_and_removed`: Lifecycle

## Implementation Order

1. **Tests first** — state manager tests for new methods
2. **State layer** — StateManager + NetworkManager changes
3. **Animation layer** — SystemRenderer `_process`, path line, guards
4. **UI integration** — HUD, action_bar, galaxy_map refactoring
5. **Polish** — destination marker pulsing, camera zoom during travel
6. **Build and test** — Windows export, manual verification
