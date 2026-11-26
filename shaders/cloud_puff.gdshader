// A billow of storm cloud rising out of the cloud sea. The sphere is pushed
// in and out by noise so it reads as lumpy vapour rather than a ball, and its
// edges fade out so neighbouring billows blend together.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.36, 0.4, 0.55, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.75, 0.5, 1.0);
uniform float lumpiness = 0.18;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = noise3(wp * 0.35 + vec3(0.0, TIME * 0.05, 0.0)) * 0.7 + noise3(wp * 0.9) * 0.3;
	VERTEX += NORMAL * (n - 0.5) * lumpiness * length(VERTEX) * 2.0;
	world_pos = wp;
}

void fragment() {
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = noise3(world_pos * 1.3);
	ALBEDO = albedo.rgb * (0.85 + 0.3 * n);
	ROUGHNESS = 1.0;
	// Sunset light catching the edges.
	EMISSION = rim_color.rgb * pow(fres, 3.0) * 0.25;
	ALPHA = clamp(1.0 - pow(fres, 2.5) * 0.9, 0.0, 1.0);
}
