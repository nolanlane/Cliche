extends Node3D
## Level 0: The Yellow Halls
## An authentic, atmospheric Backrooms recreation built with Godot 4.7.
## Scene-authored architecture with decoupled runtime systems.

const CEILING_H := 2.80
const WALL_THICKNESS := 0.30

enum FixtureType { NORMAL, STUTTER, DYING, DEAD, SLOW_PULSE, FAINT_EMERGENCY }

class FixtureData:
	var type: FixtureType
	var spot_light: SpotLight3D
	var fill_light: OmniLight3D
	var filament_light: OmniLight3D
	var panel: MeshInstance3D
	var base_spot_energy: float
	var base_fill_energy: float
	var base_filament_energy: float = 0.0
	var base_emission: float
	var seed_offset: float
	var stutter_timer: float = 0.0
	var stutter_state: int = 0

var wallpaper_material: StandardMaterial3D
var floor_material: StandardMaterial3D
var ceiling_material: StandardMaterial3D
var trim_material: StandardMaterial3D
var cap_material: StandardMaterial3D
var soffit_material: StandardMaterial3D
var vent_material: StandardMaterial3D
var pipe_material: StandardMaterial3D
var troffer_panel_material: StandardMaterial3D
var troffer_panel_dying_material: StandardMaterial3D
var troffer_panel_faint_material: StandardMaterial3D
var troffer_panel_dead_material: StandardMaterial3D
var troffer_frame_material: StandardMaterial3D
var filament_glow_material: StandardMaterial3D
var outlet_material: StandardMaterial3D
var damp_material: StandardMaterial3D
var wet_floor_material: StandardMaterial3D
var void_material: StandardMaterial3D
var cable_material: StandardMaterial3D
var tile_face_material: StandardMaterial3D
var tile_core_material: StandardMaterial3D
var observer_material: ShaderMaterial
var observer_head_material: StandardMaterial3D
var observer_hand_material: StandardMaterial3D
var observer_detail_material: StandardMaterial3D
var door_material: StandardMaterial3D
var door_recess_material: StandardMaterial3D
var architectural_metal_material: StandardMaterial3D
var threshold_material: StandardMaterial3D

var fixtures: Array[FixtureData] = []
var elapsed := 0.0

# The Observer begins as a doubtful background presence, then remembers how the
# player reacts and selectively escalates. State changes remain director-owned so
# appearance, pressure, pursuit, and recovery cannot overlap or spam the player.
enum ObserverState { DORMANT, OBSERVING, MANIFESTED, PRESSURE, PURSUIT, CAPTURE, DISENGAGING, RECOVERY }

var observer: Node3D
var observer_markers: Array[Vector3] = []
var observer_marker_roles: Array[StringName] = []
var observer_recent_markers: Array[int] = []
var observer_marker_index := 0
var observer_seen_time := 0.0
var observer_centered_time := 0.0
var observer_exposure_time := 0.0
var observer_hide_timer := 0.0
var observer_relocation_timer := 0.0
var observer_presence := 0.0
var observer_sway_phase := 0.0
var observer_state: ObserverState = ObserverState.DORMANT
var observer_state_timer := 0.0
var observer_escalation := 0.06
var observer_dread := 0.0
var observer_composure := 1.0
var observer_encounters := 0
var observer_attack_charge := 0.0
var observer_attack_cooldown := 0.0
var observer_blocked_time := 0.0
var observer_escape_time := 0.0
var observer_unseen_time := 0.0
var observer_manifest_steps := 0
var observer_feedback := 0.0
var observer_variant: StringName = &"sentinel"
var observer_last_player_position := Vector3.ZERO
var observer_distance_travelled := 0.0
var observer_safe_position := Vector3(1.2, 0.05, 3.2)
var observer_safe_timer := 0.0
var observer_learned_gaze := 0.0
var observer_learned_approach := 0.0
var observer_learned_flight := 0.0
var observer_audio_phase := 0.0
var observer_visited_sectors: Dictionary = {}
var observer_debug_forced := false
var observer_last_distance := 64.0
var observer_last_view_dot := -1.0
var observer_has_sight := false
var observer_exposure_signal := 0.0
var observer_proximity_signal := 0.0
var observer_screen_threat := 0.0
var observer_capture_timer := 0.0
var observer_capture_phase := 0.0
var observer_capture_pending_reset := false
var hud_atmosphere_material: ShaderMaterial

# --- Environmental Tension & Threat Director System ---
var env_tension := 0.0 # 0.0 to 1.0 smoothed organic building instability
var env_director_timer := 0.0
var env_false_positive_timer := 28.0
var env_electrical_wave_active := false
var env_electrical_wave_progress := 0.0
var env_electrical_wave_origin := Vector2.ZERO
var env_electrical_wave_speed := 22.0
var distant_thump_intensity := 0.0

# Silence mechanic (deliberate vacuum of room tone)
var silence_intensity := 0.0 # 0.0 (normal) to 1.0 (dead acoustic vacuum)
var silence_target := 0.0
var silence_timer := 0.0
var silence_cooldown := 38.0

# Acoustic sector identity tracking
var current_player_sector: StringName = &"reception"

# Observer Stance / Pose Variations
# Presets: sentinel, slump, peek_left, peek_right, narrow_vigil
var observer_pose_variant: StringName = &"sentinel"
var observer_unseen_advance_timer := 0.0

# Procedural fluorescent audio
var audio_playback: AudioStreamGeneratorPlayback
var audio_phase := 0.0
var ballast_spark_intensity := 0.0
var spatial_ambience_sources: Array[Dictionary] = []

var player: CharacterBody3D
var hud_status_label: Label
var hud_fuel_fill: ColorRect
var hud_fuel_label: Label
var hud_toast_container: Control
var hud_toast_label: Label
var toast_tween: Tween

func _ready() -> void:
	randomize()
	RenderingServer.set_default_clear_color(Color("#080805"))
	_bind_scene_nodes()
	if player != null:
		observer_last_player_position = player.global_position

