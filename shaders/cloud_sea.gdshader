// A layer of drifting storm cloud for the sea of cloud below the platforms.
// Two scrolling samples of one seamless noise texture make the shapes; the
// backdrop script drives `flash` and `flash_pos` for lightning.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 dark_color : source_color = vec4(0.16, 0.17, 0.24, 1.0);
uniform vec4 light_color : source_color = vec4(0.55, 0.57, 0.66, 1.0);
uniform vec2 scroll = vec2(0.006, 0.0025);
uniform float scale = 0.012;
// 0..1: how much of the layer is cloud rather than gap.
uniform float density = 0.6;
uniform float opacity = 1.0;
uniform float flash = 0.0;
uniform vec3 flash_pos = vec3(0.0);
uniform float flash_radius = 40.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * scale;
	float n1 = texture(noise_tex, uv + TIME * scroll).r;
	float n2 = texture(noise_tex, uv * 2.3 - TIME * scroll * 1.7 + vec2(0.37, 0.71)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float edge = 1.0 - density;
	float a = smoothstep(edge, edge + 0.3, n);
	vec3 col = mix(dark_color.rgb, light_color.rgb, smoothstep(0.3, 0.9, n));
	float d = distance(world_pos.xz, flash_pos.xz) / flash_radius;
	col += vec3(0.75, 0.82, 1.0) * flash * exp(-d * d * 2.0) * (0.4 + n);
	ALBEDO = col;
	ALPHA = a * opacity;
}
