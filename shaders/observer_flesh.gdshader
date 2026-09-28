shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform float threat : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

varying vec3 local_position;
void vertex() { local_position = VERTEX; }

void fragment() {
	float grain = hash21(floor(FRAGCOORD.xy * 0.5));
	float coverage = smoothstep(0.0, 0.70, presence);
	if (grain > coverage) { discard; }
	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	float grazing = pow(1.0 - facing, 2.2);
	float sinew = sin(local_position.y * 85.0 + sin(local_position.x * 42.0) * 2.4) * 0.5 + 0.5;
	float pores = hash21(floor(local_position.xy * 580.0));
	vec3 skin = vec3(0.014, 0.015, 0.016);
	skin += vec3(0.0015) * sinew + vec3(0.002) * pores;
	skin += vec3(0.012, 0.013, 0.014) * grazing;
	// Dim recessed sockets, never glowing eyes or a painted white mask.
	vec2 face = vec2(abs(local_position.x) - 0.060, local_position.y - 2.429);
	float socket = exp(-dot(face / vec2(0.035, 0.043), face / vec2(0.035, 0.043)));
	float front = 1.0 - smoothstep(-0.075, -0.035, local_position.z);
	skin *= 1.0 - socket * front * 0.92;
	ALBEDO = skin;
	ROUGHNESS = mix(0.70, 0.51, grazing) - threat * 0.035;
	METALLIC = 0.0;
	SPECULAR = 0.36;
}