func _bind_scene_nodes() -> void:
	# 1. Player binding
	player = get_node_or_null("Gameplay/Player") as CharacterBody3D
	if player == null:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			player = players[0] as CharacterBody3D

	# 2. Observer binding
	observer = get_node_or_null("Gameplay/Observer") as Node3D
	if observer != null:
		var coat := observer.get_node_or_null("Stance/Coat") as MeshInstance3D
		if coat != null:
			observer_material = coat.get_active_material(0) as ShaderMaterial
			if observer_material == null and coat.mesh != null and coat.mesh.get_surface_count() > 0:
				observer_material = coat.mesh.surface_get_material(0) as ShaderMaterial
		var head := observer.get_node_or_null("Stance/Head") as MeshInstance3D
		if head != null:
			observer_head_material = head.material_override as StandardMaterial3D
			if observer_head_material == null:
				observer_head_material = head.get_active_material(0) as StandardMaterial3D
				if observer_head_material == null and head.mesh != null and head.mesh.get_surface_count() > 0:
					observer_head_material = head.mesh.surface_get_material(0) as StandardMaterial3D

	# 3. HUD binding
	var hud_layer := get_node_or_null("HUD") as CanvasLayer
	if hud_layer != null:
		var vig := hud_layer.get_node_or_null("Vignette") as ColorRect
		if vig != null:
			hud_atmosphere_material = vig.material as ShaderMaterial
		var card := hud_layer.get_node_or_null("StatusCard")
		if card != null:
			hud_status_label = card.get_node_or_null("FuelStatus") as Label
			hud_fuel_fill = card.get_node_or_null("GaugeFill") as ColorRect
			hud_fuel_label = card.get_node_or_null("FuelPercent") as Label
			hud_toast_container = card.get_node_or_null("ToastContainer") as Control
			if hud_toast_container != null:
				hud_toast_label = hud_toast_container.get_node_or_null("ToastLabel") as Label

	# 4. Ambient Hum Audio
	var hum_node := get_node_or_null("Atmosphere/AmbientHumPlayer") as AudioStreamPlayer
	if hum_node != null:
		if not hum_node.playing:
			hum_node.play()
		audio_playback = hum_node.get_stream_playback() as AudioStreamGeneratorPlayback

	# 5. Spatial Ambience Emitters (queried from group "spatial_ambience" or Level)
	spatial_ambience_sources.clear()
	var ambience_nodes := get_tree().get_nodes_in_group("spatial_ambience")
	if ambience_nodes.is_empty():
		var level_node := get_node_or_null("Level")
		if level_node != null:
			ambience_nodes = level_node.find_children("*", "AudioStreamPlayer3D")
	for asp in ambience_nodes:
		var p3d := asp as AudioStreamPlayer3D
		if p3d != null:
			if not p3d.is_in_group("spatial_ambience"):
				p3d.add_to_group("spatial_ambience")
			if not p3d.playing:
				p3d.play()
			var kind: StringName = p3d.get_meta("ambience_kind", &"draft")
			spatial_ambience_sources.append({
				"kind": kind,
				"playback": p3d.get_stream_playback() as AudioStreamGeneratorPlayback,
				"phase": randf(),
				"smooth_noise": 0.0
			})

	# 6. Troffer Fixtures (queried from authored nodes in group "troffer_fixture")
	fixtures.clear()
	var fixture_nodes := get_tree().get_nodes_in_group("troffer_fixture")
	for node in fixture_nodes:
		var data := FixtureData.new()
		var t_val = node.get("type")
		data.type = (t_val if t_val != null else 0) as FixtureType
		data.spot_light = node.get_node_or_null("SpotLight") as SpotLight3D
		data.fill_light = node.get_node_or_null("FillLight") as OmniLight3D
		data.panel = node.get_node_or_null("Panel") as MeshInstance3D
		var b_spot = node.get("base_spot_energy")
		data.base_spot_energy = b_spot if b_spot != null else 1.42
		var b_fill = node.get("base_fill_energy")
		data.base_fill_energy = b_fill if b_fill != null else 0.68
		var b_em = node.get("base_emission")
		data.base_emission = b_em if b_em != null else 1.45
		var s_off = node.get("seed_offset")
		data.seed_offset = s_off if s_off != null else 0.0
		fixtures.append(data)

	# 7. Observer Anchors (queried from authored nodes in group "observer_anchor")
	observer_markers.clear()
	observer_marker_roles.clear()
	var anchor_nodes := get_tree().get_nodes_in_group("observer_anchor")
	for node in anchor_nodes:
		var m3d := node as Marker3D
		if m3d != null:
			observer_markers.append(m3d.global_position)
			var r = node.get("role")
			observer_marker_roles.append(r if r != null else &"doorway")

	# 8. Observer Setup
	if observer != null:
		if not observer_markers.is_empty():
			observer.position = observer_markers[0]
		observer.visible = false
		observer_hide_timer = randf_range(24.0, 38.0)
		observer_state_timer = observer_hide_timer
		observer_relocation_timer = 0.0
		observer_sway_phase = randf_range(0.0, TAU)
		_set_observer_state(ObserverState.DORMANT, observer_hide_timer)
		_update_presence_shader()

	print("[Cliche] Scene binding complete: %d troffers, %d observer anchors, %d spatial emitters, %d fuel cans. Player: %s, Observer: %s, HUD: %s" % [
		fixtures.size(),
		observer_markers.size(),
		spatial_ambience_sources.size(),
		get_tree().get_nodes_in_group("fuel_can").size(),
		"OK" if player != null else "MISSING",
		"OK" if observer != null else "MISSING",
		"OK" if hud_status_label != null else "MISSING"
	])

func _process(delta: float) -> void:
	elapsed += delta
	ballast_spark_intensity = move_toward(ballast_spark_intensity, 0.0, delta * 4.0)

	_update_environmental_director(delta)

	# Dynamic electrical ballast simulation per fixture
	var capture_brownout := 1.0
	if observer_state == ObserverState.CAPTURE:
		capture_brownout = clampf(observer_capture_timer / 1.65, 0.03, 1.0)

	for f in fixtures:
		var wave_dip := 1.0
		if env_electrical_wave_active and f.panel != null:
			var f_xz := Vector2(f.panel.global_position.x, f.panel.global_position.z)
			var dist_to_wave_origin := f_xz.distance_to(env_electrical_wave_origin)
			var dist_from_front := absf(dist_to_wave_origin - env_electrical_wave_progress)
			if dist_from_front < 5.5:
				wave_dip = 0.22 + 0.78 * smoothstep(0.0, 5.5, dist_from_front)
				if randf() < 0.06:
					ballast_spark_intensity = maxf(ballast_spark_intensity, 0.35)

		match f.type:
			FixtureType.NORMAL:
				var desync := sin(elapsed * (116.0 + f.seed_offset * 1.7)) * 0.015 * env_tension
				var flutter := sin(elapsed * 120.0 + f.seed_offset) * 0.018 + sin(elapsed * 2.2 + f.seed_offset) * 0.015 + desync
				var energy_mul := (1.0 + flutter) * wave_dip * capture_brownout
				if f.spot_light != null:
					f.spot_light.light_energy = f.base_spot_energy * energy_mul
				if f.fill_light != null:
					f.fill_light.light_energy = f.base_fill_energy * energy_mul
				if f.panel != null:
					var mat := f.panel.get_surface_override_material(0) as StandardMaterial3D
					if mat != null:
						mat.emission_energy_multiplier = f.base_emission * energy_mul

			FixtureType.SLOW_PULSE:
				var pulse := sin(elapsed * 1.4 + f.seed_offset) * 0.16 + sin(elapsed * 0.35) * 0.08
				var energy_mul := (1.0 + pulse) * wave_dip * capture_brownout
				if f.spot_light != null:
					f.spot_light.light_energy = f.base_spot_energy * energy_mul
				if f.fill_light != null:
					f.fill_light.light_energy = f.base_fill_energy * energy_mul
				if f.panel != null:
					var mat := f.panel.get_surface_override_material(0) as StandardMaterial3D
					if mat != null:
						mat.emission_energy_multiplier = f.base_emission * energy_mul

			FixtureType.DYING:
				var flutter := randf_range(-0.06, 0.06) + sin(elapsed * 45.0 + f.seed_offset) * 0.04
				var energy_mul := (1.0 + flutter) * wave_dip * capture_brownout
				if f.spot_light != null:
					f.spot_light.light_energy = f.base_spot_energy * energy_mul
				if f.fill_light != null:
					f.fill_light.light_energy = f.base_fill_energy * energy_mul
				if f.panel != null:
					var mat := f.panel.get_surface_override_material(0) as StandardMaterial3D
					if mat != null:
						mat.emission_energy_multiplier = f.base_emission * energy_mul

			FixtureType.FAINT_EMERGENCY:
				var flutter := randf_range(-0.04, 0.04) + sin(elapsed * 24.0 + f.seed_offset) * 0.03
				var energy_mul := (1.0 + flutter) * wave_dip * capture_brownout
				if f.spot_light != null:
					f.spot_light.light_energy = f.base_spot_energy * energy_mul
				if f.fill_light != null:
					f.fill_light.light_energy = f.base_fill_energy * energy_mul
				if f.panel != null:
					var mat := f.panel.get_surface_override_material(0) as StandardMaterial3D
					if mat != null:
						mat.emission_energy_multiplier = f.base_emission * energy_mul

			FixtureType.STUTTER:
				f.stutter_timer -= delta
				if f.stutter_timer <= 0.0:
					var pick := randf()
					if pick < 0.60:
						f.stutter_state = 0 # Normal glow
						f.stutter_timer = randf_range(0.35, 1.40)
					elif pick < 0.85:
						f.stutter_state = 1 # Quick half-dip
						f.stutter_timer = randf_range(0.04, 0.11)
					else:
						f.stutter_state = 2 # Complete blackout blink
						f.stutter_timer = randf_range(0.03, 0.08)

				var stutter_mul := 1.0
				if f.stutter_state == 1:
					stutter_mul = 0.35
				elif f.stutter_state == 2:
					stutter_mul = 0.0
				var flutter := sin(elapsed * 120.0 + f.seed_offset) * 0.02
				var energy_mul := (stutter_mul + flutter) * wave_dip * capture_brownout
				if f.spot_light != null:
					f.spot_light.light_energy = f.base_spot_energy * energy_mul
				if f.fill_light != null:
					f.fill_light.light_energy = f.base_fill_energy * energy_mul
				if f.panel != null:
					var mat := f.panel.get_surface_override_material(0) as StandardMaterial3D
					if mat != null:
						mat.emission_energy_multiplier = f.base_emission * energy_mul

	_fill_audio_buffer()
	_fill_spatial_ambience()
	_update_observer_presence(delta)
	_update_lighter_hud(delta)

