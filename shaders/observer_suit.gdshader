shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform float presence : hint_range(0.0, 1.0) = 0.0;
uniform float threat : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float weave_a = sin(UV.x * 96.0 + UV.y * 11.0);
	float weave_b = sin(UV.y * 118.0 - UV.x * 17.0);
	float weave = (weave_a + weave_b) * 0.5;
	float edge = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.4);
	vec3 cloth = vec3(0.0065, 0.0080, 0.0090) + vec3(0.0020, 0.0024, 0.0028) * weave;
	cloth += edge * vec3(0.010, 0.013, 0.015) * (0.75 + presence * 0.9);
	ALBEDO = max(cloth, vec3(0.001));
	ROUGHNESS = 0.79 - edge * 0.16;
	METALLIC = 0.06;
	EMISSION = vec3(0.0012, 0.0018, 0.0020) * (0.35 + edge * 1.6 + threat * 0.35);
}
