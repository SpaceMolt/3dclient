shader_type sky;

uniform vec3 sky_color : source_color = vec3(0.01, 0.01, 0.04);
uniform vec3 nebula_color_1 : source_color = vec3(0.1, 0.02, 0.15);
uniform vec3 nebula_color_2 : source_color = vec3(0.02, 0.05, 0.15);
uniform float nebula_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_brightness : hint_range(0.5, 5.0) = 2.0;
uniform float twinkle_speed : hint_range(0.0, 2.0) = 0.5;

// 3D hashes — operate directly on direction, no projection = no seams
float hash1d(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

vec3 hash3d(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453123);
}

// 3D value noise — seamless on a sphere
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

// 3-octave fbm — enough for soft nebula, cheap
float fbm3d(vec3 p) {
	float value = 0.0;
	value += 0.5 * noise3d(p);
	value += 0.25 * noise3d(p * 2.0);
	value += 0.125 * noise3d(p * 4.0);
	return value;
}

// Fast stars: single cell lookup per pixel, no neighbor search
vec3 stars(vec3 dir, float scale, float threshold, float brightness) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 local = fract(p);

	// One star candidate per cell
	vec3 star_pos = hash3d(cell);
	float d = length(local - star_pos);

	float h = hash1d(cell);
	if (h < threshold) {
		return vec3(0.0);
	}

	float star_size = 0.1 + h * 0.1;
	float star = smoothstep(star_size, 0.0, d);

	if (star < 0.001) {
		return vec3(0.0);
	}

	// Color variation
	float temp = hash1d(cell + vec3(42.0, 17.0, 91.0));
	vec3 star_col = vec3(1.0);
	if (temp < 0.2) {
		star_col = vec3(0.7, 0.8, 1.0);
	} else if (temp < 0.35) {
		star_col = vec3(1.0, 0.9, 0.7);
	} else if (temp < 0.42) {
		star_col = vec3(1.0, 0.6, 0.4);
	}

	float twinkle = sin(TIME * twinkle_speed * (1.0 + h * 3.0) + h * 100.0) * 0.3 + 0.7;
	return star_col * star * brightness * twinkle;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	vec3 col = sky_color;

	// Nebula — 3D noise, 3 octaves
	float n1 = fbm3d(dir * 2.0 + vec3(3.7, 1.2, 0.5));
	float n2 = fbm3d(dir * 2.5 + vec3(8.3, 5.1, 2.3));
	col += nebula_color_1 * smoothstep(0.4, 0.8, n1) * nebula_intensity;
	col += nebula_color_2 * smoothstep(0.5, 0.9, n2) * nebula_intensity * 0.7;

	// Stars — single cell lookup, two layers
	float star_thresh = 1.0 - star_density * 0.02;
	col += stars(dir, 30.0, star_thresh, star_brightness);
	col += stars(dir, 60.0, 0.97, 0.6);

	COLOR = col;
}