func _update_environmental_director(delta: float) -> void:
	env_director_timer += delta
	var target_tension := clampf((float(observer_encounters) * 0.12) + (observer_escalation * 0.45) + (observer_screen_threat * 0.45), 0.0, 1.0)
	env_tension = move_toward(env_tension, target_tension, delta * 0.15)

	# Periodic electrical instability waves travelling across sectors
	if env_electrical_wave_active:
		env_electrical_wave_progress += env_electrical_wave_speed * delta
		if env_electrical_wave_progress > 140.0:
			env_electrical_wave_active = false
	elif env_tension > 0.25 and randf() < (0.015 + env_tension * 0.03) * delta:
		env_electrical_wave_active = true
		env_electrical_wave_progress = 0.0
		env_electrical_wave_origin = Vector2(randf_range(-45.0, 45.0), randf_range(-45.0, 45.0))
		env_electrical_wave_speed = randf_range(18.0, 32.0)

	# Silence event mechanic
	silence_timer -= delta
	silence_cooldown -= delta
	if silence_timer <= 0.0 and silence_target > 0.0:
		silence_target = 0.0
	elif silence_cooldown <= 0.0 and env_tension > 0.35 and observer_state in [ObserverState.DORMANT, ObserverState.OBSERVING]:
		if randf() < 0.40:
			_trigger_silence_event(randf_range(5.0, 10.0))

	silence_intensity = move_toward(silence_intensity, silence_target, delta * (1.8 if silence_target > silence_intensity else 0.45))

	# Organic false positive disturbance events
	env_false_positive_timer -= delta
	if env_false_positive_timer <= 0.0:
		env_false_positive_timer = randf_range(24.0, 52.0) - env_tension * 14.0
		if randf() < 0.65:
			_trigger_organic_building_disturbance()

	distant_thump_intensity = move_toward(distant_thump_intensity, 0.0, delta * 1.5)

	# Track player acoustic sector
	if player != null:
		var p_pos := player.global_position
		if p_pos.y < -0.55 or p_pos.z > 23.0 and p_pos.x > -18.0 and p_pos.x < 18.0:
			current_player_sector = &"sump"
		elif p_pos.x < -20.0 and p_pos.z < 22.0:
			current_player_sector = &"forest"
		elif p_pos.x < -20.0 and p_pos.z > 22.0:
			current_player_sector = &"archive"
		elif p_pos.x > 18.0 and p_pos.z < -20.0:
			current_player_sector = &"crawlspace"
		elif p_pos.x > 20.0 and p_pos.z > 16.0:
			current_player_sector = &"nowhere"
		elif p_pos.z < -14.0:
			current_player_sector = &"north"
		else:
			current_player_sector = &"reception"

func _trigger_silence_event(duration: float) -> void:
	silence_target = 1.0
	silence_timer = duration
	silence_cooldown = randf_range(35.0, 65.0)

func _trigger_organic_building_disturbance() -> void:
	var roll := randf()
	if roll < 0.35:
		ballast_spark_intensity = 0.85
	elif roll < 0.65:
		distant_thump_intensity = randf_range(0.4, 0.9)
	elif roll < 0.85:
		if not env_electrical_wave_active and player != null:
			env_electrical_wave_active = true
			env_electrical_wave_progress = 0.0
			var p_xz := Vector2(player.global_position.x, player.global_position.z)
			env_electrical_wave_origin = p_xz + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))

func _fill_audio_buffer() -> void:
	if audio_playback == null:
		return

	var frames_available := audio_playback.get_frames_available()
	var sample_rate := 22050.0
	var dt := 1.0 / sample_rate
	var silence_mult := clampf(1.0 - silence_intensity * 0.96, 0.0, 1.0)
	var tension_hiss := env_tension * 0.035

	for _i in range(frames_available):
		var base_hum := (
			sin(audio_phase * TAU * 60.0) * 0.18
			+ sin(audio_phase * TAU * 120.0) * 0.38
			+ sin(audio_phase * TAU * 180.0) * 0.12
			+ sin(audio_phase * TAU * 240.0) * 0.08
			+ sin(audio_phase * TAU * 360.0) * 0.04
		)
		var flutter := sin(audio_phase * TAU * 0.85) * 0.04 + sin(audio_phase * TAU * 7.3) * 0.02
		var noise := (randf() * 2.0 - 1.0) * (0.015 + ballast_spark_intensity * 0.15 + tension_hiss)
		var sample := (base_hum * (1.0 + flutter) + noise) * silence_mult

		if distant_thump_intensity > 0.05:
			sample += sin(audio_phase * TAU * 28.0) * distant_thump_intensity * 0.15

		audio_playback.push_frame(Vector2(sample, sample))
		audio_phase += dt
		if audio_phase >= 1.0:
			audio_phase -= 1.0

func _fill_spatial_ambience() -> void:
	var sample_rate := 11025.0
	var silence_mult := clampf(1.0 - silence_intensity * 0.98, 0.0, 1.0)
	for source in spatial_ambience_sources:
		var playback := source["playback"] as AudioStreamGeneratorPlayback
		if playback == null:
			continue
		var phase: float = source["phase"]
		var smooth_noise: float = source["smooth_noise"]
		var kind: StringName = source["kind"]
		for _frame in range(playback.get_frames_available()):
			var sample := 0.0
			match kind:
				&"pump":
					sample = sin(phase * TAU * 31.0) * 0.18 + sin(phase * TAU * 62.0) * 0.055 + sin(phase * TAU * 15.5) * 0.025
				&"draft", &"duct":
					smooth_noise = lerpf(smooth_noise, randf_range(-1.0, 1.0), 0.022)
					sample = smooth_noise * 0.22 + sin(phase * TAU * 76.0) * 0.020
				&"hvac":
					smooth_noise = lerpf(smooth_noise, randf_range(-1.0, 1.0), 0.018)
					sample = sin(phase * TAU * 42.0) * 0.12 + sin(phase * TAU * 84.0) * 0.04 + smooth_noise * 0.12
				&"forest":
					smooth_noise = lerpf(smooth_noise, randf_range(-1.0, 1.0), 0.015)
					sample = sin(phase * TAU * 28.5) * 0.14 + sin(phase * TAU * 57.0) * 0.035 + smooth_noise * 0.10
				&"archive":
					smooth_noise = lerpf(smooth_noise, randf_range(-1.0, 1.0), 0.012)
					sample = sin(phase * TAU * 140.0) * 0.045 + smooth_noise * 0.08
				&"nowhere":
					smooth_noise = lerpf(smooth_noise, randf_range(-1.0, 1.0), 0.016)
					sample = sin(phase * TAU * 49.5) * 0.07 + sin(phase * TAU * 51.5) * 0.07 + smooth_noise * 0.09
				_:
					smooth_noise = lerpf(smooth_noise, randf_range(-1.0, 1.0), 0.020)
					sample = smooth_noise * 0.20
			sample *= silence_mult
			playback.push_frame(Vector2(sample, sample))
			phase += 1.0 / sample_rate
			if phase >= 1.0:
				phase -= 1.0
		source["phase"] = phase

