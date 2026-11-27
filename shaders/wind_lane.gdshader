// A rival's wind lane: a faint band of sky with thin streaks of wind
// drifting along it toward the target. UV.x is distance along the lane in
// world units, UV.y runs 0..1 across it, COLOR.a fades the two ends.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.4, 0.3, 1.0);
// Wash over the whole band, and the strength of the streaks.
uniform float fill = 0.1;
uniform float streaks = 0.55;
// World units a second the streaks drift.
uniform float speed = 3.0;
uniform float rows = 7.0;

float hash(float n) {
	return fract(sin(n * 127.1 + 11.7) * 43758.5453);
}

void fragment() {
	float across = UV.y;
	float edge = smoothstep(0.0, 0.22, across) * (1.0 - smoothstep(0.78, 1.0, across));
	float row = floor(across * rows);
	float in_row = fract(across * rows);
	float thin = smoothstep(0.25, 0.5, in_row) * (1.0 - smoothstep(0.5, 0.75, in_row));
	float h = hash(row + 1.0);
	float period = 6.0 + 5.0 * h;
	float x = (UV.x - TIME * speed * (0.7 + 0.6 * h)) / period + h * 9.0;
	float f = fract(x);
	float dash = smoothstep(0.0, 0.12, f) * (1.0 - smoothstep(0.3, 0.6, f));
	dash *= step(0.25, hash(row * 3.1 + floor(x)));
	ALBEDO = tint.rgb;
	ALPHA = clamp((fill + streaks * dash * thin) * edge * COLOR.a, 0.0, 1.0);
}
