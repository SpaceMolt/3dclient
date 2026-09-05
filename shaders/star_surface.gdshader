shader_type spatial;
// Star photosphere: slowly boiling granulation from 3D noise on the world-space normal, with
// limb darkening so the disc reads as a sphere. Unshaded, so ALBEDO is the final HDR colour
// and anything over 1.0 feeds the glow pass.
render_mode unshaded, cull_back;

uniform vec3 star_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float energy : hint_range(0.0, 12.0) = 1.3;

float hash1d(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1d(i);
	float b = hash1d(i + vec3(1, 0, 0));
	float c = hash1d(i + vec3(0, 1, 0));
	float d = hash1d(i + vec3(1, 1, 0));
	float e = hash1d(i + vec3(0, 0, 1));
	float g = hash1d(i + vec3(1, 0, 1));
	float h = hash1d(i + vec3(0, 1, 1));
	float k = hash1d(i + vec3(1, 1, 1));
	return mix(
		mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
		mix(mix(e, g, f.x), mix(h, k, f.x), f.y),
		f.z
	);
}

float fbm3d(vec3 p) {
	return 0.5 * noise3d(p) + 0.25 * noise3d(p * 2.0) + 0.125 * noise3d(p * 4.0) + 0.0625 * noise3d(p * 8.0);
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float granules = fbm3d(n * 7.0 + vec3(TIME * 0.03, 0.0, TIME * 0.02));
	float limb = mix(0.4, 1.0, pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 0.6));
	ALBEDO = star_color * (0.5 + 1.0 * granules) * limb * energy;
}