func _apply_observer_pose(variant: StringName) -> void:
	if observer == null:
		return
	var stance := observer.get_node_or_null("Stance")
	if stance == null:
		return
	var head_node := stance.get_node_or_null("Head") as MeshInstance3D
	var arm_l := stance.get_node_or_null("UpperArm_L") as MeshInstance3D
	var arm_r := stance.get_node_or_null("UpperArm_R") as MeshInstance3D
	var forearm_l := stance.get_node_or_null("Forearm_L") as MeshInstance3D
	var forearm_r := stance.get_node_or_null("Forearm_R") as MeshInstance3D
	var hand_l := stance.get_node_or_null("Hand_L") as MeshInstance3D
	var hand_r := stance.get_node_or_null("Hand_R") as MeshInstance3D
	var torso_node := stance.get_node_or_null("Torso") as MeshInstance3D

	observer_pose_variant = variant
	match variant:
		&"slump":
			if head_node:
				head_node.rotation_degrees = Vector3(18.0, 4.0, -12.0)
				head_node.position = Vector3(-0.065, 2.18, 0.06)
			if torso_node:
				torso_node.rotation_degrees = Vector3(6.0, 0.0, -4.5)
			if arm_l:
				arm_l.rotation_degrees = Vector3(12.0, 0.0, -14.0)
			if arm_r:
				arm_r.rotation_degrees = Vector3(4.0, 0.0, 6.0)
			if forearm_l:
				forearm_l.rotation_degrees = Vector3(14.0, 0.0, -8.0)
			if forearm_r:
				forearm_r.rotation_degrees = Vector3(6.0, 0.0, -2.0)

		&"peek_left":
			if head_node:
				head_node.rotation_degrees = Vector3(-4.0, 24.0, 16.0)
				head_node.position = Vector3(0.08, 2.26, -0.04)
			if torso_node:
				torso_node.rotation_degrees = Vector3(0.0, 12.0, 7.5)
			if arm_l:
				arm_l.rotation_degrees = Vector3(-2.0, 0.0, -4.0)
			if arm_r:
				arm_r.rotation_degrees = Vector3(14.0, 0.0, 18.0)

		&"peek_right":
			if head_node:
				head_node.rotation_degrees = Vector3(-4.0, -24.0, -16.0)
				head_node.position = Vector3(-0.12, 2.26, -0.04)
			if torso_node:
				torso_node.rotation_degrees = Vector3(0.0, -12.0, -7.5)
			if arm_l:
				arm_l.rotation_degrees = Vector3(14.0, 0.0, -18.0)
			if arm_r:
				arm_r.rotation_degrees = Vector3(-2.0, 0.0, 4.0)

		&"narrow_vigil":
			if head_node:
				head_node.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
				head_node.position = Vector3(-0.045, 2.29, -0.025)
			if torso_node:
				torso_node.rotation_degrees = Vector3(-2.0, 0.0, 0.0)
			if arm_l:
				arm_l.rotation_degrees = Vector3(4.0, 0.0, -4.0)
			if arm_r:
				arm_r.rotation_degrees = Vector3(4.0, 0.0, 4.0)
			if forearm_l:
				forearm_l.rotation_degrees = Vector3(0.0, 0.0, 0.0)
			if forearm_r:
				forearm_r.rotation_degrees = Vector3(0.0, 0.0, 0.0)

		_: # &"sentinel" default
			if head_node:
				head_node.rotation_degrees = Vector3(-7.0, 5.0, -2.5)
				head_node.position = Vector3(-0.045, 2.27, -0.025)
			if torso_node:
				torso_node.rotation_degrees = Vector3(3.0, 0.0, -1.7)
			if arm_l:
				arm_l.rotation_degrees = Vector3(1.5, 0.0, 7.0)
			if arm_r:
				arm_r.rotation_degrees = Vector3(1.5, 0.0, 10.0)
			if forearm_l:
				forearm_l.rotation_degrees = Vector3(-2.0, 0.0, -4.0)
			if forearm_r:
				forearm_r.rotation_degrees = Vector3(-2.0, 0.0, -7.0)
			if hand_l:
				hand_l.rotation_degrees = Vector3(-5.0, 0.0, -3.0)
			if hand_r:
				hand_r.rotation_degrees = Vector3(-5.0, 0.0, -5.5)

func _update_observer_presence(delta: float) -> void:
	if observer == null or player == null:
		return
	var camera_node := player.get_node_or_null("Head/Camera3D") as Camera3D
	if camera_node == null:
		return

	_update_observer_memory(delta)
	observer_state_timer -= delta
	observer_relocation_timer -= delta
	observer_attack_cooldown = maxf(0.0, observer_attack_cooldown - delta)
	observer_feedback = move_toward(observer_feedback, _observer_feedback_target(), delta * 0.85)
	observer_dread = clampf(observer_dread - delta * (0.012 if observer_state in [ObserverState.DORMANT, ObserverState.RECOVERY] else 0.002), 0.0, 1.0)
	if observer_state not in [ObserverState.MANIFESTED, ObserverState.PRESSURE, ObserverState.PURSUIT, ObserverState.CAPTURE]:
		observer_exposure_signal = move_toward(observer_exposure_signal, 0.0, delta * 0.78)
		observer_proximity_signal = move_toward(observer_proximity_signal, 0.0, delta * 0.54)
	if observer_state != ObserverState.CAPTURE:
		observer_screen_threat = clampf(observer_feedback * 0.52 + observer_exposure_signal * 0.58 + observer_proximity_signal * 0.24 + observer_dread * 0.28, 0.0, 1.0)
	if observer_state in [ObserverState.DORMANT, ObserverState.RECOVERY]:
		observer_composure = minf(1.0, observer_composure + delta * 0.016)

	var stance := observer.get_node_or_null("Stance") as Node3D
	if stance != null:
		var drift_scale := 0.42 if observer_state == ObserverState.PURSUIT else 1.0
		if observer_state == ObserverState.CAPTURE:
			stance.rotation_degrees.z = -2.0 + sin(observer_capture_phase * 14.0) * 1.8
			stance.position.x = sin(observer_capture_phase * 9.0) * 0.018
			stance.scale = Vector3.ONE * (1.0 + sin(observer_capture_phase * 11.0) * 0.018)
		else:
			stance.rotation_degrees.z = -1.15 + sin(elapsed * 0.23 + observer_sway_phase) * 0.16 * drift_scale
			stance.position.x = sin(elapsed * 0.37 + observer_sway_phase) * 0.006 * drift_scale
			stance.scale = Vector3.ONE

	match observer_state:
		ObserverState.DORMANT:
			_update_observer_dormant()
		ObserverState.OBSERVING:
			_update_observer_observing()
		ObserverState.MANIFESTED:
			_update_observer_manifested(delta, camera_node)
		ObserverState.PRESSURE:
			_update_observer_pressure(delta, camera_node)
		ObserverState.PURSUIT:
			_update_observer_pursuit(delta, camera_node)
		ObserverState.CAPTURE:
			_update_observer_capture(delta, camera_node)
		ObserverState.DISENGAGING:
			_update_observer_disengaging(delta)
		ObserverState.RECOVERY:
			_update_observer_recovery()

	if player.has_method("set_observer_pressure"):
		player.set_observer_pressure(clampf(maxf(observer_feedback * 0.82, maxf(observer_dread * 0.55, observer_screen_threat * 0.72)), 0.0, 1.0))
	_update_presence_shader()

