shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float vignette_intensity : hint_range(0.0, 2.5) = 1.15;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.22;
uniform float presence : hint_range(0.0, 1.0) = 0.0;
uniform float danger : hint_range(0.0, 1.0) = 0.0;
uniform float exposure : hint_range(0.0, 1.0) = 0.0;
uniform float proximity : hint_range(0.0, 1.0) = 0.0;
uniform float capture : hint_range(0.0, 1.0) = 0.0;
uniform float capture_phase : hint_range(0.0, 1.0) = 0.0;
uniform float silence : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise_line(float line, float frame) {
	return hash(vec2(line * 0.71 + 4.0, frame * 1.37 + 9.0));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;

	// Distant sightings remain completely crisp and clean.
	// Distortion and tearing only emerge under prolonged direct gaze, extreme proximity, or capture.
	float gaze_threat = smoothstep(0.35, 1.0, exposure);
	float close_threat = smoothstep(0.24, 1.0, proximity);
	float active_threat = clamp(gaze_threat * 0.65 + close_threat * 0.75 + capture * 1.4, 0.0, 1.0);

	float frame = floor(TIME * (16.0 + active_threat * 24.0));
	float line = floor(FRAGCOORD.y);
	float line_noise = noise_line(line, frame);

	// Tearing only activates when gaze or close threat threshold is crossed
	float tear_gate = step(0.78 - capture * 0.40, line_noise) * step(0.12, active_threat);
	float tear_band = smoothstep(0.0, 1.0, sin(FRAGCOORD.y * 0.028 + TIME * (2.0 + danger * 4.0)) * 0.5 + 0.5);
	float tear = (line_noise - 0.5) * px.x * (active_threat * 7.5 + capture * 18.0) * tear_gate * tear_band;

	// Subtle horizontal sync drift under gaze
	float sync_drift = sin(FRAGCOORD.y * 0.08 + TIME * 18.0) * px.x * gaze_threat * 0.45;
	// Capture vertical roll / frame drop
	float capture_v_roll = capture * sin(TIME * 32.0 + line * 0.02) * px.y * 2.8;

	vec2 warped_uv = uv + vec2(tear + sync_drift, capture_v_roll);
	float chroma = px.x * (close_threat * 0.85 + capture * 3.5);

	vec3 scene;
	scene.r = textureLod(screen_texture, warped_uv + vec2(chroma, 0.0), 0.0).r;
	scene.g = textureLod(screen_texture, warped_uv, 0.0).g;
	scene.b = textureLod(screen_texture, warped_uv - vec2(chroma * 0.75, 0.0), 0.0).b;

	// Subtle grain and scan instability under active threat
	float grain = hash(FRAGCOORD.xy + vec2(frame * 13.0, frame * 3.0)) - 0.5;
	float static_amount = pow(active_threat, 2.2) * 0.08 + capture * (0.24 + 0.18 * smoothstep(0.15, 0.85, capture_phase));
	float scan = sin(FRAGCOORD.y * 1.45 + TIME * (8.0 + active_threat * 20.0)) * 0.5 + 0.5;
	float scan_amount = (active_threat * 0.022 + capture * 0.038) * scan;

	// Exposure pulse during close pressure and capture
	float exposure_pulse = sin(TIME * (3.5 + danger * 8.0)) * (active_threat * 0.04 + capture * 0.10);

	// Desaturation / contrast drain under threat
	vec3 mono = vec3(dot(scene, vec3(0.27, 0.63, 0.10)));
	vec3 corrupted = mix(scene, mono * vec3(0.84, 0.88, 0.82), active_threat * 0.18 + capture * 0.32);
	corrupted += vec3(grain * static_amount) + vec3(scan_amount * 0.30, scan_amount * 0.42, scan_amount * 0.34);
	corrupted *= 1.0 + exposure_pulse;

	// Vignette (slightly tightens during silence or proximity)
	vec2 centered_uv = UV - vec2(0.5);
	float vig_boost = vignette_opacity + silence * 0.08 + active_threat * 0.12 + capture * 0.22;
	float vignette = smoothstep(0.32, 0.84, length(centered_uv) * vignette_intensity);
	corrupted *= 1.0 - vignette * vig_boost;

	// Capture blackout pulse
	float capture_blackout = pow(max(0.0, sin(TIME * 8.5 + capture_phase * 7.0)), 6.0) * capture * 0.55;
	corrupted = mix(corrupted, vec3(0.012, 0.014, 0.010), capture_blackout);

	float blend_amount = clamp(active_threat * 0.82 + capture * 0.24, 0.0, 0.98);
	COLOR = vec4(mix(scene, corrupted, blend_amount), 1.0);
}
