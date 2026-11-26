// Surface detail for hex deck and walkway tiles, drawn in code so there are no
// texture files to manage. `tint` is the ownership colour from the legend
// (your platforms brass, rivals red, neutral grey...) and stays the main
// colour; `surface` picks the pattern painted over it:
//   0 riveted iron plates (city platforms, headquarters)
//   1 tread plate (turbine islands)
//   2 flagstones (natural rock islands)
//   3 grass over earth (grassy crystal islands)
//   4 cracked slate with glowing crystal veins (overcharged crystal islands)
//   5 iron grating (walkways and bridges)
// The tile mesh is a 6-sided cylinder centred on its node, corners at +-z.
shader_type spatial;
render_mode cull_back;

uniform vec4 tint : source_color = vec4(0.5, 0.52, 0.55, 1.0);
uniform int surface = 0;
// Centre-to-corner radius of the tile mesh.
uniform float radius = 1.0;
uniform vec4 vein_color : source_color = vec4(0.75, 0.45, 1.0, 1.0);

varying vec3 local_pos;
varying vec3 local_normal;
varying float tile_seed;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Distance to the nearest Voronoi cell edge (x) and the cell's random id (y).
vec2 voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash21(n + g), hash21(n + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash21(n + g + 3.1);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d2 - d1, id);
}

// Distance from a point inside the hex to its nearest edge (0 at the edge).
float hex_edge(vec2 p) {
	vec2 q = abs(p);
	float apothem = radius * 0.8660254;
	float d = max(q.x, dot(q, vec2(0.5, 0.8660254)));
	return apothem - d;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	vec3 o = NODE_POSITION_WORLD;
	tile_seed = hash21(floor(o.xz * 0.5 + 0.5));
}

void fragment() {
	vec2 p = local_pos.xz;
	float edge = hex_edge(p);
	bool top = local_normal.y > 0.5;
	vec3 base = tint.rgb;
	float detail = 1.0;
	float metal = 0.0;
	float rough = 0.85;
	vec3 glow = vec3(0.0);
	// Each tile is a touch lighter or darker than its neighbours.
	float tile_var = 0.92 + 0.16 * tile_seed;

	if (top) {
		// Bevelled rim: a darker groove just inside the edge, a lit lip on it.
		float lip = smoothstep(0.02, 0.09, edge);
		float groove = 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.05, edge));
		if (surface == 0) {
			// Four riveted plates meeting at a cross through the centre.
			float seam = min(abs(p.x), abs(p.y));
			float seam_line = smoothstep(0.02, 0.05, seam);
			float n = fbm(p * 6.0 + tile_seed * 9.0);
			detail = (0.82 + 0.3 * n) * mix(0.55, 1.0, seam_line);
			// A ring of rivets just inside the rim.
			float ring = abs(edge - 0.16);
			float along = fract(atan(p.x, p.y) * 24.0 / 6.2831853) - 0.5;
			float rivets = 1.0 - smoothstep(0.03, 0.05, length(vec2(along * 0.26, ring)));
			detail = mix(detail, 1.35, rivets);
			// A dark shadow line on the inner side of the rivet ring.
			detail *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.025, abs(edge - 0.25)));
			metal = 0.55;
			rough = 0.42 + 0.25 * n;
		} else if (surface == 1) {
			// Diamond tread plate.
			vec2 r = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p * 3.6;
			vec2 c = fract(r) - 0.5;
			// Alternate the studs' direction like real tread plate.
			if (mod(floor(r.x) + floor(r.y), 2.0) > 0.5) { c = c.yx; }
			float stud = 1.0 - smoothstep(0.3, 0.36, abs(c.x) * 2.8 + abs(c.y));
			float n = fbm(p * 5.0 + tile_seed * 7.0);
			detail = 0.8 + 0.18 * n + stud * 0.4;
			metal = 0.6;
			rough = 0.38 + 0.2 * n;
		} else if (surface == 2) {
			// Flagstones with dark joints.
			vec2 v = voronoi(p * 1.25 + tile_seed * 13.0);
			float joint = smoothstep(0.02, 0.07, v.x);
			float n = fbm(p * 6.0 + v.y * 10.0);
			detail = mix(0.62, 0.84 + 0.18 * v.y + 0.14 * n, joint);
			rough = 0.95;
		} else if (surface == 3) {
			// Grass with patches of bare earth; the earth shows near edges.
			float n = fbm(p * 3.0 + tile_seed * 5.0);
			float blades = vnoise(p * 40.0);
			float earth = smoothstep(0.55, 0.7, n) + (1.0 - smoothstep(0.0, 0.12, edge)) * 0.6;
			earth = clamp(earth, 0.0, 1.0);
			vec3 grass = base * (0.8 + 0.35 * blades + 0.2 * n);
			grass += vec3(0.08, 0.07, -0.02) * smoothstep(0.4, 0.8, fbm(p * 1.5 + 3.0));
			vec3 dirt = vec3(0.36, 0.26, 0.16) * (0.85 + 0.3 * blades);
			base = mix(grass, dirt, earth * 0.85);
			rough = 0.95;
		} else if (surface == 4) {
			// Dark slate split by glowing crystal veins.
			vec2 v = voronoi(p * 1.7 + tile_seed * 11.0);
			float vein = 1.0 - smoothstep(0.0, 0.06, v.x);
			float n = fbm(p * 6.0 + v.y * 4.0);
			detail = 0.6 + 0.3 * n + 0.15 * v.y;
			float pulse = 0.65 + 0.35 * sin(TIME * 1.7 + tile_seed * 6.28);
			glow = vein_color.rgb * vein * 2.2 * pulse;
			base = mix(base, vein_color.rgb, vein * 0.6);
			metal = 0.1;
			rough = 0.55;
		} else {
			// Iron grating: a lattice of bars over darker gaps.
			vec2 g = abs(fract(p * 4.0) - 0.5);
			float bar = smoothstep(0.3, 0.38, max(g.x, g.y));
			float n = fbm(p * 5.0 + tile_seed * 3.0);
			detail = mix(0.8, 1.25, bar) * (0.9 + 0.2 * n);
			metal = 0.5;
			rough = 0.55;
		}
		detail *= groove;
		detail += (1.0 - lip) * 0.18 * smoothstep(0.0, 0.03, edge);
	} else {
		// The tile's side: darker, with horizontal bands (strata for earth and
		// rock, a riveted band for metal).
		float y = local_pos.y;
		float n = fbm(vec2(atan(p.x, p.y) * 3.0, y * 4.0) + tile_seed * 5.0);
		if (surface == 2 || surface == 3 || surface == 4) {
			float strata = 0.5 + 0.5 * sin(y * 22.0 + n * 4.0);
			detail = 0.45 + 0.2 * strata + 0.15 * n;
			if (surface == 3) {
				base = mix(vec3(0.34, 0.24, 0.15), base, smoothstep(0.36, 0.42, y));
			}
			rough = 0.95;
		} else {
			float band = smoothstep(0.03, 0.0, abs(fract(y * 3.0) - 0.5) - 0.42);
			detail = 0.55 + 0.15 * n + band * 0.15;
			metal = 0.5;
			rough = 0.5;
		}
	}

	ALBEDO = clamp(base * detail * tile_var, 0.0, 1.0);
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = glow;
}