func _update_observer_memory(delta: float) -> void:
	var moved := player.global_position.distance_to(observer_last_player_position)
	if moved < 4.0:
		observer_distance_travelled += moved
	observer_last_player_position = player.global_position
	var sector := _observer_sector_for(player.global_position)
	observer_visited_sectors[sector] = true

	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	if horizontal_speed > 4.1:
		observer_learned_flight = move_toward(observer_learned_flight, 1.0, delta * 0.010)
	else:
		observer_learned_flight = move_toward(observer_learned_flight, 0.0, delta * 0.0015)

	observer_safe_timer -= delta
	if observer_safe_timer <= 0.0 and observer_state not in [ObserverState.PURSUIT, ObserverState.PRESSURE] and player.is_on_floor():
		observer_safe_position = player.global_position
		observer_safe_timer = 4.0

	var progression_floor := _observer_progression() * 0.52 + minf(float(observer_encounters) * 0.055, 0.30)
	observer_escalation = maxf(observer_escalation, progression_floor)
	observer_escalation = clampf(observer_escalation, 0.0, 1.0)

func _observer_progression() -> float:
	var collected := 0
	var total_cans := 0
	var cans := get_tree().get_nodes_in_group("fuel_can")
	for can in cans:
		total_cans += 1
		if can.get("is_collected"):
			collected += 1
	var travel_progress := clampf(observer_distance_travelled / 380.0, 0.0, 1.0)
	var pickup_progress := clampf(float(collected) / maxf(1.0, float(total_cans)), 0.0, 1.0)
	var sector_progress := clampf(float(observer_visited_sectors.size()) / 7.0, 0.0, 1.0)
	return clampf(travel_progress * 0.34 + pickup_progress * 0.36 + sector_progress * 0.30, 0.0, 1.0)

func _observer_sector_for(pos: Vector3) -> StringName:
	if pos.y < -0.55 or pos.z > 23.0 and pos.x > -18.5 and pos.x < 18.5:
		return &"sump"
	if pos.x < -20.0 and pos.z < 23.0:
		return &"forest"
	if pos.x < -20.0 and pos.z > 28.0:
		return &"archive"
	if pos.x > 18.0 and pos.z < -20.0:
		return &"crawlspace"
	if pos.x > 20.0 and pos.z > 20.0:
		return &"nowhere"
	if pos.z < -20.0:
		return &"north"
	return &"reception"

func _observer_feedback_target() -> float:
	match observer_state:
		ObserverState.OBSERVING:
			return 0.07 + observer_escalation * 0.05
		ObserverState.MANIFESTED:
			return 0.16 + observer_presence * 0.16
		ObserverState.PRESSURE:
			return 0.42 + observer_escalation * 0.22
		ObserverState.PURSUIT:
			return 0.78 + observer_attack_charge * 0.16
		ObserverState.CAPTURE:
			return 1.0
		ObserverState.DISENGAGING:
			return 0.24
		_:
			return 0.0

func _update_observer_dormant() -> void:
	observer.visible = false
	observer_presence = move_toward(observer_presence, 0.0, 0.035)
	if observer_state_timer <= 0.0:
		_set_observer_state(ObserverState.OBSERVING, randf_range(5.0, 10.0))

func _update_observer_observing() -> void:
	observer.visible = false
	observer_presence = move_toward(observer_presence, 0.04 + observer_escalation * 0.025, 0.012)
	if observer_state_timer <= 0.0:
		_begin_observer_manifestation()

func _begin_observer_manifestation() -> void:
	observer_variant = _choose_observer_variant()
	var minimum := lerpf(27.0, 20.0, observer_escalation)
	var maximum := lerpf(52.0, 38.0, observer_escalation)
	if _place_observer_for_state(minimum, maximum, true):
		observer_encounters += 1
		observer_manifest_steps = 0
		_set_observer_state(ObserverState.MANIFESTED, randf_range(8.0, 13.5))
	else:
		_set_observer_state(ObserverState.OBSERVING, randf_range(5.0, 9.0))

func _choose_observer_variant() -> StringName:
	var roll := randf()
	if observer_learned_flight > 0.48 and roll < 0.38:
		return &"intercept"
	if observer_learned_approach > 0.42 and roll < 0.52:
		return &"retreating_lure"
	if observer_escalation > 0.62 and roll < 0.44:
		return &"relentless"
	var pool: Array[StringName] = [&"sentinel", &"doorway", &"peripheral", &"tail"]
	return pool[randi() % pool.size()]

func _update_observer_manifested(delta: float, camera_node: Camera3D) -> void:
	var distance := player.global_position.distance_to(observer.global_position)
	var sight := _observer_visibility(camera_node, observer.global_position)
	var has_sight: bool = sight["visible"]
	var view_dot: float = sight["dot"]
	_update_observer_exposure(delta, has_sight, view_dot, distance)

	var target_presence := 0.28 if has_sight else 0.08
	observer_presence = move_toward(observer_presence, target_presence, delta * 0.65)
	if distance < 34.0:
		var look_target := Vector3(player.global_position.x, observer.global_position.y, player.global_position.z)
		var current_quat := observer.global_transform.basis.get_rotation_quaternion()
		var target_xform := observer.global_transform.looking_at(look_target, Vector3.UP)
		observer.global_transform.basis = Basis(current_quat.slerp(target_xform.basis.get_rotation_quaternion(), delta * 1.8))

	if has_sight and view_dot > 0.82 and observer_seen_time > 1.35 and observer_escalation > 0.38:
		_set_observer_state(ObserverState.PRESSURE, randf_range(4.5, 7.5))
		return

	if distance < 14.5 and (has_sight or observer_exposure_time > 1.0):
		_set_observer_state(ObserverState.PRESSURE, randf_range(3.5, 6.0))
		return

	# When the player is looking away, take deliberate staggered steps closer
	if not has_sight and distance > 16.0 and observer_escalation > 0.25:
		observer_unseen_advance_timer += delta
		if observer_unseen_advance_timer > 3.2:
			observer_unseen_advance_timer = 0.0
			var forward := (player.global_position - observer.global_position).normalized()
			var advance_step := forward * randf_range(4.0, 7.5)
			var candidate_pos := observer.global_position + advance_step
			var grounded := _observer_grounded_position(candidate_pos)
			if grounded != Vector3.INF and grounded.distance_to(player.global_position) > 12.0:
				var new_sight := _observer_visibility(camera_node, grounded)
				if not bool(new_sight["visible"]):
					observer.global_position = grounded

	if not has_sight and observer_seen_time > 0.35 and observer_state_timer < 4.0:
		_conceal_observer(randf_range(16.0, 28.0))
		return

	if observer_state_timer <= 0.0:
		if has_sight:
			_set_observer_state(ObserverState.DISENGAGING, 2.4)
		else:
			_conceal_observer(randf_range(14.0, 24.0))

func _update_observer_pressure(delta: float, camera_node: Camera3D) -> void:
	var distance := player.global_position.distance_to(observer.global_position)
	var sight := _observer_visibility(camera_node, observer.global_position)
	var has_sight: bool = sight["visible"]
	var view_dot: float = sight["dot"]
	_update_observer_exposure(delta, has_sight, view_dot, distance)

	observer_presence = move_toward(observer_presence, 0.72 + observer_screen_threat * 0.28, delta * 1.2)
	observer_dread = minf(1.0, observer_dread + delta * 0.045)
	_apply_observer_light_pressure()

	var look_target := Vector3(player.global_position.x, observer.global_position.y, player.global_position.z)
	var current_quat := observer.global_transform.basis.get_rotation_quaternion()
	var target_xform := observer.global_transform.looking_at(look_target, Vector3.UP)
	observer.global_transform.basis = Basis(current_quat.slerp(target_xform.basis.get_rotation_quaternion(), delta * 3.4))

	if distance > 10.0 and not has_sight and observer_relocation_timer <= 0.0:
		var flank_min := lerpf(14.0, 9.0, observer_escalation)
		var flank_max := lerpf(24.0, 16.0, observer_escalation)
		if _place_observer_for_state(flank_min, flank_max, true):
			observer_relocation_timer = randf_range(3.5, 6.0)
			return

	if distance < 6.8 and has_sight:
		_observer_attack_player()
		return

	if observer_seen_time > 2.6 and observer_composure > 0.35 and observer_escalation > 0.45:
		_begin_observer_pursuit()
		return

	if not has_sight and observer_unseen_time > 4.2:
		_set_observer_state(ObserverState.DISENGAGING, 2.0)
		return

	if observer_state_timer <= 0.0:
		if observer_escalation > 0.55 and randf() < 0.45:
			_begin_observer_pursuit()
		else:
			_set_observer_state(ObserverState.DISENGAGING, 2.2)

