shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 color_outer : source_color = vec4(0.7, 0.25, 0.13, 1.0);
uniform vec4 color_mid : source_color = vec4(0.93, 0.52, 0.24, 1.0);
uniform vec4 color_core : source_color = vec4(1.0, 0.87, 0.6, 1.0);
uniform vec2 heat_steps = vec2(0.36, 0.8);
uniform float flame_height = 1.35;
uniform float flame_radius = 0.46;
uniform float flame_base = 0.08;
uniform float rise_speed = 1.4;
uniform float turbulence = 0.83;
uniform int march_steps : hint_range(8, 128) = 56;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
const int FIRE_PARTICLE_COUNT = 40;
uniform vec4 fire_particles[FIRE_PARTICLE_COUNT];
uniform float fire_particle_heat[FIRE_PARTICLE_COUNT];

uniform float fire_time = 0.0;
uniform float flare = 0.5;
uniform float fire_body = 0.55;
uniform float fire_girth = 1.0;
uniform float fire_turbulence = 1.0;
uniform vec2 fire_steps = vec2(0.0);
uniform vec3 fire_alpha = vec3(0.75, 0.87, 0.96);

const int TONGUES = 7;
const vec3 fire_box = vec3(0.61, 1.12, 0.61);
const vec3 fire_box_center = vec3(0.0, 1.12, 0.0);

float fire_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float fire_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(fire_hash(i), fire_hash(i + vec3(1, 0, 0)), f.x), mix(fire_hash(i + vec3(0, 1, 0)), fire_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(fire_hash(i + vec3(0, 0, 1)), fire_hash(i + vec3(1, 0, 1)), f.x), mix(fire_hash(i + vec3(0, 1, 1)), fire_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fire_fbm(vec3 p) {
	return 0.7 * fire_noise(p) + 0.3 * fire_noise(p * 2.03 + 17.1);
}

float fire_box_exit(vec3 ro, vec3 rd) {
	vec3 inv = 1.0 / rd;
	vec3 t1 = (fire_box_center - fire_box - ro) * inv;
	vec3 t2 = (fire_box_center + fire_box - ro) * inv;
	vec3 far = max(t1, t2);
	return max(min(min(far.x, far.y), far.z), 0.0);
}

float fire_tongue(vec3 p, vec2 base, float radius, float height, float phase) {
	float h = (p.y - flame_base) / height;
	if (h <= 0.0 || h >= 1.0) {
		return 0.0;
	}
	vec2 sway = vec2(sin(p.y * 5.0 - fire_time * 7.0 + phase), cos(p.y * 4.0 - fire_time * 5.5 + phase * 1.7)) * 0.06 * h;
	vec2 d = p.xz - base - sway;
	float w = radius * pow(1.0 - h, 0.7) * (0.8 + 1.0 * sqrt(h) * (1.0 - h));
	float f = max(1.0 - dot(d, d) / (w * w), 0.0);
	return f * f;
}

float fire_tongue_hash(float n) {
	return fract(sin(n * 91.3 + 7.1) * 43758.5453);
}

float fire_body_field(vec3 p, float height) {
	float top = height * fire_body;
	if (p.y < flame_base || p.y > flame_base + top) {
		return 0.0;
	}
	float radius = flame_radius * fire_girth;
	float field = fire_tongue(p, vec2(0.0), radius * 1.05, top * 0.7, 0.0) * 1.1;
	for (int i = 0; i < TONGUES; i++) {
		float k = float(i);
		float a = k * 2.39996 + fire_time * (0.25 + 0.3 * fire_tongue_hash(k)) * (fire_tongue_hash(k + 1.0) > 0.5 ? 1.0 : -1.0);
		vec2 base = vec2(cos(a), sin(a)) * radius * (0.2 + 0.4 * fire_tongue_hash(k + 3.0));
		float r = radius * (0.42 + 0.18 * fire_tongue_hash(k + 5.0));
		float beat = fire_noise(vec3(fire_time * 1.1, k * 7.3, 0.5));
		float hk = top * (0.35 + 0.75 * beat * beat);
		field += fire_tongue(p, base, r, hk, k * 2.1);
	}
	return field;
}

float fire_particle_field(vec3 p) {
	float field = 0.0;
	for (int i = 0; i < FIRE_PARTICLE_COUNT; i++) {
		vec4 q = fire_particles[i];
		vec3 d = p - q.xyz;
		d.y *= 0.45;
		float f = max(1.0 - dot(d, d) / (q.w * q.w), 0.0);
		f *= f;
		field += f * f * fire_particle_heat[i];
	}
	return field;
}

float fire_heat(vec3 p, float height) {
	float h = clamp((p.y - flame_base) / height, 0.0, 1.4);
	float body = fire_body_field(p, height);

	float field = body + fire_particle_field(p) * clamp(1.0 - body, 0.2, 1.0);
	if (field <= 0.0) {
		return -1.0;
	}
	vec3 q = vec3(p.x * 2.2, (p.y - fire_time * rise_speed) * 1.8, p.z * 2.2);
	float n = fire_fbm(q);
	return (1.0 - exp(-field)) * (1.0 - 0.3 * min(h, 1.0)) - 0.1 + (n - 0.5) * turbulence * fire_turbulence * (0.2 + 1.1 * h) * min(field * 4.0, 1.0);
}

float fire_march(vec3 ray_origin, vec3 ray_direction, float distance) {
	float height = flame_height * (0.82 + 0.36 * flare);
	float step_length = distance / float(march_steps);
	float hottest = -1.0;
	for (int i = 0; i < march_steps; i++) {
		float distance_along_ray = (float(i) + 0.5) * step_length;
		float heat = fire_heat(ray_origin + ray_direction * distance_along_ray, height);
		hottest = max(hottest, heat);
	}
	return hottest;
}

void fragment() {
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_direction = PROJECTION_MATRIX[3][3] == 1.0
		? -normalize(INV_VIEW_MATRIX[2].xyz)
		: normalize(mat3(INV_VIEW_MATRIX) * VERTEX);
	mat4 inverse_model = inverse(MODEL_MATRIX);
	vec3 ray_origin = (inverse_model * vec4(world_position, 1.0)).xyz + fire_box_center;
	vec3 ray_direction = (inverse_model * vec4(world_direction, 0.0)).xyz;
	float depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 surface = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 surface_world = (INV_VIEW_MATRIX * vec4(surface.xyz / surface.w, 1.0)).xyz;
	float ray_length = min(fire_box_exit(ray_origin, ray_direction), max(dot(surface_world - world_position, world_direction), 0.0));
	float heat = fire_march(ray_origin, ray_direction, ray_length);
	if (heat + 0.04 <= 0.0) {
		discard;
	}
	vec2 steps = heat_steps + fire_steps;
	int band = heat > steps.y ? 2 : heat > steps.x ? 1 : 0;
	ALBEDO = band == 2 ? color_core.rgb : band == 1 ? color_mid.rgb : color_outer.rgb;
	ALPHA = band == 2 ? fire_alpha.z : band == 1 ? fire_alpha.y : fire_alpha.x;
}
