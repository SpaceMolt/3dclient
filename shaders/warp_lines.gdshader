shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float line_count : hint_range(10.0, 200.0) = 80.0;
uniform float line_speed : hint_range(0.5, 5.0) = 2.0;
uniform vec3 line_color : source_color = vec3(0.8, 0.85, 1.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV - 0.5; // Center at origin
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);

	// Divide the circle into angular slices for line positions
	float slice = angle * line_count / TAU;
	float slice_id = floor(slice);
	float slice_frac = fract(slice);

	// Each slice gets a random offset and speed variation
	float rand_offset = hash(vec2(slice_id, 0.0));
	float rand_speed = 0.7 + hash(vec2(slice_id, 1.0)) * 0.6;
	float rand_width = 0.2 + hash(vec2(slice_id, 2.0)) * 0.6;

	// Line is thin in the angular direction
	float line_mask = smoothstep(0.5, 0.5 - rand_width * 0.3, abs(slice_frac - 0.5));

	// Animate lines streaking inward: radial position scrolls over time
	float scroll = fract(dist * 2.0 - TIME * line_speed * rand_speed + rand_offset);

	// Lines are brighter/longer when closer to edge, fade toward center
	float radial_fade = smoothstep(0.05, 0.4, dist);

	// Streak shape: sharp leading edge, soft trail
	float streak = smoothstep(0.0, 0.15, scroll) * smoothstep(0.7, 0.3, scroll);

	// Combine
	float line_alpha = line_mask * streak * radial_fade;

	// Slight vignette glow at edges
	float edge_glow = smoothstep(0.3, 0.7, dist) * 0.15;

	float final_alpha = (line_alpha + edge_glow) * intensity;
	COLOR = vec4(line_color, final_alpha);
}
