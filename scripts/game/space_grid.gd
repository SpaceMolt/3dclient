extends MeshInstance3D

## Draws a subtle reference grid on the XZ plane.

const GRID_EXTENT := 100.0  # Half-size in each direction
const GRID_SPACING := 10.0  # Distance between lines
const GRID_COLOR := Color(0.15, 0.2, 0.4, 0.2)


func _ready() -> void:
	var im := ImmediateMesh.new()
	mesh = im

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat

	_build_grid(im)

	# Slight offset to avoid z-fighting
	position.y = -0.05


func _build_grid(im: ImmediateMesh) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(GRID_COLOR)

	var steps := int(GRID_EXTENT / GRID_SPACING)
	for i in range(-steps, steps + 1):
		var offset: float = i * GRID_SPACING

		# Line along Z axis
		im.surface_add_vertex(Vector3(offset, 0.0, -GRID_EXTENT))
		im.surface_add_vertex(Vector3(offset, 0.0, GRID_EXTENT))

		# Line along X axis
		im.surface_add_vertex(Vector3(-GRID_EXTENT, 0.0, offset))
		im.surface_add_vertex(Vector3(GRID_EXTENT, 0.0, offset))

	im.surface_end()