func _begin_observer_pursuit() -> void:
	_set_observer_state(ObserverState.PURSUIT, randf_range(6.5, 10.5))
	observer_attack_charge = 0.0
	observer_blocked_time = 0.0
	observer_escape_time = 0.0
	_apply_observer_pose(&"slump")

func _update_observer_pursuit(delta: float, camera_node: Camera3D) -> void:
	var distance := player.global_position.distance_to(observer.global_position)
	var sight := _observer_visibility(camera_node, observer.global_position)
	var has_sight: bool = sight["visible"]
	var view_dot: float = sight["dot"]
	_update_observer_exposure(delta, has_sight, view_dot, distance)

	observer_presence = 1.0
	observer_dread = 1.0
	_apply_observer_light_pressure()

	var chase_speed := lerpf(2.2, 4.4, observer_escalation)
	if has_sight and view_dot > 0.65:
		chase_speed *= 0.62
		observer_composure = maxf(0.0, observer_composure - delta * 0.18)
	else:
		chase_speed *= 1.25

	var look_target := Vector3(player.global_position.x, observer.global_position.y, player.global_position.z)
	var current_quat := observer.global_transform.basis.get_rotation_quaternion()
	var target_xform := observer.global_transform.looking_at(look_target, Vector3.UP)
	observer.global_transform.basis = Basis(current_quat.slerp(target_xform.basis.get_rotation_quaternion(), delta * 4.2))

	var step_direction := (player.global_position - observer.global_position)
	step_direction.y = 0.0
	if step_direction.length_squared() > 0.01:
		step_direction = step_direction.normalized()
		var candidate_move := observer.global_position + step_direction * chase_speed * delta
		var grounded := _observer_grounded_position(candidate_move)
		if grounded != Vector3.INF:
			observer.global_position = grounded
			observer_blocked_time = 0.0
		else:
			observer_blocked_time += delta

	if distance < 2.3:
		_observer_attack_player()
		return

	if distance > 28.0 or observer_blocked_time > 2.0:
		observer_escape_time += delta
		if observer_escape_time > 2.2:
			_set_observer_state(ObserverState.DISENGAGING, 2.5)
			return

	if observer_composure <= 0.05 and has_sight and view_dot > 0.85:
		_set_observer_state(ObserverState.DISENGAGING, 1.8)
		return

	if observer_state_timer <= 0.0:
		_set_observer_state(ObserverState.DISENGAGING, 2.0)

func _update_observer_capture(delta: float, camera_node: Camera3D) -> void:
	observer_capture_timer += delta
	observer_capture_phase = clampf(observer_capture_timer / 1.65, 0.0, 1.0)
	observer_presence = 1.0
	observer_screen_threat = 1.0
	observer_dread = 1.0
	ballast_spark_intensity = maxf(ballast_spark_intensity, 0.95)

	var target_anchor := player.global_position + (-camera_node.global_transform.basis.z * 1.45)
	target_anchor.y = player.global_position.y + 0.05
	observer.global_position = observer.global_position.lerp(target_anchor, delta * 8.5)
	var face_pos := Vector3(player.global_position.x, observer.global_position.y, player.global_position.z)
	if observer.global_position.distance_squared_to(face_pos) > 0.01:
		observer.look_at(face_pos, Vector3.UP)

	if player.has_method("set_movement_frozen"):
		player.set_movement_frozen(true)

	if observer_capture_timer >= 1.05 and not observer_capture_pending_reset:
		observer_capture_pending_reset = true
		player.global_position = observer_safe_position
		observer.visible = false

	if observer_capture_timer >= 1.65:
		if player.has_method("set_movement_frozen"):
			player.set_movement_frozen(false)
		if player.has_method("trigger_recovery"):
			player.trigger_recovery()
		observer_capture_pending_reset = false
		observer_capture_timer = 0.0
		observer_capture_phase = 0.0
		_set_observer_state(ObserverState.RECOVERY, randf_range(28.0, 48.0))

func _update_observer_exposure(delta: float, has_sight: bool, view_dot: float, distance: float) -> void:
	observer_last_distance = distance
	observer_last_view_dot = view_dot
	observer_has_sight = has_sight
	if has_sight:
		observer_seen_time += delta
		observer_unseen_time = 0.0
		if view_dot > 0.72:
			observer_centered_time += delta
			observer_exposure_time += delta * 1.35
			observer_learned_gaze = move_toward(observer_learned_gaze, 1.0, delta * 0.02)
		else:
			observer_exposure_time += delta * 0.45
	else:
		observer_seen_time = 0.0
		observer_centered_time = 0.0
		observer_unseen_time += delta
		observer_exposure_time = maxf(0.0, observer_exposure_time - delta * 0.65)

	var player_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var to_obs := (observer.global_position - player.global_position).normalized()
	var move_dir := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	if player_speed > 1.2 and move_dir.dot(to_obs) > 0.45:
		observer_learned_approach = move_toward(observer_learned_approach, 1.0, delta * 0.015)
	else:
		observer_learned_approach = move_toward(observer_learned_approach, 0.0, delta * 0.002)

	var raw_exposure := smoothstep(0.40, 0.95, view_dot) if has_sight else 0.0
	observer_exposure_signal = move_toward(observer_exposure_signal, raw_exposure, delta * (2.8 if raw_exposure > observer_exposure_signal else 0.75))
	var prox_factor := 1.0 - smoothstep(2.5, 18.0, distance)
	observer_proximity_signal = move_toward(observer_proximity_signal, prox_factor, delta * 1.5)

func _observer_attack_player() -> void:
	if observer_attack_cooldown > 0.0 or observer_state == ObserverState.CAPTURE:
		return
	_set_observer_state(ObserverState.CAPTURE, 1.65)
	observer_capture_timer = 0.0
	observer_capture_phase = 0.0
	observer_capture_pending_reset = false
	observer_attack_cooldown = 12.0
	_apply_observer_pose(&"slump")
	ballast_spark_intensity = 1.0

func _begin_observer_disengage() -> void:
	_set_observer_state(ObserverState.DISENGAGING, 2.0)

func _update_observer_disengaging(delta: float) -> void:
	observer_presence = move_toward(observer_presence, 0.0, delta * 0.55)
	if observer_state_timer <= 0.0 or observer_presence <= 0.02:
		_conceal_observer(_observer_recovery_delay())

func _update_observer_recovery() -> void:
	observer.visible = false
	observer_presence = 0.0
	if observer_state_timer <= 0.0:
		_set_observer_state(ObserverState.DORMANT, randf_range(8.0, 16.0))

func _observer_recovery_delay() -> float:
	var base_delay := lerpf(26.0, 12.0, observer_escalation)
	if observer_learned_approach > 0.55:
		base_delay *= 0.80
	return randf_range(base_delay * 0.85, base_delay * 1.25)

func _set_observer_state(next_state: ObserverState, duration: float) -> void:
	observer_state = next_state
	observer_state_timer = duration
	if next_state == ObserverState.DORMANT or next_state == ObserverState.RECOVERY:
		observer.visible = false
		observer_presence = 0.0
		observer_seen_time = 0.0
		observer_exposure_time = 0.0
		observer_unseen_time = 0.0
		observer_attack_charge = 0.0
	elif next_state == ObserverState.CAPTURE:
		observer.visible = true
		observer_seen_time = 0.0
		observer_exposure_time = 0.0
		observer_unseen_time = 0.0
		observer_attack_charge = 0.0

func _conceal_observer(next_delay: float) -> void:
	_set_observer_state(ObserverState.RECOVERY, next_delay)
	observer_presence = 0.0
	_update_presence_shader()

