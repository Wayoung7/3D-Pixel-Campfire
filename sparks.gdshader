shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float spark_time = 0.0;
uniform float spark_amount = 0.5;

uniform float life = 1.6;
uniform float rise = 1.4;
uniform float spread = 0.28;
uniform vec4 color_hot : source_color = vec4(0.97, 0.87, 0.66, 1.0);
uniform vec4 color_warm : source_color = vec4(0.87, 0.53, 0.3, 1.0);
uniform vec4 color_cool : source_color = vec4(0.62, 0.27, 0.17, 1.0);
uniform vec4 color_dying : source_color = vec4(0.45, 0.12, 0.06, 1.0);

uniform float flare = 0.5;

varying flat vec3 spark_color;

float spark_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float period = life * (0.6 + 0.8 * c.g);
	float cycle = spark_time / period + c.r;
	float k = floor(cycle);
	float t = fract(cycle);
	float s = spark_hash(c.b * 91.7 + k * 7.31);
	bool flies = spark_hash(s * 3.1 + 2.0) < spark_amount * (1.0 + 0.6 * (flare - 0.5));
	float a = s * TAU;
	float r = spread * sqrt(spark_hash(s + 1.0));

	vec3 p = vec3(cos(a) * r, 0.95 + 0.35 * spark_hash(s + 2.0), sin(a) * r);

	p.y += rise * (0.5 + spark_hash(s + 3.0)) * (1.0 - (1.0 - t) * (1.0 - t));
	p.xz += vec2(sin(t * 9.0 + s * 20.0), cos(t * 7.0 + s * 13.0)) * 0.08 * t;

	vec3 world_position = (MODEL_MATRIX * vec4(p, 1.0)).xyz;

	bool blink = t > 0.75 && fract(spark_time * 5.0 + s * 5.0) < 0.4;
	float pixels = flies && !blink ? (t < 0.45 && spark_hash(s + 4.0) > 0.45 ? 2.0 : 1.0) : 0.0;
	spark_color = t < 0.25 ? color_hot.rgb : t < 0.55 ? color_warm.rgb : t < 0.85 ? color_cool.rgb : color_dying.rgb;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world_position, 1.0));
	vec2 px = (clip.xy / clip.w * 0.5 + 0.5) * VIEWPORT_SIZE;
	vec2 corner = floor(px - pixels * 0.5 + 0.5) + UV * pixels;
	POSITION = vec4((corner / VIEWPORT_SIZE * 2.0 - 1.0) * clip.w, clip.z, clip.w);
}

void fragment() {
	ALBEDO = spark_color;
}
