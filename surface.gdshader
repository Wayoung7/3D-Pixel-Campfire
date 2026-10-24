shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.5, 0.47, 0.44, 1.0);
uniform float ambient_energy = 0.3;
uniform bool burning = false;
uniform float light_wrap = 0.0;
uniform float light_steepness = 1.0;

uniform vec4 bark_color : source_color = vec4(0.32, 0.2, 0.12, 1.0);
uniform vec4 bark_dark_color : source_color = vec4(0.22, 0.13, 0.08, 1.0);
uniform vec4 char_color : source_color = vec4(0.1, 0.075, 0.065, 1.0);
uniform vec4 ash_color : source_color = vec4(0.42, 0.38, 0.35, 1.0);
uniform vec4 ember_hot : source_color = vec4(0.95, 0.66, 0.36, 1.0);
uniform vec4 ember_warm : source_color = vec4(0.6, 0.25, 0.15, 1.0);

uniform float char_radius = 0.34;
uniform float ember_radius = 0.26;
uniform float ember_scale = 6.0;

uniform bool coal_bed = false;

uniform float flare = 0.5;

varying vec3 local_position;

float wood_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float wood_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(wood_hash(i), wood_hash(i + vec3(1, 0, 0)), f.x), mix(wood_hash(i + vec3(0, 1, 0)), wood_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(wood_hash(i + vec3(0, 0, 1)), wood_hash(i + vec3(1, 0, 1)), f.x), mix(wood_hash(i + vec3(0, 1, 1)), wood_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 base = albedo.rgb;
	vec3 glow = vec3(0.0);
	if (burning) {
		vec3 p = local_position;
		float d = length(p.xz);
		float n = wood_noise(p * 5.0);
		base = n > 0.62 ? bark_dark_color.rgb : bark_color.rgb;
		float burn = d + (n - 0.5) * 0.16;
		float reach = ember_radius;
		if (coal_bed) {
			base = n > 0.58 && d > 0.25 ? ash_color.rgb : char_color.rgb;
			reach = 0.5;
		} else if (burn < char_radius) {
			base = char_color.rgb;
		}

		float crack = wood_noise(p * ember_scale + 7.3);
		float beat = sin(TIME * (0.8 + wood_noise(p * 2.0) * 1.6) + crack * 9.0);
		float heat = (1.0 - burn / reach) * 0.9 + crack * 0.7 - 0.45 + 0.08 * beat + 0.15 * (flare - 0.5);
		glow = heat > 0.5 ? ember_hot.rgb : heat > 0.3 ? ember_warm.rgb : vec3(0.0);
	}
	ALBEDO = base;
	EMISSION = base * ambient_energy + glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float energy = max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), LIGHT_COLOR.b);
	float facing = clamp((dot(NORMAL, LIGHT) + light_wrap) * light_steepness, 0.0, 1.0);
	float intensity = energy / PI * ATTENUATION * facing;
	float band = intensity <= 0.06 ? 0.0 : intensity <= 0.15 ? 0.1 : intensity <= 0.4 ? 0.3 : intensity <= 0.7 ? 0.6 : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR / max(energy, 0.00001) * band;
}