func _place_observer_at_next_marker() -> void:
	if not _place_observer_for_state(20.0, 52.0, true):
		_set_observer_state(ObserverState.OBSERVING, randf_range(5.0, 9.0))

func _place_observer_for_state(min_distance: float, max_distance: float, prefer_unseen: bool) -> bool:
	if observer_markers.is_empty() or player == null:
		return false
	var camera_node := player.get_node_or_null("Head/Camera3D") as Camera3D
	if camera_node == null:
		return false
	var best_index := -1
	var best_score := INF
	var target_distance := (min_distance + max_distance) * 0.5
	var allow_edge_violation := observer_escalation > 0.64 and randf() < (0.035 + observer_escalation * 0.085)
	for candidate_index in range(observer_markers.size()):
		if observer_recent_markers.has(candidate_index):
			continue
		var grounded := _observer_grounded_position(observer_markers[candidate_index])
		if grounded == Vector3.INF:
			continue
		var distance := player.global_position.distance_to(grounded)
		if distance < min_distance or distance > max_distance:
			continue
		var sight := _observer_visibility(camera_node, grounded)
		var view_dot: float = sight["dot"]
		var samples: int = sight["samples"]
		if prefer_unseen and not allow_edge_violation and view_dot > 0.42 and samples > 0:
			continue
		if allow_edge_violation and view_dot > 0.82 and samples > 0:
			continue
		var score := absf(distance - target_distance) + randf_range(0.0, 3.5)
		var role: StringName = observer_marker_roles[candidate_index]
		if role == &"doorway" and observer_variant in [&"doorway", &"intercept"]:
			score -= 5.0
		elif role == &"intersection" and observer_variant in [&"tail", &"peripheral"]:
			score -= 4.0
		elif role == &"dead_end" and observer_variant == &"sentinel":
			score -= 3.5
		elif role == &"pillar":
			score -= 4.5
		elif role == &"obscured":
			score -= 2.2
		if samples in [1, 2]:
			score -= 3.6
		elif samples == 0:
			score += 2.4
		if score < best_score:
			best_score = score
			best_index = candidate_index
	if best_index < 0:
		return false
	observer_marker_index = best_index
	observer.global_position = _observer_grounded_position(observer_markers[best_index])
	var look_target := Vector3(player.global_position.x, observer.global_position.y, player.global_position.z)
	if observer.global_position.distance_squared_to(look_target) > 0.01:
		observer.look_at(look_target, Vector3.UP)

	var chosen_role: StringName = observer_marker_roles[best_index]
	var chosen_pose: StringName = &"sentinel"
	if chosen_role in [&"pillar", &"doorway"]:
		var to_obs := (observer.global_position - player.global_position).normalized()
		var p_right := camera_node.global_transform.basis.x
		chosen_pose = &"peek_left" if to_obs.dot(p_right) > 0.0 else &"peek_right"
	elif chosen_role in [&"dead_end", &"distant"]:
		chosen_pose = &"narrow_vigil" if randf() < 0.55 else &"sentinel"
	elif observer_state in [ObserverState.PRESSURE, ObserverState.PURSUIT]:
		chosen_pose = &"slump" if randf() < 0.65 else &"narrow_vigil"
	else:
		var candidate_poses: Array[StringName] = [&"sentinel", &"slump", &"narrow_vigil", &"peek_left", &"peek_right"]
		chosen_pose = candidate_poses[randi() % candidate_poses.size()]
	_apply_observer_pose(chosen_pose)

	observer.visible = true
	observer_seen_time = 0.0
	observer_centered_time = 0.0
	observer_exposure_time = 0.0
	observer_unseen_time = 0.0
	observer_presence = 0.0
	observer_sway_phase = randf_range(0.0, TAU)
	observer_recent_markers.push_back(best_index)
	while observer_recent_markers.size() > 3:
		observer_recent_markers.pop_front()
	return true

