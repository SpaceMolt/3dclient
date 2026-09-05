shader_type spatial;
// Atmospheric halo for planets. Drawn on a shell slightly larger than the planet with the
// front faces culled: the back faces outside the planet's disc are what remains visible.
// Godot flips NORMAL to face the camera on those faces, so dot(NORMAL, VIEW) runs from 0 at
// the shell's edge to about 0.3 at the planet's limb, and the glow fades outward with no
// extra math. sun_dir keeps the halo on the star-lit side.
render_mode blend_add, cull_front, depth_draw_never, unshaded;

uniform vec3 atmo_color : source_color = vec3(0.35, 0.6, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.5;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);  // world space, pointing at the star

void fragment() {
	float rim = smoothstep(0.0, 0.4, dot(NORMAL, VIEW));
	// NORMAL faces the camera here, so its negation is the shell's true outward normal
	vec3 outward = -normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = clamp(dot(outward, sun_dir) * 1.5 + 0.3, 0.0, 1.0);
	ALBEDO = atmo_color * intensity * rim * lit;
}
