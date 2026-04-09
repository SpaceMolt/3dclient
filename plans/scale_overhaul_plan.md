# Scale Overhaul Plan: Board Game → Cinematic Space

## Goal
Transform the visual feel from "board game with symbolic pieces" to "cinematic space game" (EVE Online-ish). Ships are tiny, stations tower over you, planets fill the sky, stars burn in the distance.

## Architecture: Focus Bubble

The player ship stays at or near world origin (0,0,0). Everything positions relative to the ship.

- **Focused POI**: The POI the player is currently at. Rendered at full cinematic scale near origin.
- **Distant POIs**: All other POIs. Rendered as billboard impostors (glowing dots + labels) at logarithmically compressed distances in the correct direction.
- **During travel**: The focus bubble shifts. Origin POI recedes to impostor, destination grows to full geometry.

This avoids Godot's single-precision float issues (jitter past ~10K units) and keeps everything in one scene.

## Scale Ratios

| Object | Size (Godot units) | Notes |
|--------|-------------------|-------|
| Ship (fighter/personal) | ~1 unit long | Baseline scale 1 |
| Ship (capital class) | ~5 units long | Scale varies by ship class |
| Station | 30-60 across | Hub + ring + arms, towers over ships |
| Asteroid field | 10-40 cluster radius | Individual rocks 0.5-4 units |
| Moon | 80-120 radius | Large backdrop sphere |
| Planet (terrestrial) | 200-400 radius | Fills significant view |
| Planet (gas giant/jovian) | 600-1000 radius | Enormous |
| Star (M dwarf) | ~800 radius | Distant, always visible |
| Star (G class) | ~1500 radius | Distant, always visible |
| Star (O/B giant) | ~3000 radius | Distant, always visible |

## Distance Compression

POI positions from API are in AU (range: ±8 AU from system center).

Distant POIs placed in a "compressed shell" at 2000-5000 Godot units from origin:

```
direction = normalize(poi_au - player_au)
real_dist = length(poi_au - player_au)
compressed = SHELL_MIN + (SHELL_MAX - SHELL_MIN) * (1.0 - exp(-real_dist * COMPRESS_K))
world_pos = direction * compressed
```

Constants: `SHELL_MIN = 2000`, `SHELL_MAX = 5000`, `COMPRESS_K = 0.5`

This puts:
- 0.1 AU away → ~2100 units (nearby, visible dot)
- 1.0 AU away → ~2800 units
- 5.0 AU away → ~4600 units
- 8.0 AU away → ~4950 units (near max shell)

## POI Data (from backend)

- 13 types: planet, moon, sun, asteroid_belt, asteroid, nebula, gas_cloud, ice_field, relic, station, wormhole_entrance, wormhole_exit, wormhole_collapsed
- Positions: float64 AU from system center, range ±8 AU
- Class field varies by type (spectral class for stars, terrain for planets, composition for asteroids, etc.)
- One binary star system exists (Alzirr: black hole + K-class giant)
- All other systems: single star

## Camera Changes

Context-aware zoom ranges:

| Context | Zoom Min | Zoom Max | Default |
|---------|----------|----------|---------|
| Station | 5 | 200 | 30 |
| Planet | 20 | 500 | 100 |
| Star | 50 | 1000 | 200 |
| Asteroid/other | 10 | 300 | 50 |
| Traveling | 20 | 200 | 80 |
| Combat | 8 | 50 | 15 |

## Travel Animation

During travel, the ship stays at origin. POIs move around it:
1. **Departure**: Focused POI scales down and transitions to impostor
2. **Mid-flight**: Ship at center, origin dot behind, destination dot ahead
3. **Arrival**: Destination transitions from impostor to full geometry, scales up
4. Asymptotic progress math unchanged: `progress = min(1 - exp(-0.08 * t), 0.95)`

## Star Rendering

System star rendered as a large emissive sphere at fixed distance (~6000 units) in the correct direction from origin. Size/color from spectral class. For the Alzirr binary, render both.

## Implementation Phases

### Phase 1: Focus Bubble Foundation
- Ship-centric coordinate system in system_renderer.gd
- `_player_au_pos` tracking, `_focused_poi_id` tracking
- `_poi_to_bubble_pos()` function: focused POI near origin, others in compressed shell
- Impostor rendering for distant POIs (billboard + label)
- Tests for all coordinate math

### Phase 2: Cinematic POI Geometry
- Scale up poi_marker.gd meshes for focused POI mode
- Add `set_mode("full" / "impostor")` switching
- Full mode: massive geometry per type/class
- Impostor mode: billboard quad + glow + label

### Phase 3: Camera Overhaul
- Context-aware zoom ranges
- Smooth transitions between contexts
- Chase-cam during travel

### Phase 4: Travel Animation Rework
- POIs move around stationary ship during travel
- Origin→impostor transition, destination→full transition
- Focus bubble continuous update during travel

### Phase 5: Star Rendering
- Distant star sphere in correct direction
- Spectral class drives size/color
- Handle binary star case (Alzirr)

### Phase 6: Polish
- Impostor↔geometry crossfade
- Label scaling by distance
- Ship scale by class
- Engine trail VFX during travel

## Risks
- Click detection needs scale-aware hit radii
- Label readability across huge zoom range
- Travel animation may feel disorienting (POIs moving around ship) — needs playtesting
- Only one POI has full geometry at a time — keeps performance good

## Out of Scope (This Pass)
- 2D system map overlay (separate effort)
- Custom GLB ship models (later phase)
- Realistic astronomical scale