func _observer_grounded_position(candidate: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var floor_query := PhysicsRayQueryParameters3D.create(candidate + Vector3(0.0, 1.25, 0.0), candidate + Vector3(0.0, -0.85, 0.0))
	floor_query.exclude = [player.get_rid()] if player != null else []
	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty():
		return Vector3.INF
	var floor_position: Vector3 = floor_hit["position"]
	if absf(floor_position.y - candidate.y) > 0.48:
		return Vector3.INF
	var grounded := Vector3(candidate.x, floor_position.y + 0.015, candidate.z)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 2.72
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = capsule
	clearance.transform = Transform3D(Basis.IDENTITY, grounded + Vector3(0.0, 1.36, 0.0))
	clearance.collision_mask = 1
	clearance.exclude = [player.get_rid()] if player != null else []
	if not space.intersect_shape(clearance, 1).is_empty():
		return Vector3.INF
	return grounded

func _observer_visibility(camera_node: Camera3D, candidate: Vector3) -> Dictionary:
	var camera_pos := camera_node.global_position
	var forward := -camera_node.global_transform.basis.z.normalized()
	var to_target := (candidate + Vector3(0.0, 1.5, 0.0) - camera_pos)
	var distance := to_target.length()
	var dir := to_target / maxf(distance, 0.001)
	var dot := forward.dot(dir)
	var space := get_world_3d().direct_space_state

	var sample_heights := [0.45, 1.35, 2.15]
	var samples_visible := 0
	for h in sample_heights:
		var sample_point := candidate + Vector3(0.0, h, 0.0)
		var query := PhysicsRayQueryParameters3D.create(camera_pos, sample_point)
		query.exclude = [player.get_rid()] if player != null else []
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			samples_visible += 1
		else:
			var hit_pos: Vector3 = hit["position"]
			if hit_pos.distance_to(sample_point) < 0.35:
				samples_visible += 1

	return {
		"visible": samples_visible > 0 and dot > 0.18,
		"dot": dot,
		"distance": distance,
		"samples": samples_visible
	}

func _observer_has_walk_path(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3(0.0, 0.5, 0.0), to + Vector3(0.0, 0.5, 0.0))
	query.exclude = [player.get_rid()] if player != null else []
	return space.intersect_ray(query).is_empty()

func _apply_observer_light_pressure() -> void:
	if fixtures.is_empty() or observer == null:
		return
	var nearest_index := -1
	var nearest_distance := INF
	for i in range(fixtures.size()):
		var f := fixtures[i]
		if f.panel == null:
			continue
		var dist := observer.global_position.distance_to(f.panel.global_position)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest_index = i
	if nearest_index >= 0 and nearest_distance < 12.0:
		var target := fixtures[nearest_index]
		if target.spot_light != null:
			target.spot_light.light_energy = target.base_spot_energy * randf_range(0.15, 0.55)
		if target.panel != null:
			var mat := target.panel.get_surface_override_material(0) as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = target.base_emission * randf_range(0.20, 0.60)

func debug_observer_force_state(state_name: String) -> Dictionary:
	observer_debug_forced = true
	match state_name.to_lower():
		"dormant":
			_set_observer_state(ObserverState.DORMANT, 999.0)
		"observing":
			_set_observer_state(ObserverState.OBSERVING, 999.0)
		"manifested":
			observer_escalation = maxf(observer_escalation, 0.35)
			_begin_observer_manifestation()
		"pressure":
			observer_escalation = maxf(observer_escalation, 0.65)
			if observer.visible:
				_set_observer_state(ObserverState.PRESSURE, 999.0)
			else:
				_begin_observer_manifestation()
				_set_observer_state(ObserverState.PRESSURE, 999.0)
		"pursuit":
			observer_escalation = maxf(observer_escalation, 0.85)
			if not observer.visible:
				_begin_observer_manifestation()
			_begin_observer_pursuit()
		"capture":
			_observer_attack_player()
		"disengaging":
			_begin_observer_disengage()
		"recovery":
			_set_observer_state(ObserverState.RECOVERY, 999.0)
		_:
			return {"ok": false, "error": "Unknown state: " + state_name}
	return debug_observer_snapshot()

func _debug_align_player_to(target_pos: Vector3) -> void:
	if player == null:
		return
	var to_obs := (target_pos - player.global_position)
	to_obs.y = 0.0
	if to_obs.length_squared() > 0.001:
		player.rotation.y = atan2(-to_obs.x, -to_obs.z)
		var head_node := player.get_node_or_null("Head") as Node3D
		if head_node != null:
			head_node.rotation.x = 0.0
		var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
		if cam != null:
			cam.rotation.x = 0.0

func debug_setup_scenario(scenario_id: int) -> Dictionary:
	if player == null or observer == null:
		return {"ok": false, "error": "Player or Observer null"}
	observer_debug_forced = true
	match scenario_id:
		1: # SCENARIO 1: RECEPTION CORRIDOR FRAME
			player.global_position = Vector3(0.0, 0.05, 3.5)
			_debug_align_player_to(Vector3(0.0, 0.0, -18.0))
			observer_variant = &"doorway"
			observer.global_position = Vector3(0.0, 0.0, -20.5)
			observer.look_at(Vector3(0.0, 0.0, 3.5), Vector3.UP)
			_apply_observer_pose(&"sentinel")
			observer.visible = true
			observer_presence = 0.35
			_set_observer_state(ObserverState.MANIFESTED, 30.0)

		2: # SCENARIO 2: PILLAR FOREST SILHOUETTE
			player.global_position = Vector3(-20.0, 0.05, 0.0)
			_debug_align_player_to(Vector3(-38.0, 0.0, 0.0))
			observer_variant = &"sentinel"
			observer.global_position = Vector3(-38.0, 0.0, 8.5)
			observer.look_at(Vector3(-20.0, 0.0, 0.0), Vector3.UP)
			_apply_observer_pose(&"peek_left")
			observer.visible = true
			observer_presence = 0.45
			_set_observer_state(ObserverState.MANIFESTED, 30.0)

		3: # SCENARIO 3: SUNKEN PIT ELEVATION VIEW
			player.global_position = Vector3(0.0, 0.05, 22.0)
			_debug_align_player_to(Vector3(0.0, -1.2, 40.0))
			observer_variant = &"relentless"
			observer.global_position = Vector3(1.5, -1.2 + 0.015, 38.0)
			observer.look_at(Vector3(0.0, -1.2, 22.0), Vector3.UP)
			_apply_observer_pose(&"narrow_vigil")
			observer.visible = true
			observer_presence = 0.55
			_set_observer_state(ObserverState.PRESSURE, 30.0)

		4: # SCENARIO 4: IMMEDIATE PURSUIT
			player.global_position = Vector3(0.0, 0.05, -24.0)
			_debug_align_player_to(Vector3(0.0, 0.0, -38.0))
			observer_variant = &"relentless"
			observer.global_position = Vector3(0.0, 0.0, -36.0)
			observer.look_at(Vector3(0.0, 0.0, -24.0), Vector3.UP)
			_apply_observer_pose(&"slump")
			observer.visible = true
			observer_presence = 0.85
			_set_observer_state(ObserverState.PURSUIT, 30.0)

		_:
			return {"ok": false, "error": "Invalid scenario ID"}

	_update_presence_shader()
	return debug_observer_snapshot()

func debug_observer_snapshot() -> Dictionary:
	return {
		"ok": true,
		"state": ObserverState.keys()[observer_state],
		"state_timer": observer_state_timer,
		"escalation": observer_escalation,
		"presence": observer_presence,
		"screen_threat": observer_screen_threat,
		"dread": observer_dread,
		"composure": observer_composure,
		"variant": String(observer_variant),
		"pose": String(observer_pose_variant),
		"visible": observer.visible if observer != null else false,
		"observer_pos": observer.global_position if observer != null else Vector3.ZERO,
		"player_pos": player.global_position if player != null else Vector3.ZERO,
		"distance": observer_last_distance,
		"view_dot": observer_last_view_dot,
		"has_sight": observer_has_sight,
		"sector": String(_observer_sector_for(player.global_position if player != null else Vector3.ZERO)),
		"total_anchors": observer_markers.size(),
		"total_fixtures": fixtures.size()
	}

func _update_presence_shader() -> void:
	if observer_material != null:
		observer_material.set_shader_parameter("presence", clampf(observer_presence, 0.0, 1.0))
		observer_material.set_shader_parameter("threat", clampf(observer_screen_threat, 0.0, 1.0))
	if observer_head_material != null:
		observer_head_material.emission_energy_multiplier = lerpf(0.16, 0.34, clampf(observer_screen_threat, 0.0, 1.0))
	if hud_atmosphere_material != null:
		var capture_signal := clampf(observer_capture_timer / 1.65, 0.0, 1.0)
		hud_atmosphere_material.set_shader_parameter("presence", clampf(observer_presence, 0.0, 1.0))
		hud_atmosphere_material.set_shader_parameter("danger", clampf(observer_feedback, 0.0, 1.0))
		hud_atmosphere_material.set_shader_parameter("exposure", clampf(observer_exposure_signal, 0.0, 1.0))
		hud_atmosphere_material.set_shader_parameter("proximity", clampf(observer_proximity_signal, 0.0, 1.0))
		hud_atmosphere_material.set_shader_parameter("capture", capture_signal)
		hud_atmosphere_material.set_shader_parameter("capture_phase", clampf(observer_capture_phase / 1.65, 0.0, 1.0))
		hud_atmosphere_material.set_shader_parameter("silence", clampf(silence_intensity, 0.0, 1.0))

func _show_hud_toast(msg: String) -> void:
	if hud_toast_label == null or hud_toast_container == null:
		return
	hud_toast_label.text = msg
	if toast_tween != null and toast_tween.is_valid():
		toast_tween.kill()
	hud_toast_container.modulate = Color(1.0, 1.0, 1.0, 1.0)
	hud_toast_container.scale = Vector2(1.04, 1.04)
	toast_tween = create_tween()
	toast_tween.tween_property(hud_toast_container, "scale", Vector2(1.0, 1.0), 0.20)
	toast_tween.tween_interval(3.5)
	toast_tween.tween_property(hud_toast_container, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.60)

func _update_lighter_hud(_delta: float) -> void:
	if player == null or hud_fuel_fill == null:
		return

	var fuel_ratio: float = player.get_fuel_ratio() if player.has_method("get_fuel_ratio") else 1.0
	var is_lit: bool = player.is_lighter_lit() if player.has_method("is_lighter_lit") else false
	var is_eq: bool = player.is_lighter_equipped() if player.has_method("is_lighter_equipped") else false

	hud_fuel_fill.size.x = 224.0 * fuel_ratio
	hud_fuel_label.text = "%d%%" % int(round(fuel_ratio * 100.0))

	if fuel_ratio <= 0.0:
		hud_status_label.text = "EMPTY"
		hud_status_label.add_theme_color_override("font_color", Color("#cc3333"))
		hud_fuel_fill.color = Color(0.40, 0.15, 0.12, 0.6)
	elif is_lit:
		if fuel_ratio < 0.20:
			hud_status_label.text = "LOW FUEL"
			var pulse := (sin(elapsed * 12.0) + 1.0) * 0.5
			var warn_col := Color("#ffaa33").lerp(Color("#ff2211"), pulse)
			hud_status_label.add_theme_color_override("font_color", warn_col)
			hud_fuel_fill.color = Color("#d48822").lerp(Color("#dd3311"), pulse)
		else:
			hud_status_label.text = "BURNING"
			hud_status_label.add_theme_color_override("font_color", Color("#ffaa33"))
			hud_fuel_fill.color = Color("#d48822")
	else:
		hud_status_label.text = "READY" if is_eq else "STOWED"
		hud_status_label.add_theme_color_override("font_color", Color("#8e7c54"))
		hud_fuel_fill.color = Color("#9e6b22")
