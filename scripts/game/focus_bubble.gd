extends RefCounted
## Shared POI sizing helpers.
##
## The main renderer now uses stable world-space positions for every POI.
## This file still owns the visual size buckets and some legacy helper math
## used by tests and tooling.

# --- Distance compression constants ---
const SHELL_MIN := 12000.0   # Closest off-orbit distance (Godot units)
const SHELL_MAX := 40000.0   # Farthest off-orbit distance
const COMPRESS_K := 0.2      # Compression rate (higher = more bunching near min)

# --- Cinematic scale sizes (radius in Godot units) ---
const SCALE_SHIP := 1.0

const SCALE_STATION := 80.0         # hub + ring radius

const SCALE_ASTEROID := 30.0        # cluster radius
const SCALE_ICE_FIELD := 40.0

const SCALE_MOON := 200.0
const SCALE_PLANET_SMALL := 500.0   # terrestrial, arid, tundra, etc.
const SCALE_PLANET_LARGE := 800.0   # super_terran, oceanic
const SCALE_GAS_GIANT := 2800.0     # jovian, hot_jupiter, ice_giant, sub_neptune
const SCALE_STAR_SMALL := 2000.0    # M, L, T, Y, DA, DB
const SCALE_STAR_MEDIUM := 4000.0   # G, K, F, A, C, S, NS
const SCALE_STAR_LARGE := 7000.0    # O, B, WR, LBV
const SCALE_STAR_BH := 1000.0       # Black hole (event horizon visual)

const SCALE_NEBULA := 120.0
const SCALE_GAS_CLOUD := 80.0
const SCALE_RELIC := 40.0
const SCALE_WORMHOLE := 60.0

# Distance from ship to focused POI center (so the ship orbits outside the surface)
const ORBIT_MARGIN := 1.2  # multiplier on the POI radius

# AU range over which a POI transitions from cinematic orbit view to background
const BLEND_AU := 0.3


## Returns the cinematic radius for a POI based on type and class.
static func poi_radius(poi_type: String, poi_class: String) -> float:
	match poi_type:
		"sun", "star":
			return _star_radius(poi_class)
		"planet":
			return _planet_radius(poi_class)
		"moon":
			return SCALE_MOON
		"station":
			return SCALE_STATION
		"asteroid", "asteroid_belt":
			return SCALE_ASTEROID
		"ice_field":
			return SCALE_ICE_FIELD
		"nebula":
			return SCALE_NEBULA
		"gas_cloud":
			return SCALE_GAS_CLOUD
		"relic":
			return SCALE_RELIC
		"wormhole_entrance", "wormhole_exit", "wormhole_collapsed":
			return SCALE_WORMHOLE
		_:
			return SCALE_RELIC  # safe fallback


## Returns the world position for the focused POI center.
## The ship orbits at origin; the POI center is offset so the ship is
## just above the surface.
static func focused_poi_offset(poi_type: String, poi_class: String) -> Vector3:
	var r: float = poi_radius(poi_type, poi_class)
	# Place POI center below and in front of the ship (negative Y).
	# For planets/moons/stars the ship orbits above the surface.
	# For stations/small objects the ship is beside them.
	match poi_type:
		"sun", "star", "planet", "moon":
			# Ship orbits above — POI center is below
			return Vector3(0.0, -r * ORBIT_MARGIN, 0.0)
		_:
			# Ship is beside — POI center offset on Z
			return Vector3(0.0, 0.0, -r * ORBIT_MARGIN)


## Compresses a real AU distance into the impostor shell range.
static func compress_distance(au_distance: float) -> float:
	if au_distance <= 0.0:
		return SHELL_MIN
	return SHELL_MIN + (SHELL_MAX - SHELL_MIN) * (1.0 - exp(-au_distance * COMPRESS_K))


## Returns the world position for a distant (impostor) POI.
## Direction is accurate; distance is compressed.
static func impostor_position(player_au: Vector2, poi_au: Vector2) -> Vector3:
	var delta: Vector2 = poi_au - player_au
	var au_dist: float = delta.length()
	if au_dist < 0.001:
		return Vector3.ZERO  # same position as player, shouldn't be an impostor
	var dir_2d: Vector2 = delta / au_dist
	var compressed: float = compress_distance(au_dist)
	# Map 2D AU direction to 3D XZ plane
	return Vector3(dir_2d.x * compressed, 0.0, dir_2d.y * compressed)


## Returns the continuous world position for any POI based on AU distance from player.
## At au_dist = 0: returns focused_poi_offset (cinematic orbit).
## At au_dist >= BLEND_AU: returns impostor_position on XZ plane.
## Smoothly blends between the two so travel is geometrically continuous.
static func continuous_poi_position(player_au: Vector2, poi_au: Vector2, poi_type: String, poi_class: String) -> Vector3:
	var delta: Vector2 = poi_au - player_au
	var au_dist: float = delta.length()
	if au_dist < 0.001:
		return focused_poi_offset(poi_type, poi_class)
	var dir_2d: Vector2 = delta / au_dist
	var t: float = clampf(au_dist / BLEND_AU, 0.0, 1.0)
	var focused: Vector3 = focused_poi_offset(poi_type, poi_class)
	var background: Vector3 = Vector3(dir_2d.x * compress_distance(au_dist), 0.0, dir_2d.y * compress_distance(au_dist))
	return focused.lerp(background, t)


## Returns the AU position of a POI from its data dictionary.
static func poi_au_pos(poi_data: Dictionary) -> Vector2:
	var pos: Dictionary = poi_data.get("position", {})
	return Vector2(pos.get("x", 0.0), pos.get("y", 0.0))


## Returns the renderer scale for a POI.
## We keep geometry scale stable and let the camera's real perspective do the work.
static func perspective_scale(au_distance: float) -> float:
	return 1.0


## Returns the hit radius for click detection, accounting for perspective scale.
static func hit_radius(poi_type: String, poi_class: String, current_scale: float = 1.0) -> float:
	var r: float = poi_radius(poi_type, poi_class)
	var scaled := r * current_scale * 1.1
	return clampf(scaled, 20.0, 500.0)


# --- Private helpers ---

static func _star_radius(star_class: String) -> float:
	match star_class:
		"O", "B", "WR", "LBV":
			return SCALE_STAR_LARGE
		"G", "K", "F", "A", "C", "S", "NS":
			return SCALE_STAR_MEDIUM
		"M", "L", "T", "Y", "DA", "DB":
			return SCALE_STAR_SMALL
		"BH":
			return SCALE_STAR_BH
		_:
			return SCALE_STAR_MEDIUM


static func _planet_radius(planet_class: String) -> float:
	match planet_class:
		"hot_jupiter", "jovian", "sub_neptune", "ice_giant":
			return SCALE_GAS_GIANT
		"super_terran", "oceanic":
			return SCALE_PLANET_LARGE
		_:
			return SCALE_PLANET_SMALL
