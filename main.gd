extends Node3D
## Level 0: The Yellow Halls
## An authentic, atmospheric Backrooms recreation built with Godot 4.7.
## Expanded multi-sector complex with weird geometry, crawlspaces, sunken sump, and A+ lighting.

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
var observer_material: StandardMaterial3D

# Collectible Lighter Fluid Can Materials
var fuel_can_body_mat: StandardMaterial3D
var fuel_can_band_mat: StandardMaterial3D
var fuel_can_silver_mat: StandardMaterial3D
var fuel_can_spout_mat: StandardMaterial3D

var fixtures: Array[FixtureData] = []
var fuel_cans: Array[Dictionary] = []
var elapsed := 0.0

# A restrained, non-hostile presence used to seed the future stalking loop.
var observer: Node3D
var observer_markers: Array[Vector3] = []
var observer_marker_index := 0
var observer_seen_time := 0.0
var observer_centered_time := 0.0
var observer_exposure_time := 0.0
var observer_hide_timer := 0.0
var observer_relocation_timer := 0.0
var observer_presence := 0.0
var observer_sway_phase := 0.0
var hud_atmosphere_material: ShaderMaterial

# Procedural fluorescent audio
var audio_playback: AudioStreamGeneratorPlayback
var audio_phase := 0.0
var ballast_spark_intensity := 0.0

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
	_make_materials()
	_build_environment()
	_build_shell()
	_build_architecture()
	_build_environmental_dressing()
	_build_troffer_lighting()
	_build_fuel_pickups()
	_build_ambient_hum()
	_spawn_player()
	_build_hud()
	_build_observer_presence()

func _process(delta: float) -> void:
	elapsed += delta
	ballast_spark_intensity = move_toward(ballast_spark_intensity, 0.0, delta * 4.0)

	# Dynamic electrical ballast simulation per fixture
	for f in fixtures:
		match f.type:
			FixtureType.NORMAL:
				var flutter := sin(elapsed * 120.0 + f.seed_offset) * 0.018 + sin(elapsed * 2.2 + f.seed_offset) * 0.015
				var energy_mul := 1.0 + flutter
				if f.spot_light != null:
					f.spot_light.light_energy = f.base_spot_energy * energy_mul
				if f.fill_light != null:
					f.fill_light.light_energy = f.base_fill_energy * energy_mul

			FixtureType.SLOW_PULSE:
				var pulse := sin(elapsed * 1.4 + f.seed_offset) * 0.16 + sin(elapsed * 0.35) * 0.08
				var energy_mul := 1.0 + pulse
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
				var energy_mul := 1.0 + flutter
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
				var energy_mul := 1.0 + flutter
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
						f.stutter_timer = randf_range(0.8, 3.2)
					elif pick < 0.85:
						f.stutter_state = 1 # 26Hz rapid ballast stutter
						f.stutter_timer = randf_range(0.2, 0.6)
						ballast_spark_intensity = 1.0
					else:
						f.stutter_state = 2 # Brownout / blackout
						f.stutter_timer = randf_range(0.1, 0.45)
						ballast_spark_intensity = 0.5

				var mul := 1.0
				if f.stutter_state == 1:
					mul = 0.15 + (1.05 if fmod(elapsed * 26.0 + f.seed_offset, 1.0) > 0.45 else 0.0)
				elif f.stutter_state == 2:
					mul = 0.02

				if f.spot_light != null:
					f.spot_light.light_energy = f.base_spot_energy * mul
				if f.fill_light != null:
					f.fill_light.light_energy = f.base_fill_energy * mul
				if f.panel != null:
					var mat := f.panel.get_surface_override_material(0) as StandardMaterial3D
					if mat != null:
						mat.emission_energy_multiplier = f.base_emission * mul

			FixtureType.DEAD:
				pass

		# Animate cathode filament glows on dead, dying, and emergency fixtures
		if f.filament_light != null and f.base_filament_energy > 0.0:
			var filament_flutter := 1.0 + randf_range(-0.06, 0.06) + sin(elapsed * 7.5 + f.seed_offset) * 0.05
			f.filament_light.light_energy = f.base_filament_energy * filament_flutter

	# Animate fuel pickups (rotation and gentle hovering)
	for item in fuel_cans:
		if item["collected"]:
			continue
		var visual: Node3D = item["visual"]
		var glow: OmniLight3D = item["glow"]
		if not item["grounded"]:
			visual.rotate_y(delta * 1.35)
			visual.position.y = sin(elapsed * 2.5 + item["seed"]) * 0.022
		else:
			var pulse := sin(elapsed * 2.8 + item["seed"]) * 0.06
			if glow != null:
				glow.light_energy = 0.42 + pulse

	_fill_audio_buffer()
	_update_lighter_hud(delta)
	_update_observer_presence(delta)

func _build_ambient_hum() -> void:
	var audio := AudioStreamPlayer.new()
	audio.name = "FluorescentHum"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.15
	audio.stream = gen
	audio.volume_db = -18.0
	add_child(audio)
	audio.play()
	audio_playback = audio.get_stream_playback() as AudioStreamGeneratorPlayback

func _fill_audio_buffer() -> void:
	if audio_playback == null:
		return
	var frames_available := audio_playback.get_frames_available()
	var sample_rate := 22050.0
	for _f in range(frames_available):
		var s60 := sin(audio_phase * TAU * 60.0) * 0.42
		var s120 := sin(audio_phase * TAU * 120.0) * 0.30
		var s180 := sin(audio_phase * TAU * 180.0) * 0.16
		var s240 := sin(audio_phase * TAU * 240.0) * 0.09
		var spark := (randf_range(-0.15, 0.15) if randf() < 0.1 else 0.0) * ballast_spark_intensity
		# The observer should never announce itself through an obvious audio sting.
		var presence_noise := randf_range(-0.008, 0.008) * observer_presence
		var noise := randf_range(-0.022, 0.022) + spark + presence_noise
		var sample := (s60 + s120 + s180 + s240 + noise) * 0.22
		audio_playback.push_frame(Vector2(sample, sample))
		audio_phase += 1.0 / sample_rate
		if audio_phase >= 1.0:
			audio_phase -= 1.0

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	var img := Image.load_from_file(path)
	if img != null:
		return ImageTexture.create_from_image(img)
	return null

func _make_materials() -> void:
	# 1. Iconic chevron Backrooms wallpaper
	var wp_tex := _load_tex("res://wallpaper_level0.png")
	if wp_tex == null:
		wp_tex = _load_tex("res://backrooms_wallpapers_9.jpg")

	wallpaper_material = StandardMaterial3D.new()
	wallpaper_material.albedo_color = Color(0.95, 0.93, 0.86)
	if wp_tex != null:
		wallpaper_material.albedo_texture = wp_tex
	wallpaper_material.roughness = 0.84
	wallpaper_material.uv1_triplanar = true
	wallpaper_material.uv1_world_triplanar = true
	wallpaper_material.uv1_scale = Vector3(1.4, 1.4, 1.4)

	# 2. Continuous damp loop-pile commercial carpet
	var carpet_tex := _load_tex("res://carpet_albedo.png")
	var carpet_norm := _load_tex("res://carpet_normal.png")
	floor_material = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.92, 0.90, 0.84)
	if carpet_tex != null:
		floor_material.albedo_texture = carpet_tex
	if carpet_norm != null:
		floor_material.normal_enabled = true
		floor_material.normal_texture = carpet_norm
		floor_material.normal_scale = 0.90
	floor_material.roughness = 0.94
	floor_material.uv1_triplanar = true
	floor_material.uv1_world_triplanar = true
	floor_material.uv1_scale = Vector3(0.5, 0.5, 0.5)

	# 3. Acoustic 2x2 drop-ceiling tiles
	var ceil_tex := _load_tex("res://ceiling_tiles.png")
	ceiling_material = StandardMaterial3D.new()
	ceiling_material.albedo_color = Color(0.92, 0.91, 0.86)
	if ceil_tex != null:
		ceiling_material.albedo_texture = ceil_tex
	ceiling_material.roughness = 0.92
	ceiling_material.uv1_triplanar = true
	ceiling_material.uv1_world_triplanar = true
	ceiling_material.uv1_scale = Vector3(0.8333, 0.8333, 0.8333)

	# 4. Wood baseboard & chair rail trims
	trim_material = StandardMaterial3D.new()
	trim_material.albedo_color = Color("#6c421b")
	trim_material.roughness = 0.65

	# 5. Half-wall countertop cap rail
	cap_material = StandardMaterial3D.new()
	cap_material.albedo_color = Color("#583311")
	cap_material.roughness = 0.44

	# 6. Soffit / dropped bulkhead drywall
	soffit_material = wallpaper_material

	# 7. Ceiling return air vent grills
	vent_material = StandardMaterial3D.new()
	vent_material.albedo_color = Color("#2a2b28")
	vent_material.roughness = 0.42
	vent_material.metallic = 0.55

	# 8. Industrial pipes
	pipe_material = StandardMaterial3D.new()
	pipe_material.albedo_color = Color("#3e403d")
	pipe_material.metallic = 0.75
	pipe_material.roughness = 0.38

	# 9. Standard fluorescent troffer diffuser panel (authentic Backrooms sterile 4200K green-yellow)
	troffer_panel_material = StandardMaterial3D.new()
	troffer_panel_material.albedo_color = Color("#ebf0cb")
	troffer_panel_material.emission_enabled = true
	troffer_panel_material.emission = Color("#ebf0cb")
	troffer_panel_material.emission_energy_multiplier = 2.0
	troffer_panel_material.roughness = 0.85

	# 9b. Dying fluorescent panel (aged phosphor decay - Jaundiced Pale Ivory/Titanium)
	troffer_panel_dying_material = StandardMaterial3D.new()
	troffer_panel_dying_material.albedo_color = Color("#d4cca2")
	troffer_panel_dying_material.emission_enabled = true
	troffer_panel_dying_material.emission = Color("#c7c09e")
	troffer_panel_dying_material.emission_energy_multiplier = 0.95
	troffer_panel_dying_material.roughness = 0.85

	# 9c. Faint emergency fixture panel (degraded ballast - Sickly Desaturated Green-White)
	troffer_panel_faint_material = StandardMaterial3D.new()
	troffer_panel_faint_material.albedo_color = Color("#cad4b2")
	troffer_panel_faint_material.emission_enabled = true
	troffer_panel_faint_material.emission = Color("#b8c298")
	troffer_panel_faint_material.emission_energy_multiplier = 0.70
	troffer_panel_faint_material.roughness = 0.85

	# 9d. Dead / burned-out panel (dark gray / unlit frosted acrylic)
	troffer_panel_dead_material = StandardMaterial3D.new()
	troffer_panel_dead_material.albedo_color = Color("#222320")
	troffer_panel_dead_material.emission_enabled = false
	troffer_panel_dead_material.roughness = 0.85

	# 10. Troffer fixture metal frame
	troffer_frame_material = StandardMaterial3D.new()
	troffer_frame_material.albedo_color = Color("#6e6c62")
	troffer_frame_material.roughness = 0.52

	# 10b. Tube end oxidized emitter electrodes (realistic darkened rings, no amateur orange glow)
	filament_glow_material = StandardMaterial3D.new()
	filament_glow_material.albedo_color = Color("#22201d")
	filament_glow_material.roughness = 0.85
	filament_glow_material.metallic = 0.35

	# 11. Outlet faceplates
	var outlet_tex := _load_tex("res://outlet.png")
	outlet_material = StandardMaterial3D.new()
	outlet_material.albedo_color = Color(1.0, 1.0, 1.0)
	if outlet_tex != null:
		outlet_material.albedo_texture = outlet_tex
	else:
		outlet_material.albedo_color = Color("#b88f54")
	outlet_material.roughness = 0.5

	# 11b. Environmental decay materials. Kept restrained so the wallpaper remains dominant.
	damp_material = StandardMaterial3D.new()
	damp_material.albedo_color = Color(0.11, 0.095, 0.045, 0.72)
	damp_material.roughness = 0.48
	damp_material.metallic = 0.04
	damp_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	wet_floor_material = StandardMaterial3D.new()
	wet_floor_material.albedo_color = Color(0.075, 0.07, 0.035, 0.58)
	wet_floor_material.roughness = 0.16
	wet_floor_material.metallic = 0.18
	wet_floor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	void_material = StandardMaterial3D.new()
	void_material.albedo_color = Color("#050604")
	void_material.roughness = 0.96

	cable_material = StandardMaterial3D.new()
	cable_material.albedo_color = Color("#121310")
	cable_material.roughness = 0.58
	cable_material.metallic = 0.36

	tile_face_material = ceiling_material.duplicate() as StandardMaterial3D
	tile_face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tile_face_material.roughness = 0.94

	tile_core_material = StandardMaterial3D.new()
	tile_core_material.albedo_color = Color("#aaa58f")
	tile_core_material.roughness = 1.0
	tile_core_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	observer_material = StandardMaterial3D.new()
	# Alpha-hashed, light-reactive charcoal lets the figure break up in haze instead of
	# reading as a hard black cardboard cutout.
	observer_material.albedo_color = Color(0.008, 0.009, 0.006, 0.34)
	observer_material.roughness = 1.0
	observer_material.metallic = 0.0
	observer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	observer_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 12. Lighter Fluid Can PBR Materials
	fuel_can_body_mat = StandardMaterial3D.new()
	fuel_can_body_mat.albedo_color = Color("#d99b26")
	fuel_can_body_mat.metallic = 0.70
	fuel_can_body_mat.roughness = 0.35

	fuel_can_band_mat = StandardMaterial3D.new()
	fuel_can_band_mat.albedo_color = Color("#141412")
	fuel_can_band_mat.roughness = 0.85

	fuel_can_silver_mat = StandardMaterial3D.new()
	fuel_can_silver_mat.albedo_color = Color("#c5c9cc")
	fuel_can_silver_mat.metallic = 0.95
	fuel_can_silver_mat.roughness = 0.22

	fuel_can_spout_mat = StandardMaterial3D.new()
	fuel_can_spout_mat.albedo_color = Color("#d82828")
	fuel_can_spout_mat.roughness = 0.38

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#080805")

	# Ambient lighting: Softened murky olive-charcoal so silhouettes & geometry remain legible in the dark
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#323528")
	env.ambient_light_energy = 0.165

	# SSAO
	env.ssao_enabled = true
	env.ssao_radius = 2.6
	env.ssao_intensity = 3.8
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssao_horizon = 0.05

	# SSIL
	env.ssil_enabled = true
	env.ssil_radius = 4.2
	env.ssil_intensity = 0.75

	# Volumetric Fog: Thick dusty air catching light shafts
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color("#9b9770")
	env.volumetric_fog_emission = Color("#0c0e09")
	env.volumetric_fog_emission_energy = 0.35
	env.volumetric_fog_anisotropy = 0.38
	env.volumetric_fog_length = 55.0

	# Atmospheric Distance Fog
	env.fog_enabled = true
	env.fog_light_color = Color("#0e100a")
	env.fog_density = 0.014
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 55.0

	# Filmic Tonemapper & Contrast
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.04
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 0.88
	env.adjustment_brightness = 0.96

	# Eerie fluorescent bloom
	env.glow_enabled = true
	env.glow_intensity = 0.48
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.0

	world.environment = env
	add_child(world)

func _build_shell() -> void:
	# North Main Floor Slab (X: [-52, 52], Z: [-52, 23])
	_add_floor_slab("Floor_NorthMain", Vector3(0.0, -0.1, -14.5), Vector3(104.0, 0.2, 75.0))

	# South-West Floor Slab (X: [-52, -18], Z: [23, 52])
	_add_floor_slab("Floor_SouthWest", Vector3(-35.0, -0.1, 37.5), Vector3(34.0, 0.2, 29.0))

	# South-East Floor Slab (X: [18, 52], Z: [23, 52])
	_add_floor_slab("Floor_SouthEast", Vector3(35.0, -0.1, 37.5), Vector3(34.0, 0.2, 29.0))

	# South Perimeter Floor Strip (X: [-18, 18], Z: [50, 52])
	_add_floor_slab("Floor_SouthEdge", Vector3(0.0, -0.1, 51.0), Vector3(36.0, 0.2, 2.0))

	# Sunken Sump Chamber Floor Slab at Y = -1.2m (X: [-18, 18], Z: [23, 50])
	_add_floor_slab("Floor_SumpPit", Vector3(0.0, -1.3, 36.5), Vector3(36.0, 0.2, 27.0))

	# Sump Ramp descending from Y = 0.0 to Y = -1.2m (X: [-3.0, 3.0], Z: [23.0, 29.0])
	# Starts seamlessly at Z=23 portal threshold and lands on Sump pit floor at Y = -1.2m
	_add_ramp("Ramp_SumpDescent", Vector2(0.0, 23.0), Vector2(0.0, 29.0), 6.0, 0.0, -1.2)

	# Continuous Acoustic Ceiling (104m x 104m at CEILING_H = 2.80m)
	var ceil_inst := MeshInstance3D.new()
	ceil_inst.name = "AcousticCeiling"
	var ceil_box := BoxMesh.new()
	ceil_box.size = Vector3(104.0, 0.2, 104.0)
	ceil_box.material = ceiling_material
	ceil_inst.mesh = ceil_box
	ceil_inst.position = Vector3(0.0, CEILING_H + 0.1, 0.0)
	add_child(ceil_inst)

	var ceil_body := StaticBody3D.new()
	ceil_body.name = "CeilingCollision"
	var ceil_col := CollisionShape3D.new()
	var ceil_shape := BoxShape3D.new()
	ceil_shape.size = Vector3(104.0, 0.2, 104.0)
	ceil_col.shape = ceil_shape
	ceil_col.position = Vector3(0.0, CEILING_H + 0.1, 0.0)
	ceil_body.add_child(ceil_col)
	add_child(ceil_body)

	# Outer Perimeter Enclosure Walls
	_add_wall_segment("Outer_North", Vector2(-52.0, -52.0), Vector2(52.0, -52.0))
	_add_wall_segment("Outer_South", Vector2(-52.0, 52.0), Vector2(52.0, 52.0))
	_add_wall_segment("Outer_West", Vector2(-52.0, -52.0), Vector2(-52.0, 52.0))
	_add_wall_segment("Outer_East", Vector2(52.0, -52.0), Vector2(52.0, 52.0))

func _add_floor_slab(label: String, center: Vector3, size: Vector3) -> void:
	var floor_inst := MeshInstance3D.new()
	floor_inst.name = label
	var floor_box := BoxMesh.new()
	floor_box.size = size
	floor_box.material = floor_material
	floor_inst.mesh = floor_box
	floor_inst.position = center
	add_child(floor_inst)

	var floor_body := StaticBody3D.new()
	floor_body.name = label + "_Col"
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = size
	floor_col.shape = floor_shape
	floor_col.position = center
	floor_body.add_child(floor_col)
	add_child(floor_body)

func _add_ramp(label: String, start_xz: Vector2, end_xz: Vector2, width: float, y_start: float, y_end: float) -> void:
	var start_pos := Vector3(start_xz.x, y_start, start_xz.y)
	var end_pos := Vector3(end_xz.x, y_end, end_xz.y)
	var delta := end_pos - start_pos
	var length := delta.length()
	if length < 0.05:
		return

	var center := (start_pos + end_pos) * 0.5
	var thickness := 0.20
	var forward := delta / length
	var h_dir := Vector3(forward.x, 0.0, forward.z).normalized()
	if h_dir.length_squared() < 0.001:
		h_dir = Vector3.FORWARD
	var right := Vector3.UP.cross(h_dir).normalized()
	var up := forward.cross(right).normalized()
	var ramp_basis := Basis(forward, up, -right)
	var xform := Transform3D(ramp_basis, center - up * (thickness * 0.5))

	var ramp := MeshInstance3D.new()
	ramp.name = label
	var box := BoxMesh.new()
	box.size = Vector3(length, thickness, width)
	box.material = floor_material
	ramp.mesh = box
	ramp.transform = xform
	add_child(ramp)

	var body := StaticBody3D.new()
	body.name = label + "_Col"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, thickness, width)
	col.shape = shape
	col.transform = xform
	body.add_child(col)
	add_child(body)

func _build_architecture() -> void:
	# SECTOR 1: CENTRAL RECEPTION LOBBY & SPINE CORRIDORS
	_add_half_wall("HalfWall_Foreground_L", Vector2(-2.0, 6.0), Vector2(-2.0, -4.5), 1.10)
	_add_wall_segment("Reception_Partition_Left", Vector2(-2.0, -4.5), Vector2(-12.0, -4.5))

	_add_column("Col_Main_FL", Vector2(-5.0, 0.0))
	_add_column("Col_Main_BL", Vector2(-5.0, -8.0))
	_add_column("Col_Main_BR", Vector2(5.0, -8.0))
	_add_column("Col_Main_FR", Vector2(5.0, 0.0))

	_add_soffit("Soffit_Header_Entry", Vector2(-12.0, 6.0), Vector2(16.0, 6.0), 0.55)
	_add_soffit("Soffit_Header_Mid", Vector2(-12.0, -8.0), Vector2(16.0, -8.0), 0.50)
	_add_soffit("Soffit_Long_L", Vector2(-5.0, -14.0), Vector2(-5.0, 6.0), 0.45)
	_add_soffit("Soffit_Long_R", Vector2(5.0, -14.0), Vector2(5.0, 6.0), 0.45)

	_add_wall_segment("Wall_Mid_L", Vector2(-20.0, -14.0), Vector2(-3.0, -14.0))
	_add_soffit("Door_Header_NorthCenter", Vector2(-3.0, -14.0), Vector2(3.0, -14.0), 0.75)
	_add_wall_segment("Wall_Mid_R", Vector2(3.0, -14.0), Vector2(18.0, -14.0))

	_add_wall_segment("Wall_South_L", Vector2(-20.0, 14.0), Vector2(-3.5, 14.0))
	_add_soffit("Door_Header_SouthCenter", Vector2(-3.5, 14.0), Vector2(3.5, 14.0), 0.75)
	_add_wall_segment("Wall_South_R", Vector2(3.5, 14.0), Vector2(18.0, 14.0))

	_add_wall_segment("Wall_West_L", Vector2(-20.0, -14.0), Vector2(-20.0, -4.0))
	_add_soffit("Door_Header_West", Vector2(-20.0, -4.0), Vector2(-20.0, 4.0), 0.75)
	_add_wall_segment("Wall_West_R", Vector2(-20.0, 4.0), Vector2(-20.0, 14.0))

	_add_wall_segment("Wall_East_L", Vector2(18.0, -14.0), Vector2(18.0, -3.0))
	_add_soffit("Door_Header_East", Vector2(18.0, -3.0), Vector2(18.0, 3.0), 0.75)
	_add_wall_segment("Wall_East_R", Vector2(18.0, 3.0), Vector2(18.0, 14.0))

	_add_half_wall("HalfWall_Right_Mid", Vector2(9.0, -8.0), Vector2(9.0, -2.0), 1.10)

	# SECTOR 2: THE PILLAR FOREST / MONOLITH GRID
	_add_wall_segment("Pillar_NorthWall_1", Vector2(-52.0, -22.0), Vector2(-32.0, -22.0))
	_add_soffit("Pillar_NorthPortal", Vector2(-32.0, -22.0), Vector2(-28.0, -22.0), 0.80)
	_add_wall_segment("Pillar_NorthWall_2", Vector2(-28.0, -22.0), Vector2(-20.0, -22.0))

	_add_wall_segment("Pillar_SouthWall_1", Vector2(-52.0, 22.0), Vector2(-32.0, 22.0))
	_add_soffit("Pillar_SouthPortal", Vector2(-32.0, 22.0), Vector2(-28.0, 22.0), 0.80)
	_add_wall_segment("Pillar_SouthWall_2", Vector2(-28.0, 22.0), Vector2(-20.0, 22.0))

	var col_xs := [-26.0, -32.0, -38.0, -44.0]
	var col_zs := [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]
	var col_idx := 0
	for cx in col_xs:
		for cz in col_zs:
			col_idx += 1
			_add_column("Col_Forest_%d" % col_idx, Vector2(cx, cz), Vector2(1.3, 1.3))
			if col_idx % 4 == 0:
				_add_outlet_on_wall(Vector3(cx, 0.35, cz + 0.66), 0.0)

	_add_vent_grill(Vector3(-29.0, CEILING_H - 0.005, -9.0), Vector2(1.2, 0.6))
	_add_vent_grill(Vector3(-41.0, CEILING_H - 0.005, -3.0), Vector2(1.2, 0.6))
	_add_vent_grill(Vector3(-29.0, CEILING_H - 0.005, 9.0), Vector2(1.2, 0.6))
	_add_vent_grill(Vector3(-41.0, CEILING_H - 0.005, 15.0), Vector2(1.2, 0.6))

	# SECTOR 3: THE ANOMALOUS STAGGER & BLIND CORRIDORS
	_add_wall_segment("North_Z22_L", Vector2(-20.0, -22.0), Vector2(4.0, -22.0))
	_add_wall_segment("North_Z22_R", Vector2(10.0, -22.0), Vector2(18.0, -22.0))

	_add_wall_segment("North_Xminus8", Vector2(-8.0, -22.0), Vector2(-8.0, -34.0))
	_add_wall_segment("North_X6", Vector2(6.0, -22.0), Vector2(6.0, -34.0))

	_add_wall_segment("North_Z34_L", Vector2(-24.0, -34.0), Vector2(-2.0, -34.0))
	_add_wall_segment("North_Z34_R", Vector2(4.0, -34.0), Vector2(18.0, -34.0))

	_add_wall_segment("North_Z44_L", Vector2(-24.0, -44.0), Vector2(-6.0, -44.0))
	_add_wall_segment("North_Z44_R", Vector2(0.0, -44.0), Vector2(14.0, -44.0))

	_add_wall_segment("Blind_Pocket_West", Vector2(-18.0, -44.0), Vector2(-18.0, -52.0))
	_add_wall_segment("Blind_Pocket_East", Vector2(-14.0, -44.0), Vector2(-14.0, -52.0))
	_add_outlet_on_wall(Vector3(-16.0, 0.35, -51.84), deg_to_rad(180.0))

	_add_wall_segment("Blind_Alcove_X8", Vector2(8.0, -44.0), Vector2(8.0, -52.0))
	_add_outlet_on_wall(Vector3(7.84, 0.35, -48.0), deg_to_rad(90.0))

	_add_soffit("Soffit_North_Kink1", Vector2(-2.0, -34.0), Vector2(4.0, -34.0), 0.70)
	_add_soffit("Soffit_North_Kink2", Vector2(-6.0, -44.0), Vector2(0.0, -44.0), 0.70)

	_add_vent_grill(Vector3(-2.0, CEILING_H - 0.005, -20.0), Vector2(1.2, 0.6))
	_add_vent_grill(Vector3(0.0, CEILING_H - 0.005, -38.0), Vector2(1.2, 0.6))

	# SECTOR 4: THE CRAWLSPACE / LOW MAINTENANCE DUCTS
	_add_soffit("Crawl_Portal_Header_1", Vector2(18.0, -24.5), Vector2(18.0, -22.5), CEILING_H - 1.10)

	_add_wall_segment("Crawl_Wall_S1", Vector2(18.0, -22.5), Vector2(46.0, -22.5))
	_add_wall_segment("Crawl_Wall_N1", Vector2(18.0, -24.5), Vector2(43.0, -24.5))

	_add_wall_segment("Crawl_Wall_W2", Vector2(43.0, -24.5), Vector2(43.0, -42.5))
	_add_wall_segment("Crawl_Wall_E2", Vector2(45.5, -22.5), Vector2(45.5, -42.5))

	_add_wall_segment("Crawl_Wall_S3", Vector2(45.5, -42.5), Vector2(18.0, -42.5))
	_add_wall_segment("Crawl_Wall_N3", Vector2(43.0, -44.5), Vector2(18.0, -44.5))

	_add_soffit("Crawl_Portal_Header_2", Vector2(18.0, -44.5), Vector2(18.0, -42.5), CEILING_H - 1.10)

	_add_wall_segment("Crawl_Alcove_W", Vector2(32.0, -24.5), Vector2(32.0, -34.0))
	_add_wall_segment("Crawl_Alcove_E", Vector2(34.0, -24.5), Vector2(34.0, -34.0))
	_add_wall_segment("Crawl_Alcove_End", Vector2(32.0, -34.0), Vector2(34.0, -34.0))
	_add_outlet_on_wall(Vector3(33.0, 0.25, -33.84), deg_to_rad(180.0))

	_add_crawlspace_ceiling("CrawlCeil_MainRun", Vector2(18.0, -25.0), Vector2(46.0, -22.0), 1.10)
	_add_crawlspace_ceiling("CrawlCeil_NorthRun", Vector2(42.5, -43.0), Vector2(46.0, -24.0), 1.10)
	_add_crawlspace_ceiling("CrawlCeil_ReturnRun", Vector2(18.0, -45.0), Vector2(46.0, -42.0), 1.10)
	_add_crawlspace_ceiling("CrawlCeil_Alcove", Vector2(31.5, -34.5), Vector2(34.5, -24.0), 1.10)

	_add_pipe("Crawl_Pipe_Main", Vector3(18.5, 1.04, -23.1), Vector3(45.0, 1.04, -23.1), 0.04)
	_add_pipe("Crawl_Pipe_North", Vector3(44.8, 1.04, -23.5), Vector3(44.8, 1.04, -42.0), 0.04)
	_add_pipe("Crawl_Pipe_Return", Vector3(44.5, 1.04, -43.1), Vector3(18.5, 1.04, -43.1), 0.04)

	_add_vent_grill(Vector3(28.0, 1.095, -23.5), Vector2(0.8, 0.4))
	_add_vent_grill(Vector3(44.2, 1.095, -33.0), Vector2(0.8, 0.4), true)

	_add_outlet_on_wall(Vector3(26.0, 0.28, -22.34), deg_to_rad(180.0))
	_add_outlet_on_wall(Vector3(38.0, 0.28, -22.34), deg_to_rad(180.0))
	_add_outlet_on_wall(Vector3(44.25, 0.28, -38.0), deg_to_rad(90.0))

	# SECTOR 5: THE SUNKEN PIT / SUMP CHAMBER
	_add_retaining_edge("Retaining_Left", Vector2(-18.0, 23.0), Vector2(-3.0, 23.0), -1.2, 0.0)
	_add_half_wall("Guardrail_Left", Vector2(-18.0, 23.0), Vector2(-3.0, 23.0), 1.00, 0.0)

	_add_retaining_edge("Retaining_Right", Vector2(3.0, 23.0), Vector2(18.0, 23.0), -1.2, 0.0)
	_add_half_wall("Guardrail_Right", Vector2(3.0, 23.0), Vector2(18.0, 23.0), 1.00, 0.0)

	_add_wall_segment("Sump_Wall_West", Vector2(-18.0, 23.0), Vector2(-18.0, 50.0), 4.00, -1.2)
	_add_wall_segment("Sump_Wall_East", Vector2(18.0, 23.0), Vector2(18.0, 50.0), 4.00, -1.2)
	_add_wall_segment("Sump_Wall_South", Vector2(-18.0, 50.0), Vector2(18.0, 50.0), 4.00, -1.2)

	_add_soffit("Sump_Joist_1", Vector2(-18.0, 30.0), Vector2(18.0, 30.0), 0.90)
	_add_soffit("Sump_Joist_2", Vector2(-18.0, 38.0), Vector2(18.0, 38.0), 0.90)
	_add_soffit("Sump_Joist_3", Vector2(-18.0, 45.0), Vector2(18.0, 45.0), 0.90)

	_add_pipe("Sump_Pipe_1", Vector3(-17.5, 2.1, 30.2), Vector3(17.5, 2.1, 30.2), 0.06)
	_add_pipe("Sump_Pipe_2", Vector3(-17.5, 2.1, 38.2), Vector3(17.5, 2.1, 38.2), 0.06)

	_add_column("Col_Sump_1", Vector2(-8.0, 32.0), Vector2(1.4, 1.4), 4.00, -1.2)
	_add_column("Col_Sump_2", Vector2(8.0, 32.0), Vector2(1.4, 1.4), 4.00, -1.2)
	_add_column("Col_Sump_3", Vector2(-8.0, 42.0), Vector2(1.4, 1.4), 4.00, -1.2)
	_add_column("Col_Sump_4", Vector2(8.0, 42.0), Vector2(1.4, 1.4), 4.00, -1.2)

	_add_vent_grill(Vector3(0.0, CEILING_H - 0.005, 34.0), Vector2(1.4, 0.7))
	_add_vent_grill(Vector3(0.0, CEILING_H - 0.005, 46.0), Vector2(1.4, 0.7))
	_add_outlet_on_wall(Vector3(-17.84, -1.2 + 0.35, 36.0), deg_to_rad(90.0))
	_add_outlet_on_wall(Vector3(17.84, -1.2 + 0.35, 36.0), deg_to_rad(-90.0))
	_add_outlet_on_wall(Vector3(0.0, -1.2 + 0.35, 49.84), deg_to_rad(180.0))

	# SECTOR 6: TILTED ALCOVES & THE HALLWAY TO NOWHERE
	_add_wall_segment("Diag_Wall_1", Vector2(20.0, 20.0), Vector2(30.0, 30.0))
	_add_wall_segment("Diag_Wall_2", Vector2(22.0, 15.0), Vector2(34.0, 27.0))
	_add_wall_segment("Diag_Return_1", Vector2(34.0, 27.0), Vector2(40.0, 27.0))
	_add_wall_segment("Diag_Return_2", Vector2(30.0, 30.0), Vector2(40.0, 30.0))

	_add_wall_segment("Wedge_Wall_1", Vector2(24.0, 26.0), Vector2(24.0, 34.0))
	_add_wall_segment("Wedge_Wall_2", Vector2(24.0, 34.0), Vector2(28.0, 34.0))

	_add_wall_segment("Nowhere_Wall_North", Vector2(28.0, 37.1), Vector2(52.0, 37.1))
	_add_wall_segment("Nowhere_Wall_South", Vector2(28.0, 38.9), Vector2(52.0, 38.9))
	_add_soffit("Nowhere_Entry_Soffit", Vector2(28.0, 37.1), Vector2(28.0, 38.9), 0.70)
	_add_outlet_on_wall(Vector3(51.84, 0.35, 38.0), deg_to_rad(-90.0))

	_add_outlet_on_wall(Vector3(32.0, 0.35, 27.16), 0.0)
	_add_vent_grill(Vector3(35.0, CEILING_H - 0.005, 28.5), Vector2(1.2, 0.6))
	_add_vent_grill(Vector3(38.0, CEILING_H - 0.005, 38.0), Vector2(1.0, 0.5))

	# SECTOR 7: SOUTH-WEST DEAD ARCHIVE & STORAGE LABYRINTH
	_add_wall_segment("Archive_Run_1", Vector2(-48.0, 30.0), Vector2(-34.0, 30.0))
	_add_wall_segment("Archive_Run_2", Vector2(-34.0, 30.0), Vector2(-34.0, 42.0))
	_add_wall_segment("Archive_Cross_1", Vector2(-48.0, 42.0), Vector2(-38.0, 42.0))
	_add_soffit("Archive_Portal_1", Vector2(-38.0, 42.0), Vector2(-34.0, 42.0), 0.70)
	_add_wall_segment("Archive_Cross_2", Vector2(-34.0, 42.0), Vector2(-22.0, 42.0))

	_add_half_wall("Archive_Bay_1", Vector2(-44.0, 36.0), Vector2(-36.0, 36.0), 1.10)
	_add_half_wall("Archive_Bay_2", Vector2(-30.0, 36.0), Vector2(-22.0, 36.0), 1.10)

	_add_outlet_on_wall(Vector3(-47.84, 0.35, 34.0), deg_to_rad(90.0))
	_add_outlet_on_wall(Vector3(-22.16, 0.35, 38.0), deg_to_rad(-90.0))
	_add_vent_grill(Vector3(-38.0, CEILING_H - 0.005, 36.0), Vector2(1.2, 0.6))

	# --- TRAVERSAL OPTIMIZATION: STEPPED LEDGES, CURBS & CLIMBING PLATFORMS ---
	# 1. Reception Half-Wall Traversal Steps (allows vaulting over the 1.10m partition)
	_add_stepping_ledge("Reception_Step_West_T1", Vector3(-2.65, 0.175, 1.0), Vector3(0.70, 0.35, 2.4), false, false)
	_add_stepping_ledge("Reception_Step_West_T2", Vector3(-2.35, 0.525, 1.0), Vector3(0.40, 0.35, 2.4), true, false)
	_add_invisible_stair_ramp("Ramp_Reception_West", Vector2(-3.05, 1.0), Vector2(-2.15, 1.0), 2.4, 0.0, 0.70)

	_add_stepping_ledge("Reception_Step_East_T1", Vector3(-1.35, 0.175, 1.0), Vector3(0.70, 0.35, 2.4), false, false)
	_add_stepping_ledge("Reception_Step_East_T2", Vector3(-1.65, 0.525, 1.0), Vector3(0.40, 0.35, 2.4), true, false)
	_add_invisible_stair_ramp("Ramp_Reception_East", Vector2(-0.95, 1.0), Vector2(-1.85, 1.0), 2.4, 0.0, 0.70)

	# 2. Mid-Corridor Half-Wall Traversal Steps (X = 9.0, Z: -8.0 to -2.0)
	_add_stepping_ledge("MidWall_Step_West_T1", Vector3(8.35, 0.175, -5.0), Vector3(0.70, 0.35, 2.2), false, false)
	_add_stepping_ledge("MidWall_Step_West_T2", Vector3(8.65, 0.525, -5.0), Vector3(0.40, 0.35, 2.2), true, false)
	_add_invisible_stair_ramp("Ramp_MidWall_West", Vector2(7.95, -5.0), Vector2(8.85, -5.0), 2.2, 0.0, 0.70)

	_add_stepping_ledge("MidWall_Step_East_T1", Vector3(9.65, 0.175, -5.0), Vector3(0.70, 0.35, 2.2), false, false)
	_add_stepping_ledge("MidWall_Step_East_T2", Vector3(9.35, 0.525, -5.0), Vector3(0.40, 0.35, 2.2), true, false)
	_add_invisible_stair_ramp("Ramp_MidWall_East", Vector2(10.05, -5.0), Vector2(9.15, -5.0), 2.2, 0.0, 0.70)

	# 3. Sunken Sump Chamber Ramp Curbs & Multi-Tier Climbing Terraces (-1.2m pit)
	_add_ramp("Ramp_Curb_L", Vector2(-3.1, 23.0), Vector2(-3.1, 29.0), 0.22, 0.12, -1.08)
	_add_ramp("Ramp_Curb_R", Vector2(3.1, 23.0), Vector2(3.1, 29.0), 0.22, 0.12, -1.08)

	# West Sump Emergency Maintenance Stair (3 tiers: -0.85m, -0.50m, -0.15m up to 0.0m floor)
	_add_stepping_ledge("Sump_Stair_W_T1", Vector3(-15.4, -1.2 + 0.175, 25.5), Vector3(2.2, 0.35, 2.8), false, false)
	_add_stepping_ledge("Sump_Stair_W_T2", Vector3(-16.3, -1.2 + 0.525, 25.5), Vector3(1.6, 0.35, 2.8), false, false)
	_add_stepping_ledge("Sump_Stair_W_T3", Vector3(-17.2, -1.2 + 0.875, 25.5), Vector3(1.0, 0.35, 2.8), true, false)
	_add_invisible_stair_ramp("Ramp_Sump_West", Vector2(-14.3, 25.5), Vector2(-17.7, 25.5), 2.8, -1.2, 0.0)

	# East Sump Emergency Maintenance Stair (3 tiers: -0.85m, -0.50m, -0.15m up to 0.0m floor)
	_add_stepping_ledge("Sump_Stair_E_T1", Vector3(15.4, -1.2 + 0.175, 25.5), Vector3(2.2, 0.35, 2.8), false, false)
	_add_stepping_ledge("Sump_Stair_E_T2", Vector3(16.3, -1.2 + 0.525, 25.5), Vector3(1.6, 0.35, 2.8), false, false)
	_add_stepping_ledge("Sump_Stair_E_T3", Vector3(17.2, -1.2 + 0.875, 25.5), Vector3(1.0, 0.35, 2.8), true, false)
	_add_invisible_stair_ramp("Ramp_Sump_East", Vector2(14.3, 25.5), Vector2(17.7, 25.5), 2.8, -1.2, 0.0)

	# Sump Column Maintenance Plinths (Jumpable 0.35m risers)
	_add_stepping_ledge("Col_Sump1_Plinth", Vector3(-8.0, -1.2 + 0.175, 32.0), Vector3(2.2, 0.35, 2.2), true, true)
	_add_stepping_ledge("Col_Sump2_Plinth", Vector3(8.0, -1.2 + 0.175, 32.0), Vector3(2.2, 0.35, 2.2), true, true)

	# 4. SW Archive Half-Wall Stepped Vaulting Ledges
	_add_stepping_ledge("Archive_Step1_N_T1", Vector3(-40.0, 0.175, 35.35), Vector3(2.6, 0.35, 0.70), false, false)
	_add_stepping_ledge("Archive_Step1_N_T2", Vector3(-40.0, 0.525, 35.65), Vector3(2.6, 0.35, 0.40), true, false)
	_add_invisible_stair_ramp("Ramp_Archive1_North", Vector2(-40.0, 34.9), Vector2(-40.0, 35.9), 2.6, 0.0, 0.70)

	_add_stepping_ledge("Archive_Step1_S_T1", Vector3(-40.0, 0.175, 36.65), Vector3(2.6, 0.35, 0.70), false, false)
	_add_stepping_ledge("Archive_Step1_S_T2", Vector3(-40.0, 0.525, 36.35), Vector3(2.6, 0.35, 0.40), true, false)
	_add_invisible_stair_ramp("Ramp_Archive1_South", Vector2(-40.0, 37.1), Vector2(-40.0, 36.1), 2.6, 0.0, 0.70)

	_add_stepping_ledge("Archive_Step2_N_T1", Vector3(-26.0, 0.175, 35.35), Vector3(2.6, 0.35, 0.70), false, false)
	_add_stepping_ledge("Archive_Step2_N_T2", Vector3(-26.0, 0.525, 35.65), Vector3(2.6, 0.35, 0.40), true, false)
	_add_invisible_stair_ramp("Ramp_Archive2_North", Vector2(-26.0, 34.9), Vector2(-26.0, 35.9), 2.6, 0.0, 0.70)

	_add_stepping_ledge("Archive_Step2_S_T1", Vector3(-26.0, 0.175, 36.65), Vector3(2.6, 0.35, 0.70), false, false)
	_add_stepping_ledge("Archive_Step2_S_T2", Vector3(-26.0, 0.525, 36.35), Vector3(2.6, 0.35, 0.40), true, false)
	_add_invisible_stair_ramp("Ramp_Archive2_South", Vector2(-26.0, 37.1), Vector2(-26.0, 36.1), 2.6, 0.0, 0.70)

	# --- ARCHITECTURAL COHESION: DOORWAY THRESHOLDS, SEALED SECTORS & HEADER SOFFITS ---
	_add_doorway_threshold("Threshold_Crawl_Entry", Vector2(18.0, -23.5), 0.40, 1.9)
	_add_doorway_threshold("Threshold_Crawl_Exit", Vector2(18.0, -43.5), 0.40, 1.9)
	_add_doorway_threshold("Threshold_North_Entry", Vector2(0.0, -14.0), 5.8, 0.35)
	_add_doorway_threshold("Threshold_Sump_RampTop", Vector2(0.0, 23.0), 5.8, 0.35)

	_add_soffit("Door_Header_North_Z22", Vector2(4.0, -22.0), Vector2(10.0, -22.0), 0.75)
	_add_soffit("Soffit_PillarForest_North", Vector2(-20.0, -22.0), Vector2(-20.0, -14.0), 0.70)
	_add_soffit("Soffit_PillarForest_South", Vector2(-20.0, 14.0), Vector2(-20.0, 22.0), 0.70)
	_add_wall_segment("Nowhere_Portal_Return", Vector2(28.0, 34.0), Vector2(28.0, 37.1))
	_add_soffit("Soffit_Archive_Corridor", Vector2(-22.0, 42.0), Vector2(-18.0, 42.0), 0.75)
	_add_wall_segment("Crawl_Corner_Seal", Vector2(18.0, -22.0), Vector2(18.0, -22.5))

func _build_environmental_dressing() -> void:
	# Damp islands break up the tiled floor repetition and quietly guide the player between sectors.
	var damp_patches: Array[Dictionary] = [
		{"name": "Damp_Reception", "pos": Vector3(7.2, 0.006, -5.8), "size": Vector2(1.8, 0.7), "rot": 18.0},
		{"name": "Damp_NorthTurn", "pos": Vector3(-1.5, 0.006, -31.0), "size": Vector2(2.4, 0.9), "rot": -12.0},
		{"name": "Damp_PillarForest", "pos": Vector3(-37.0, 0.006, 5.0), "size": Vector2(2.0, 0.8), "rot": 34.0},
		{"name": "Damp_Archive", "pos": Vector3(-29.0, 0.006, 39.5), "size": Vector2(2.5, 0.8), "rot": 5.0},
		{"name": "Damp_Nowhere", "pos": Vector3(40.0, 0.006, 38.0), "size": Vector2(2.2, 0.45), "rot": 0.0, "wet": true},
		{"name": "Damp_Sump", "pos": Vector3(1.5, -1.194, 41.0), "size": Vector2(4.6, 1.35), "rot": -22.0, "wet": true},
		{"name": "Damp_SumpEdge", "pos": Vector3(-8.5, -1.194, 34.5), "size": Vector2(2.6, 0.65), "rot": 12.0, "wet": true}
	]
	for patch in damp_patches:
		_add_damp_patch(patch["name"], patch["pos"], patch["size"], patch["rot"], bool(patch.get("wet", false)))

	# Missing and displaced ceiling tiles give the otherwise regular grid readable landmarks.
	_add_missing_ceiling_tile("MissingTile_Reception", Vector3(8.0, CEILING_H, -10.0), 7.0)
	_add_missing_ceiling_tile("MissingTile_North", Vector3(-2.0, CEILING_H, -39.0), -4.0)
	_add_missing_ceiling_tile("MissingTile_Forest", Vector3(-46.0, CEILING_H, 10.5), 3.0)
	_add_missing_ceiling_tile("MissingTile_Archive", Vector3(-43.0, CEILING_H, 46.0), -9.0)

	_add_fallen_ceiling_tile("FallenTile_North", Vector3(-0.9, 0.025, -40.4), 18.0, false)
	_add_fallen_ceiling_tile("FallenTile_Archive", Vector3(-42.6, 0.025, 44.8), -20.0, true)

	# Loose utilities hang only where the grid is damaged; these also improve silhouette depth.
	_add_hanging_cable("Cable_North_A", Vector3(-2.2, 2.77, -39.0), Vector3(-2.0, 1.82, -39.1), 0.013)
	_add_hanging_cable("Cable_North_B", Vector3(-1.8, 2.77, -39.0), Vector3(-1.65, 2.18, -38.86), 0.009)
	_add_hanging_cable("Cable_Archive", Vector3(-43.2, 2.77, 46.0), Vector3(-43.0, 1.72, 45.9), 0.012)

	# Weak maintenance beacons establish depth in the intentionally under-lit sectors.
	_add_wall_beacon("Beacon_NorthPocket", Vector3(-16.0, 1.30, -51.78), 180.0, Color("#b7c07d"), 0.30)
	_add_wall_beacon("Beacon_SumpSouth", Vector3(0.0, 0.22, 49.78), 0.0, Color("#c5964d"), 0.42)
	_add_wall_beacon("Beacon_SumpWest", Vector3(-17.78, 0.08, 39.0), -90.0, Color("#b7c07d"), 0.30)
	_add_wall_beacon("Beacon_ArchiveWest", Vector3(-51.78, 1.25, 35.0), -90.0, Color("#c5964d"), 0.28)

func _add_damp_patch(label: String, world_pos: Vector3, footprint: Vector2, rotation_deg: float, wet: bool = false) -> void:
	var patch := MeshInstance3D.new()
	patch.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.008
	mesh.material = wet_floor_material if wet else damp_material
	patch.mesh = mesh
	patch.position = world_pos
	patch.scale = Vector3(footprint.x, 1.0, footprint.y)
	patch.rotation_degrees.y = rotation_deg
	add_child(patch)

func _add_missing_ceiling_tile(label: String, world_pos: Vector3, rotation_deg: float) -> void:
	var recess := MeshInstance3D.new()
	recess.name = label
	var recess_mesh := BoxMesh.new()
	recess_mesh.size = Vector3(1.12, 0.025, 1.12)
	recess_mesh.material = void_material
	recess.mesh = recess_mesh
	recess.position = Vector3(world_pos.x, world_pos.y - 0.027, world_pos.z)
	recess.rotation_degrees.y = rotation_deg
	add_child(recess)

	var inner := MeshInstance3D.new()
	inner.name = label + "_Inner"
	var inner_mesh := BoxMesh.new()
	inner_mesh.size = Vector3(0.92, 0.035, 0.92)
	inner_mesh.material = vent_material
	inner.mesh = inner_mesh
	inner.position = Vector3(world_pos.x, world_pos.y - 0.045, world_pos.z)
	inner.rotation_degrees.y = rotation_deg
	add_child(inner)

	# Exposed T-grid rails around the opening sell the missing panel as part of the ceiling system.
	for rail_data in [
		{"size": Vector3(1.20, 0.025, 0.025), "offset": Vector3(0.0, -0.060, -0.585)},
		{"size": Vector3(1.20, 0.025, 0.025), "offset": Vector3(0.0, -0.060, 0.585)},
		{"size": Vector3(0.025, 0.025, 1.20), "offset": Vector3(-0.585, -0.060, 0.0)},
		{"size": Vector3(0.025, 0.025, 1.20), "offset": Vector3(0.585, -0.060, 0.0)}
	]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = rail_data["size"]
		rail_mesh.material = troffer_frame_material
		rail.mesh = rail_mesh
		var rotated_offset: Vector3 = rail_data["offset"].rotated(Vector3.UP, deg_to_rad(rotation_deg))
		rail.position = world_pos + rotated_offset
		rail.rotation_degrees.y = rotation_deg
		add_child(rail)

func _add_fallen_ceiling_tile(label: String, world_pos: Vector3, rotation_y: float, mirrored: bool) -> void:
	var debris := Node3D.new()
	debris.name = label
	debris.position = world_pos
	debris.rotation_degrees.y = rotation_y
	debris.scale.x = -1.0 if mirrored else 1.0
	add_child(debris)

	var shard_specs: Array[Dictionary] = [
		{
			"points": PackedVector2Array([Vector2(-0.55, -0.36), Vector2(0.06, -0.38), Vector2(0.30, -0.10), Vector2(0.18, 0.34), Vector2(-0.48, 0.31)]),
			"pos": Vector3(-0.16, 0.012, 0.0), "rot": Vector3(0.0, -4.0, -1.5)
		},
		{
			"points": PackedVector2Array([Vector2(-0.18, -0.24), Vector2(0.31, -0.31), Vector2(0.46, 0.05), Vector2(0.05, 0.29)]),
			"pos": Vector3(0.48, 0.018, 0.18), "rot": Vector3(1.0, 19.0, 2.0)
		},
		{
			"points": PackedVector2Array([Vector2(-0.19, -0.15), Vector2(0.22, -0.10), Vector2(0.04, 0.24)]),
			"pos": Vector3(0.34, 0.022, -0.38), "rot": Vector3(-1.5, -16.0, 1.0)
		},
		{
			"points": PackedVector2Array([Vector2(-0.12, -0.08), Vector2(0.11, -0.10), Vector2(0.15, 0.07), Vector2(-0.06, 0.13)]),
			"pos": Vector3(-0.62, 0.018, 0.34), "rot": Vector3(0.0, 31.0, 0.0)
		}
	]

	for index in range(shard_specs.size()):
		var spec: Dictionary = shard_specs[index]
		var shard := MeshInstance3D.new()
		shard.name = "Shard_%02d" % index
		shard.mesh = _make_broken_tile_mesh(spec["points"], 0.032 if index < 2 else 0.024)
		shard.position = spec["pos"]
		shard.rotation_degrees = spec["rot"]
		debris.add_child(shard)

	# A twisted section of metal ceiling grid makes the debris read as construction, not furniture.
	var grid_bar := MeshInstance3D.new()
	grid_bar.name = "BentGridBar"
	var grid_mesh := BoxMesh.new()
	grid_mesh.size = Vector3(1.18, 0.018, 0.025)
	grid_mesh.material = troffer_frame_material
	grid_bar.mesh = grid_mesh
	grid_bar.position = Vector3(0.12, 0.035, -0.50)
	grid_bar.rotation_degrees = Vector3(0.0, -11.0, 2.5)
	debris.add_child(grid_bar)

func _make_broken_tile_mesh(points: PackedVector2Array, thickness: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 3:
		return mesh

	var half_t := thickness * 0.5
	var face_tool := SurfaceTool.new()
	face_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	face_tool.set_material(tile_face_material)
	for i in range(1, points.size() - 1):
		for point_index in [0, i + 1, i]:
			var point: Vector2 = points[point_index]
			face_tool.set_normal(Vector3.UP)
			face_tool.set_uv(Vector2(point.x + 0.6, point.y + 0.45))
			face_tool.add_vertex(Vector3(point.x, half_t, point.y))
	face_tool.commit(mesh)

	var core_tool := SurfaceTool.new()
	core_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	core_tool.set_material(tile_core_material)
	for i in range(1, points.size() - 1):
		for point_index in [0, i, i + 1]:
			var point: Vector2 = points[point_index]
			core_tool.set_normal(Vector3.DOWN)
			core_tool.add_vertex(Vector3(point.x, -half_t, point.y))
	for i in range(points.size()):
		var next_i := (i + 1) % points.size()
		var point_a := points[i]
		var point_b := points[next_i]
		var edge := Vector3(point_b.x - point_a.x, 0.0, point_b.y - point_a.y)
		var side_normal := Vector3(edge.z, 0.0, -edge.x).normalized()
		var top_a := Vector3(point_a.x, half_t, point_a.y)
		var top_b := Vector3(point_b.x, half_t, point_b.y)
		var bottom_a := Vector3(point_a.x, -half_t, point_a.y)
		var bottom_b := Vector3(point_b.x, -half_t, point_b.y)
		for vertex in [top_a, top_b, bottom_b, top_a, bottom_b, bottom_a]:
			core_tool.set_normal(side_normal)
			core_tool.add_vertex(vertex)
	core_tool.commit(mesh)
	return mesh

func _add_hanging_cable(label: String, start_pos: Vector3, end_pos: Vector3, radius: float) -> void:
	var cable_delta := end_pos - start_pos
	var cable_length := cable_delta.length()
	if cable_length < 0.02:
		return
	var cable := MeshInstance3D.new()
	cable.name = label
	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = radius
	cable_mesh.bottom_radius = radius
	cable_mesh.height = cable_length
	cable_mesh.material = cable_material
	cable.mesh = cable_mesh
	cable.position = (start_pos + end_pos) * 0.5
	add_child(cable)
	var cable_dir := cable_delta.normalized()
	var cable_up := Vector3.UP
	if absf(cable_dir.dot(cable_up)) > 0.99:
		cable_up = Vector3.RIGHT
	cable.look_at(cable.position + cable_dir, cable_up)
	cable.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

func _add_wall_beacon(label: String, world_pos: Vector3, rotation_y: float, color: Color, energy: float) -> void:
	var beacon := Node3D.new()
	beacon.name = label
	beacon.position = world_pos
	beacon.rotation_degrees.y = rotation_y
	add_child(beacon)

	var housing := MeshInstance3D.new()
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(0.24, 0.34, 0.10)
	housing_mesh.material = vent_material
	housing.mesh = housing_mesh
	beacon.add_child(housing)

	var lens_material := StandardMaterial3D.new()
	lens_material.albedo_color = color
	lens_material.emission_enabled = true
	lens_material.emission = color
	lens_material.emission_energy_multiplier = 1.8
	lens_material.roughness = 0.62
	var lens := MeshInstance3D.new()
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.15, 0.22, 0.025)
	lens_mesh.material = lens_material
	lens.mesh = lens_mesh
	lens.position.z = -0.062
	beacon.add_child(lens)

	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = energy
	glow.omni_range = 4.8
	glow.omni_attenuation = 1.55
	glow.shadow_enabled = false
	glow.position.z = -0.18
	beacon.add_child(glow)

func _add_wall_segment(label: String, start_xz: Vector2, end_xz: Vector2, height: float = CEILING_H, y_offset: float = 0.0) -> void:
	var delta := end_xz - start_xz
	var length := delta.length()
	if length < 0.05:
		return
	var center_xz := (start_xz + end_xz) * 0.5
	var angle := delta.angle()

	var wall := MeshInstance3D.new()
	wall.name = label
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(length, height, WALL_THICKNESS)
	wall_box.material = wallpaper_material
	wall.mesh = wall_box
	wall.position = Vector3(center_xz.x, y_offset + height * 0.5, center_xz.y)
	wall.rotation.y = -angle
	add_child(wall)

	var body := StaticBody3D.new()
	body.name = label + "_Col"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, height, WALL_THICKNESS)
	col.shape = shape
	col.position = Vector3(center_xz.x, y_offset + height * 0.5, center_xz.y)
	col.rotation.y = -angle
	body.add_child(col)
	add_child(body)

	# Baseboards
	var base_h := 0.14
	var base_t := 0.025
	for side in [-1.0, 1.0]:
		var bb := MeshInstance3D.new()
		var bb_mesh := BoxMesh.new()
		bb_mesh.size = Vector3(length, base_h, base_t)
		bb_mesh.material = trim_material
		bb.mesh = bb_mesh
		var local_offset := Vector3(0.0, base_h * 0.5, side * (WALL_THICKNESS * 0.5 + base_t * 0.5))
		var world_offset := local_offset.rotated(Vector3.UP, -angle)
		bb.position = Vector3(center_xz.x, y_offset, center_xz.y) + world_offset
		bb.rotation.y = -angle
		add_child(bb)

	# Chair rails (for full height walls)
	if height >= 1.6:
		var rail_h := 0.07
		var rail_t := 0.02
		var rail_y := 0.85
		for side in [-1.0, 1.0]:
			var cr := MeshInstance3D.new()
			var cr_mesh := BoxMesh.new()
			cr_mesh.size = Vector3(length, rail_h, rail_t)
			cr_mesh.material = trim_material
			cr.mesh = cr_mesh
			var local_offset := Vector3(0.0, rail_y, side * (WALL_THICKNESS * 0.5 + rail_t * 0.5))
			var world_offset := local_offset.rotated(Vector3.UP, -angle)
			cr.position = Vector3(center_xz.x, y_offset, center_xz.y) + world_offset
			cr.rotation.y = -angle
			add_child(cr)

func _add_half_wall(label: String, start_xz: Vector2, end_xz: Vector2, height: float = 1.10, y_offset: float = 0.0) -> void:
	var delta := end_xz - start_xz
	var length := delta.length()
	if length < 0.05:
		return
	var center_xz := (start_xz + end_xz) * 0.5
	var angle := delta.angle()
	var t := 0.28

	var wall := MeshInstance3D.new()
	wall.name = label
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(length, height, t)
	wall_box.material = wallpaper_material
	wall.mesh = wall_box
	wall.position = Vector3(center_xz.x, y_offset + height * 0.5, center_xz.y)
	wall.rotation.y = -angle
	add_child(wall)

	var body := StaticBody3D.new()
	body.name = label + "_Col"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, height, t)
	col.shape = shape
	col.position = Vector3(center_xz.x, y_offset + height * 0.5, center_xz.y)
	col.rotation.y = -angle
	body.add_child(col)
	add_child(body)

	# Polished dark wood cap rail
	var cap := MeshInstance3D.new()
	var cap_box := BoxMesh.new()
	var cap_t := t + 0.08
	var cap_h := 0.04
	cap_box.size = Vector3(length + 0.04, cap_h, cap_t)
	cap_box.material = cap_material
	cap.mesh = cap_box
	cap.position = Vector3(center_xz.x, y_offset + height + cap_h * 0.5, center_xz.y)
	cap.rotation.y = -angle
	add_child(cap)

	# Baseboards
	var base_h := 0.14
	var base_t := 0.025
	for side in [-1.0, 1.0]:
		var bb := MeshInstance3D.new()
		var bb_mesh := BoxMesh.new()
		bb_mesh.size = Vector3(length, base_h, base_t)
		bb_mesh.material = trim_material
		bb.mesh = bb_mesh
		var local_offset := Vector3(0.0, base_h * 0.5, side * (t * 0.5 + base_t * 0.5))
		var world_offset := local_offset.rotated(Vector3.UP, -angle)
		bb.position = Vector3(center_xz.x, y_offset, center_xz.y) + world_offset
		bb.rotation.y = -angle
		add_child(bb)

func _add_column(label: String, center_xz: Vector2, footprint: Vector2 = Vector2(1.2, 1.2), height: float = CEILING_H, y_offset: float = 0.0) -> void:
	var col := MeshInstance3D.new()
	col.name = label
	var box := BoxMesh.new()
	box.size = Vector3(footprint.x, height, footprint.y)
	box.material = wallpaper_material
	col.mesh = box
	col.position = Vector3(center_xz.x, y_offset + height * 0.5, center_xz.y)
	add_child(col)

	var body := StaticBody3D.new()
	body.name = label + "_Col"
	var col_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(footprint.x, height, footprint.y)
	col_shape.shape = shape
	col_shape.position = Vector3(center_xz.x, y_offset + height * 0.5, center_xz.y)
	body.add_child(col_shape)
	add_child(body)

	# Baseboard wrapping 4 sides
	var base_h := 0.14
	var base_t := 0.025
	for side in [-1.0, 1.0]:
		var bbx := MeshInstance3D.new()
		var mx := BoxMesh.new()
		mx.size = Vector3(footprint.x + base_t * 2.0, base_h, base_t)
		mx.material = trim_material
		bbx.mesh = mx
		bbx.position = Vector3(center_xz.x, y_offset + base_h * 0.5, center_xz.y + side * (footprint.y * 0.5 + base_t * 0.5))
		add_child(bbx)

		var bbz := MeshInstance3D.new()
		var mz := BoxMesh.new()
		mz.size = Vector3(base_t, base_h, footprint.y)
		mz.material = trim_material
		bbz.mesh = mz
		bbz.position = Vector3(center_xz.x + side * (footprint.x * 0.5 + base_t * 0.5), y_offset + base_h * 0.5, center_xz.y)
		add_child(bbz)

	# Chair rail wrapping 4 sides
	if height >= 1.6:
		var rail_h := 0.07
		var rail_t := 0.02
		var rail_y := 0.85
		for side in [-1.0, 1.0]:
			var crx := MeshInstance3D.new()
			var mx := BoxMesh.new()
			mx.size = Vector3(footprint.x + rail_t * 2.0, rail_h, rail_t)
			mx.material = trim_material
			crx.mesh = mx
			crx.position = Vector3(center_xz.x, y_offset + rail_y, center_xz.y + side * (footprint.y * 0.5 + rail_t * 0.5))
			add_child(crx)

			var crz := MeshInstance3D.new()
			var mz := BoxMesh.new()
			mz.size = Vector3(rail_t, rail_h, footprint.y)
			mz.material = trim_material
			crz.mesh = mz
			crz.position = Vector3(center_xz.x + side * (footprint.x * 0.5 + rail_t * 0.5), y_offset + rail_y, center_xz.y)
			add_child(crz)

func _add_soffit(label: String, start_xz: Vector2, end_xz: Vector2, drop: float = 0.50, y_top: float = CEILING_H) -> void:
	var delta := end_xz - start_xz
	var length := delta.length()
	if length < 0.05:
		return
	var center_xz := (start_xz + end_xz) * 0.5
	var angle := delta.angle()
	var width := 0.35

	var soffit := MeshInstance3D.new()
	soffit.name = label
	var box := BoxMesh.new()
	box.size = Vector3(length, drop, width)
	box.material = soffit_material
	soffit.mesh = box
	soffit.position = Vector3(center_xz.x, y_top - drop * 0.5, center_xz.y)
	soffit.rotation.y = -angle
	add_child(soffit)

	var body := StaticBody3D.new()
	body.name = label + "_Col"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, drop, width)
	col.shape = shape
	col.position = Vector3(center_xz.x, y_top - drop * 0.5, center_xz.y)
	col.rotation.y = -angle
	body.add_child(col)
	add_child(body)

func _add_crawlspace_ceiling(label: String, min_xz: Vector2, max_xz: Vector2, height: float = 1.10) -> void:
	var size_x: float = absf(max_xz.x - min_xz.x)
	var size_z: float = absf(max_xz.y - min_xz.y)
	var center_x: float = (min_xz.x + max_xz.x) * 0.5
	var center_z: float = (min_xz.y + max_xz.y) * 0.5
	var thickness := 0.20

	var slab := MeshInstance3D.new()
	slab.name = label
	var box := BoxMesh.new()
	box.size = Vector3(size_x, thickness, size_z)
	box.material = ceiling_material
	slab.mesh = box
	slab.position = Vector3(center_x, height + thickness * 0.5, center_z)
	add_child(slab)

	var body := StaticBody3D.new()
	body.name = label + "_Col"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_x, thickness, size_z)
	col.shape = shape
	col.position = Vector3(center_x, height + thickness * 0.5, center_z)
	body.add_child(col)
	add_child(body)

func _add_pipe(label: String, start_pos: Vector3, end_pos: Vector3, radius: float = 0.045) -> void:
	var delta := end_pos - start_pos
	var length := delta.length()
	if length < 0.05:
		return
	var center := (start_pos + end_pos) * 0.5

	var pipe := MeshInstance3D.new()
	pipe.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.material = pipe_material
	pipe.mesh = mesh
	pipe.position = center

	add_child(pipe)
	var dir := delta.normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	pipe.look_at(pipe.position + dir, up)
	pipe.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

func _add_retaining_edge(label: String, start_xz: Vector2, end_xz: Vector2, y_bottom: float, y_top: float) -> void:
	var delta := end_xz - start_xz
	var length := delta.length()
	if length < 0.05:
		return
	var center_xz := (start_xz + end_xz) * 0.5
	var angle := delta.angle()
	var height: float = y_top - y_bottom
	var thickness := 0.28

	var wall := MeshInstance3D.new()
	wall.name = label
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(length, height, thickness)
	wall_box.material = wallpaper_material
	wall.mesh = wall_box
	wall.position = Vector3(center_xz.x, y_bottom + height * 0.5, center_xz.y)
	wall.rotation.y = -angle
	add_child(wall)

	var body := StaticBody3D.new()
	body.name = label + "_Col"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, height, thickness)
	col.shape = shape
	col.position = Vector3(center_xz.x, y_bottom + height * 0.5, center_xz.y)
	col.rotation.y = -angle
	body.add_child(col)
	add_child(body)

func _add_vent_grill(world_pos: Vector3, size: Vector2 = Vector2(1.2, 0.6), rotated: bool = false) -> void:
	var l := size.y if rotated else size.x
	var w := size.x if rotated else size.y

	var vent := MeshInstance3D.new()
	var vent_box := BoxMesh.new()
	vent_box.size = Vector3(l, 0.012, w)
	vent_box.material = vent_material
	vent.mesh = vent_box
	vent.position = world_pos
	add_child(vent)

	var inner := MeshInstance3D.new()
	var inner_box := BoxMesh.new()
	inner_box.size = Vector3(l - 0.08, 0.016, w - 0.08)
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color("#0b0d0a")
	inner_mat.roughness = 0.9
	inner.mesh = inner_box
	inner.material_override = inner_mat
	inner.position = world_pos
	add_child(inner)

func _add_outlet_on_wall(world_pos: Vector3, rotation_y: float) -> void:
	var outlet := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.13, 0.015)
	box.material = outlet_material
	outlet.mesh = box
	outlet.position = world_pos
	outlet.rotation.y = rotation_y
	add_child(outlet)

func _build_troffer_lighting() -> void:
	var troffer_configs: Array[Dictionary] = [
		# --- 1. Central Lobby (X: [-12, 12], Z: [-12, 12]) ---
		{"pos": Vector2(0.0, 3.5), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(0.0, -2.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(0.0, -8.0), "rot": false, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(5.0, 3.5), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(5.0, -2.0), "rot": false, "type": FixtureType.SLOW_PULSE, "y": CEILING_H},
		{"pos": Vector2(5.0, -8.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-7.0, 2.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-7.0, -3.0), "rot": false, "type": FixtureType.DEAD, "y": CEILING_H},
		{"pos": Vector2(10.0, 0.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(10.0, -6.0), "rot": false, "type": FixtureType.DYING, "y": CEILING_H},

		# --- 2. North Corridor & Anomalous Stagger (X: [-24, 20], Z: [-50, -14]) ---
		{"pos": Vector2(0.0, -18.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-12.0, -18.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},
		{"pos": Vector2(12.0, -18.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(16.0, -23.5), "rot": false, "type": FixtureType.STUTTER, "y": CEILING_H}, # Crawlspace entrance
		{"pos": Vector2(-14.0, -26.0), "rot": false, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(0.0, -28.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(12.0, -28.0), "rot": true, "type": FixtureType.DYING, "y": CEILING_H},
		{"pos": Vector2(-6.0, -36.0), "rot": true, "type": FixtureType.SLOW_PULSE, "y": CEILING_H},
		{"pos": Vector2(10.0, -36.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},
		{"pos": Vector2(-16.0, -42.0), "rot": false, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(-4.0, -48.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(8.0, -48.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H}, # North blind alcove
		{"pos": Vector2(-16.0, -49.0), "rot": false, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H}, # Formerly pitch black dead-end pocket!

		# --- 3. North-East Crawlspace Ducts (Y = 1.10m low-profile fixtures!) ---
		{"pos": Vector2(24.0, -23.5), "rot": true, "type": FixtureType.DYING, "y": 1.10},
		{"pos": Vector2(34.0, -23.5), "rot": true, "type": FixtureType.STUTTER, "y": 1.10},
		{"pos": Vector2(44.0, -23.5), "rot": false, "type": FixtureType.DEAD, "y": 1.10},
		{"pos": Vector2(44.0, -34.0), "rot": false, "type": FixtureType.DYING, "y": 1.10},
		{"pos": Vector2(33.0, -30.0), "rot": false, "type": FixtureType.FAINT_EMERGENCY, "y": 1.10}, # Low crawlspace alcove
		{"pos": Vector2(44.0, -43.5), "rot": true, "type": FixtureType.STUTTER, "y": 1.10},
		{"pos": Vector2(32.0, -43.5), "rot": true, "type": FixtureType.DYING, "y": 1.10},
		{"pos": Vector2(22.0, -43.5), "rot": true, "type": FixtureType.NORMAL, "y": 1.10},

		# --- 4. West Pillar Forest (X: [-50, -20], Z: [-22, 22]) ---
		{"pos": Vector2(-23.0, -15.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-35.0, -15.0), "rot": false, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},
		{"pos": Vector2(-46.0, -15.0), "rot": false, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(-29.0, -9.0), "rot": true, "type": FixtureType.SLOW_PULSE, "y": CEILING_H},
		{"pos": Vector2(-41.0, -9.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-23.0, -3.0), "rot": false, "type": FixtureType.DEAD, "y": CEILING_H},
		{"pos": Vector2(-35.0, -3.0), "rot": false, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(-46.0, -3.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-29.0, 3.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-41.0, 3.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},
		{"pos": Vector2(-23.0, 9.0), "rot": false, "type": FixtureType.DYING, "y": CEILING_H},
		{"pos": Vector2(-35.0, 9.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-46.0, 9.0), "rot": false, "type": FixtureType.DEAD, "y": CEILING_H},
		{"pos": Vector2(-29.0, 15.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-41.0, 15.0), "rot": true, "type": FixtureType.STUTTER, "y": CEILING_H},

		# --- 5. South Sunken Sump Chamber (X: [-18, 18], Z: [22, 50]) ---
		{"pos": Vector2(0.0, 18.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(0.0, 27.0), "rot": false, "type": FixtureType.DYING, "y": CEILING_H},
		{"pos": Vector2(-10.0, 32.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},
		{"pos": Vector2(10.0, 32.0), "rot": true, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(0.0, 38.0), "rot": false, "type": FixtureType.SLOW_PULSE, "y": CEILING_H},
		{"pos": Vector2(-10.0, 44.0), "rot": true, "type": FixtureType.DYING, "y": CEILING_H},
		{"pos": Vector2(10.0, 44.0), "rot": true, "type": FixtureType.DEAD, "y": CEILING_H},
		{"pos": Vector2(0.0, 47.0), "rot": false, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},

		# --- 6. South-East Tilted Alcoves & Hallway to Nowhere (X: [18, 50], Z: [16, 50]) ---
		{"pos": Vector2(24.0, 20.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(32.0, 24.0), "rot": true, "type": FixtureType.DYING, "y": CEILING_H},
		{"pos": Vector2(26.0, 30.0), "rot": false, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(36.0, 32.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},
		# Hallway to Nowhere: gradual fade with faint emergency guidance before final darkness
		{"pos": Vector2(30.0, 38.0), "rot": true, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(36.0, 38.0), "rot": true, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(42.0, 38.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H},
		{"pos": Vector2(48.0, 38.0), "rot": true, "type": FixtureType.DEAD, "y": CEILING_H},

		# --- 7. South-West Dead Archive & Storage (X: [-50, -20], Z: [22, 50]) ---
		{"pos": Vector2(-30.0, 26.0), "rot": false, "type": FixtureType.NORMAL, "y": CEILING_H},
		{"pos": Vector2(-42.0, 28.0), "rot": true, "type": FixtureType.DEAD, "y": CEILING_H},
		{"pos": Vector2(-34.0, 34.0), "rot": false, "type": FixtureType.SLOW_PULSE, "y": CEILING_H},
		{"pos": Vector2(-44.0, 38.0), "rot": true, "type": FixtureType.STUTTER, "y": CEILING_H},
		{"pos": Vector2(-28.0, 44.0), "rot": false, "type": FixtureType.DYING, "y": CEILING_H},
		{"pos": Vector2(-42.0, 47.0), "rot": true, "type": FixtureType.FAINT_EMERGENCY, "y": CEILING_H}
	]

	for i in range(troffer_configs.size()):
		var item: Dictionary = troffer_configs[i]
		var p: Vector2 = item["pos"]
		var rot: bool = item["rot"]
		var type: FixtureType = item["type"]
		var y_val: float = item.get("y", CEILING_H)
		_add_troffer_fixture(p, 2.2, 0.65, rot, type, float(i), y_val)

func _add_troffer_fixture(pos_2d: Vector2, length: float, width: float, rotated: bool, type: FixtureType, index: float, y_pos: float = CEILING_H) -> void:
	var l := width if rotated else length
	var w := length if rotated else width

	# Metal rim frame flush with ceiling
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(l, 0.02, w)
	frame_mesh.material = troffer_frame_material
	frame.mesh = frame_mesh
	frame.position = Vector3(pos_2d.x, y_pos - 0.005, pos_2d.y)
	add_child(frame)

	# Emissive diffuser panel
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(l - 0.08, 0.025, w - 0.08)

	var p_mat: StandardMaterial3D
	if type == FixtureType.DEAD:
		p_mat = troffer_panel_dead_material.duplicate() as StandardMaterial3D
	elif type == FixtureType.DYING:
		p_mat = troffer_panel_dying_material.duplicate() as StandardMaterial3D
	elif type == FixtureType.FAINT_EMERGENCY:
		p_mat = troffer_panel_faint_material.duplicate() as StandardMaterial3D
	else:
		p_mat = troffer_panel_material.duplicate() as StandardMaterial3D

	panel_mesh.material = p_mat
	panel.mesh = panel_mesh
	panel.position = Vector3(pos_2d.x, y_pos - 0.012, pos_2d.y)
	add_child(panel)

	var data := FixtureData.new()
	data.type = type
	data.panel = panel
	data.seed_offset = index * 4.31

	# Tube End Oxidized Electrode Rings (authentic failure silhouettes)
	var has_filaments := (type == FixtureType.DEAD or type == FixtureType.DYING or type == FixtureType.FAINT_EMERGENCY)
	if has_filaments:
		var half_span := (length * 0.5) - 0.12
		for end_sign in [-1.0, 1.0]:
			for tube_side in [-0.12, 0.12]:
				var fil_mesh := MeshInstance3D.new()
				var fil_box := BoxMesh.new()
				if not rotated:
					fil_box.size = Vector3(0.055, 0.012, 0.020)
					fil_mesh.position = Vector3(pos_2d.x + end_sign * half_span, y_pos - 0.018, pos_2d.y + tube_side)
				else:
					fil_box.size = Vector3(0.020, 0.012, 0.055)
					fil_mesh.position = Vector3(pos_2d.x + tube_side, y_pos - 0.018, pos_2d.y + end_sign * half_span)
				fil_box.material = filament_glow_material
				fil_mesh.mesh = fil_box
				add_child(fil_mesh)

	# If DEAD fixture, leave completely unlit (no spotlights or floating pinpoint lights)
	if type == FixtureType.DEAD:
		data.base_emission = 0.0
		data.base_spot_energy = 0.0
		data.base_fill_energy = 0.0
		fixtures.append(data)
		return

	# Primary downward Spotlight
	var spot := SpotLight3D.new()
	spot.position = Vector3(pos_2d.x, y_pos - 0.05, pos_2d.y)
	spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	var spot_color := Color("#ebf0cb")
	var base_spot_e := 1.65
	var base_fill_e := 0.44
	var base_em := 2.0
	var spot_atten := 1.45
	var spot_ang := 76.0
	var shadow_bl := 2.6

	if type == FixtureType.DYING:
		# Authentic phosphor degradation: Jaundiced Pale Ivory/Titanium
		spot_color = Color("#d4cca2")
		base_spot_e = 0.95
		base_fill_e = 0.32
		base_em = 0.95
		spot_atten = 1.22
		spot_ang = 80.0
		shadow_bl = 2.8
	elif type == FixtureType.FAINT_EMERGENCY:
		# Authentic low-pressure ballast glow: Sickly Desaturated Green-White
		spot_color = Color("#cad4b2")
		base_spot_e = 0.80
		base_fill_e = 0.26
		base_em = 0.70
		spot_atten = 1.25
		spot_ang = 82.0
		shadow_bl = 2.8
	elif y_pos < 1.5: # Crawlspace low troffers (Dim Mercury-Vapor Gray)
		base_spot_e = 0.85
		base_fill_e = 0.20
		spot_color = Color("#b4bcaf")
		spot_atten = 1.50
		spot_ang = 76.0
		shadow_bl = 2.6

	spot.light_color = spot_color
	spot.light_energy = base_spot_e
	spot.spot_range = 9.0 if y_pos >= 2.0 else 4.5
	spot.spot_angle = spot_ang
	spot.spot_attenuation = spot_atten
	spot.shadow_enabled = true
	spot.shadow_bias = 0.040
	spot.shadow_blur = shadow_bl
	spot.light_volumetric_fog_energy = 2.2 if y_pos >= 2.0 else 1.2
	add_child(spot)

	# Secondary broad soft ceiling fill OmniLight
	var fill := OmniLight3D.new()
	fill.position = Vector3(pos_2d.x, y_pos - (0.30 if y_pos >= 2.0 else 0.12), pos_2d.y)
	fill.light_color = spot_color
	fill.light_energy = base_fill_e
	fill.omni_range = 6.4 if y_pos >= 2.0 else 3.2
	fill.omni_attenuation = 1.20
	fill.shadow_enabled = false
	add_child(fill)

	data.spot_light = spot
	data.fill_light = fill
	data.base_spot_energy = base_spot_e
	data.base_fill_energy = base_fill_e
	data.base_emission = base_em
	fixtures.append(data)

func _build_fuel_pickups() -> void:
	var pickup_spawns: Array[Dictionary] = [
		# 1. On the reception counter cap rail (early discovery)
		{"pos": Vector3(-2.0, 1.14, 2.0), "grounded": true, "label": "ReceptionCounter"},
		# 2. Monolith Pillar Grid (tucked behind column at cx=-38, cz=6)
		{"pos": Vector3(-38.0, 0.12, 7.1), "grounded": false, "label": "PillarForest"},
		# 3. Midway inside the low 1.10m maintenance crawlspace
		{"pos": Vector3(33.0, 0.12, -29.0), "grounded": true, "label": "CrawlspaceAlcove"},
		# 4. In the Sunken Sump Chamber near the floor retaining wall
		{"pos": Vector3(-13.0, -1.2 + 0.12, 26.5), "grounded": false, "label": "SumpChamber"},
		# 5. At the blind Z-turn in the North corridor
		{"pos": Vector3(-7.5, 0.12, -34.0), "grounded": false, "label": "NorthZTurn"},
		# 6. In the alcove leading to the Hallway to Nowhere
		{"pos": Vector3(26.0, 0.12, 32.0), "grounded": false, "label": "NowhereAlcove"},
		# 7. In the West corridor junction
		{"pos": Vector3(-20.5, 0.12, 2.0), "grounded": false, "label": "WestJunction"},
		# 8. At the South dead-end hallway in SW Archive
		{"pos": Vector3(-44.0, 0.12, 45.0), "grounded": false, "label": "SWArchiveDeadEnd"},
		# 9. Deep North blind dead-end pocket
		{"pos": Vector3(-16.0, 0.12, -49.5), "grounded": false, "label": "NorthPocketDeadEnd"},
		# 10. East corridor junction near crawlspace entry
		{"pos": Vector3(18.0, 0.12, -18.5), "grounded": false, "label": "EastCorridor"}
	]

	for data in pickup_spawns:
		_spawn_fuel_can(data)

func _spawn_fuel_can(data: Dictionary) -> void:
	var can_area := Area3D.new()
	can_area.name = "FuelCan_" + data["label"]
	can_area.position = data["pos"]
	add_child(can_area)

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	col.shape = sphere
	can_area.add_child(col)

	var visual := Node3D.new()
	visual.name = "Visual"
	can_area.add_child(visual)

	# 1. Main tin body: 14cm height, 7cm width, 3.5cm depth
	var body_mesh := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.070, 0.110, 0.035)
	body_box.material = fuel_can_body_mat
	body_mesh.mesh = body_box
	body_mesh.position = Vector3(0.0, 0.055, 0.0)
	visual.add_child(body_mesh)

	# 2. Dark vintage graphic band / label
	var band_mesh := MeshInstance3D.new()
	var band_box := BoxMesh.new()
	band_box.size = Vector3(0.071, 0.046, 0.036)
	band_box.material = fuel_can_band_mat
	band_mesh.mesh = band_box
	band_mesh.position = Vector3(0.0, 0.055, 0.0)
	visual.add_child(band_mesh)

	# 3. Stamped silver top rim & cap
	var top_rim := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(0.068, 0.008, 0.034)
	top_box.material = fuel_can_silver_mat
	top_rim.mesh = top_box
	top_rim.position = Vector3(0.0, 0.114, 0.0)
	visual.add_child(top_rim)

	# 4. Stamped silver bottom rim
	var btm_rim := MeshInstance3D.new()
	var btm_box := BoxMesh.new()
	btm_box.size = Vector3(0.068, 0.008, 0.034)
	btm_box.material = fuel_can_silver_mat
	btm_rim.mesh = btm_box
	btm_rim.position = Vector3(0.0, 0.004, 0.0)
	visual.add_child(btm_rim)

	# 5. Silver neck spout collar
	var collar_mesh := MeshInstance3D.new()
	var collar_cyl := CylinderMesh.new()
	collar_cyl.top_radius = 0.006
	collar_cyl.bottom_radius = 0.007
	collar_cyl.height = 0.012
	collar_cyl.material = fuel_can_silver_mat
	collar_mesh.mesh = collar_cyl
	collar_mesh.position = Vector3(0.014, 0.124, 0.0)
	visual.add_child(collar_mesh)

	# 6. Red angled dispenser nozzle spout
	var spout_mesh := MeshInstance3D.new()
	var spout_cyl := CylinderMesh.new()
	spout_cyl.top_radius = 0.0025
	spout_cyl.bottom_radius = 0.0042
	spout_cyl.height = 0.022
	spout_cyl.material = fuel_can_spout_mat
	spout_mesh.mesh = spout_cyl
	spout_mesh.position = Vector3(0.019, 0.138, 0.0)
	spout_mesh.rotation.z = deg_to_rad(-25.0)
	visual.add_child(spout_mesh)

	# 7. Warm ambient point highlight
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.position = Vector3(0.0, 0.08, 0.0)
	glow.light_color = Color("#ffb347")
	glow.light_energy = 0.45
	glow.omni_range = 1.8
	glow.omni_attenuation = 1.6
	glow.shadow_enabled = false
	can_area.add_child(glow)

	var can_entry := {
		"area": can_area,
		"visual": visual,
		"glow": glow,
		"base_y": data["pos"].y,
		"grounded": data["grounded"],
		"seed": randf() * 10.0,
		"collected": false
	}
	fuel_cans.append(can_entry)

	can_area.body_entered.connect(_on_fuel_can_entered.bind(can_entry))

func _on_fuel_can_entered(body: Node3D, item: Dictionary) -> void:
	if item["collected"]:
		return
	if body.is_in_group("player") or body == player:
		item["collected"] = true
		if player != null and player.has_method("add_fuel"):
			player.add_fuel(40.0)
		elif player != null and "lighter_fuel" in player:
			player.lighter_fuel = clampf(player.lighter_fuel + 40.0, 0.0, 100.0)

		_show_hud_toast("+40% LIGHTER FLUID")

		# Tactile collection bounce & vanish animation
		var can_area: Area3D = item["area"]
		var visual: Node3D = item["visual"]
		var glow: OmniLight3D = item["glow"]
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		if glow != null:
			tween.tween_property(glow, "light_energy", 2.2, 0.08)
			tween.tween_property(glow, "light_energy", 0.0, 0.20).set_delay(0.08)
		tween.chain().tween_callback(can_area.queue_free)

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://player.gd"))
	player.position = Vector3(1.2, 0.05, 3.2)
	player.rotation_degrees.y = 8.0
	add_child(player)

func _build_observer_presence() -> void:
	observer_markers = [
		Vector3(-16.0, 0.0, -50.7),
		Vector3(49.8, 0.0, 38.0),
		Vector3(-44.0, 0.0, 45.8),
		Vector3(-46.0, 0.0, -14.5),
		Vector3(12.0, -1.2, 47.0),
		Vector3(7.0, 0.0, -20.8),
		Vector3(-48.0, 0.0, 1.0),
		Vector3(17.0, 0.0, -18.5),
		Vector3(34.5, 0.0, 28.5)
	]

	observer = Node3D.new()
	observer.name = "DistantObserver"

	# A slightly stooped, asymmetrical human outline. Rounded low-poly forms catch only
	# fragments of the room light, while the coat hides enough anatomy to stay uncertain.
	var stance := Node3D.new()
	stance.name = "Stance"
	stance.rotation_degrees.z = -1.15
	observer.add_child(stance)

	var coat_mesh := CylinderMesh.new()
	coat_mesh.top_radius = 0.225
	coat_mesh.bottom_radius = 0.315
	coat_mesh.height = 1.08
	coat_mesh.radial_segments = 12
	_add_observer_part(stance, "Coat", coat_mesh, Vector3(-0.015, 0.83, 0.0), Vector3(0.0, 0.0, 0.8), Vector3(1.0, 1.0, 0.72))

	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.255
	torso_mesh.height = 1.12
	torso_mesh.radial_segments = 12
	torso_mesh.rings = 5
	_add_observer_part(stance, "Torso", torso_mesh, Vector3(0.0, 1.42, 0.0), Vector3(4.0, 0.0, -1.6), Vector3(0.94, 1.0, 0.64))

	var shoulder_mesh := CapsuleMesh.new()
	shoulder_mesh.radius = 0.105
	shoulder_mesh.height = 0.84
	shoulder_mesh.radial_segments = 12
	shoulder_mesh.rings = 4
	_add_observer_part(stance, "Shoulders", shoulder_mesh, Vector3(-0.01, 1.84, 0.0), Vector3(0.0, 0.0, 91.5), Vector3(1.0, 1.0, 0.75))

	var hood_mesh := SphereMesh.new()
	hood_mesh.radius = 0.215
	hood_mesh.height = 0.47
	hood_mesh.radial_segments = 14
	hood_mesh.rings = 7
	_add_observer_part(stance, "Hood", hood_mesh, Vector3(-0.035, 2.16, -0.018), Vector3(-7.0, 5.0, -2.5), Vector3(0.88, 1.0, 0.80))

	# Segmented limbs avoid the toy-like straight rods of the old figure. The unequal
	# angles are readable as a person at a glance but resist a clean mannequin silhouette.
	for side in [-1.0, 1.0]:
		var side_name := "L" if side < 0.0 else "R"
		var upper_arm_mesh := CylinderMesh.new()
		upper_arm_mesh.top_radius = 0.060
		upper_arm_mesh.bottom_radius = 0.072
		upper_arm_mesh.height = 0.64 if side < 0.0 else 0.61
		upper_arm_mesh.radial_segments = 10
		var upper_angle := -7.0 if side < 0.0 else 10.0
		_add_observer_part(stance, "UpperArm_" + side_name, upper_arm_mesh, Vector3(side * 0.30, 1.53 if side < 0.0 else 1.50, 0.005), Vector3(1.5, 0.0, side * upper_angle), Vector3(1.0, 1.0, 0.82))

		var forearm_mesh := CylinderMesh.new()
		forearm_mesh.top_radius = 0.045
		forearm_mesh.bottom_radius = 0.060
		forearm_mesh.height = 0.59
		forearm_mesh.radial_segments = 10
		var forearm_angle := 4.0 if side < 0.0 else -7.0
		_add_observer_part(stance, "Forearm_" + side_name, forearm_mesh, Vector3(side * 0.345, 0.96 if side < 0.0 else 0.94, 0.025), Vector3(-2.0, 0.0, side * forearm_angle), Vector3(1.0, 1.0, 0.78))

		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.080
		leg_mesh.bottom_radius = 0.062
		leg_mesh.height = 0.79
		leg_mesh.radial_segments = 10
		_add_observer_part(stance, "Leg_" + side_name, leg_mesh, Vector3(side * 0.105, 0.39, 0.0), Vector3(0.0, 0.0, side * -1.8), Vector3(1.0, 1.0, 0.84))

	observer.position = observer_markers[0]
	observer.visible = false
	observer_hide_timer = randf_range(18.0, 32.0)
	observer_relocation_timer = 0.0
	observer_sway_phase = randf_range(0.0, TAU)
	add_child(observer)
	_update_presence_shader()

func _add_observer_part(parent: Node3D, part_name: String, mesh: PrimitiveMesh, part_position: Vector3, part_rotation: Vector3 = Vector3.ZERO, part_scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	mesh.material = observer_material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = part_position
	part.rotation_degrees = part_rotation
	part.scale = part_scale
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(part)
	return part

func _update_observer_presence(delta: float) -> void:
	if observer == null or player == null:
		return

	if observer_hide_timer > 0.0:
		observer_hide_timer -= delta
		observer_presence = move_toward(observer_presence, 0.0, delta * 1.4)
		if observer_hide_timer <= 0.0:
			_place_observer_at_next_marker()
		_update_presence_shader()
		return

	var camera_node := player.get_node_or_null("Head/Camera3D") as Camera3D
	if camera_node == null or not observer.visible:
		return

	observer_relocation_timer -= delta
	var stance := observer.get_node_or_null("Stance") as Node3D
	if stance != null:
		# Barely-there posture drift is slow enough to be mistaken for visual noise.
		stance.rotation_degrees.z = -1.15 + sin(elapsed * 0.23 + observer_sway_phase) * 0.16

	var observer_focus := observer.global_position + Vector3(0.0, 1.38, 0.0)
	var to_observer := observer_focus - camera_node.global_position
	var distance := to_observer.length()
	if distance < 0.01:
		return

	var view_dot := (-camera_node.global_transform.basis.z).dot(to_observer / distance)
	var has_clear_sight := false
	if view_dot > 0.72 and distance > 16.0 and distance < 58.0:
		var query := PhysicsRayQueryParameters3D.create(camera_node.global_position, observer_focus)
		query.exclude = [player.get_rid()]
		has_clear_sight = get_world_3d().direct_space_state.intersect_ray(query).is_empty()

	var target_presence := 0.0
	if has_clear_sight:
		var angular_reveal := clampf((view_dot - 0.76) / 0.22, 0.0, 1.0)
		var distance_reveal := clampf(1.0 - absf(distance - 36.0) / 30.0, 0.28, 1.0)
		target_presence = angular_reveal * distance_reveal
		if view_dot > 0.91:
			observer_seen_time += delta * clampf((view_dot - 0.91) / 0.09, 0.15, 1.0)
		observer_exposure_time += delta * clampf((view_dot - 0.84) / 0.16, 0.0, 1.0)
		if view_dot > 0.992:
			observer_centered_time += delta
		else:
			observer_centered_time = move_toward(observer_centered_time, 0.0, delta * 1.8)
	else:
		observer_seen_time = move_toward(observer_seen_time, 0.0, delta * 1.2)
		observer_centered_time = move_toward(observer_centered_time, 0.0, delta * 2.0)

	observer_presence = move_toward(observer_presence, target_presence, delta * (0.48 if target_presence > observer_presence else 1.7))
	_update_presence_shader()

	# The figure retreats only after the player has truly centered it, or after a few
	# accumulated peripheral glimpses. There is no dramatic cue to confirm the sighting.
	if distance < 18.0 or observer_centered_time > 0.62 or observer_exposure_time > 2.8:
		_conceal_observer(randf_range(22.0, 42.0))
	elif observer_relocation_timer <= 0.0 and not has_clear_sight:
		_conceal_observer(randf_range(14.0, 30.0))
	elif observer_relocation_timer < -4.0:
		_conceal_observer(randf_range(18.0, 34.0))

func _conceal_observer(next_delay: float) -> void:
	observer.visible = false
	observer_seen_time = 0.0
	observer_centered_time = 0.0
	observer_exposure_time = 0.0
	observer_presence = 0.0
	observer_hide_timer = next_delay
	_update_presence_shader()

func _place_observer_at_next_marker() -> void:
	if observer_markers.is_empty():
		return
	var best_index := -1
	var best_score := INF
	var camera_node := player.get_node_or_null("Head/Camera3D") as Camera3D if player != null else null
	for offset in range(1, observer_markers.size() + 1):
		var candidate_index := (observer_marker_index + offset) % observer_markers.size()
		var candidate := observer_markers[candidate_index]
		if player == null:
			best_index = candidate_index
			break
		var distance := player.global_position.distance_to(candidate)
		if distance > 28.0 and distance < 52.0:
			var score := absf(distance - 37.0) + randf_range(0.0, 4.0)
			if camera_node != null:
				var focus := candidate + Vector3(0.0, 1.38, 0.0)
				var direction := focus - camera_node.global_position
				var view_dot := (-camera_node.global_transform.basis.z).dot(direction.normalized())
				var query := PhysicsRayQueryParameters3D.create(camera_node.global_position, focus)
				query.exclude = [player.get_rid()]
				var clear_sight := get_world_3d().direct_space_state.intersect_ray(query).is_empty()
				# Prefer a clear, peripheral placement instead of materializing dead-center.
				score += absf(view_dot - 0.78) * 7.0
				if not clear_sight:
					score += 7.5
			if score < best_score:
				best_score = score
				best_index = candidate_index
	if best_index >= 0:
		observer_marker_index = best_index
		observer.global_position = observer_markers[best_index]
		var look_target := Vector3(player.global_position.x, observer.global_position.y, player.global_position.z)
		if observer.global_position.distance_squared_to(look_target) > 0.01:
			observer.look_at(look_target, Vector3.UP)
		observer.visible = true
		observer_seen_time = 0.0
		observer_centered_time = 0.0
		observer_exposure_time = 0.0
		observer_presence = 0.0
		observer_sway_phase = randf_range(0.0, TAU)
		observer_relocation_timer = randf_range(7.0, 13.0)
		_update_presence_shader()
		return
	observer_hide_timer = randf_range(10.0, 18.0)

func _update_presence_shader() -> void:
	if observer_material != null:
		var alpha := 0.0
		if observer != null and observer.visible:
			alpha = 0.27 + observer_presence * 0.17
		observer_material.albedo_color = Color(0.008, 0.009, 0.006, alpha)
	if hud_atmosphere_material != null:
		# Kept below conscious notice: the screen no longer confirms what the player saw.
		hud_atmosphere_material.set_shader_parameter("presence", observer_presence * 0.06)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	# Subtle claustrophobic analog vignette overlay
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float vignette_intensity : hint_range(0.0, 2.5) = 1.25;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.62;
uniform float presence : hint_range(0.0, 1.0) = 0.0;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	float v = smoothstep(0.32, 0.76, dist * vignette_intensity);
	float grain = (hash(FRAGCOORD.xy + floor(TIME * 24.0)) - 0.5) * (0.018 + presence * 0.025);
	float scan = (sin(FRAGCOORD.y * 1.7 + TIME * 9.0) * 0.5 + 0.5) * presence * 0.004;
	float alpha = clamp(v * vignette_opacity + abs(grain) + scan, 0.0, 0.88);
	vec3 tint = mix(vec3(0.03, 0.03, 0.02), vec3(0.012, 0.018, 0.010), presence);
	COLOR = vec4(tint + max(grain, 0.0) * 0.12, alpha);
}
"""
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	vignette.material = shader_mat
	hud_atmosphere_material = shader_mat
	layer.add_child(vignette)

	# Atmospheric Status Card
	var card := ColorRect.new()
	card.position = Vector2(24.0, 22.0)
	card.size = Vector2(340.0, 138.0)
	card.color = Color(0.03, 0.03, 0.02, 0.82)
	layer.add_child(card)

	var title := Label.new()
	title.position = Vector2(16.0, 8.0)
	title.text = "CLICHE"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#e8d6a8"))
	card.add_child(title)

	var level := Label.new()
	level.position = Vector2(18.0, 40.0)
	level.text = "LEVEL 0   //   THE YELLOW COMPLEX"
	level.add_theme_font_size_override("font_size", 11)
	level.add_theme_color_override("font_color", Color("#a69260"))
	card.add_child(level)

	var hint := Label.new()
	hint.position = Vector2(18.0, 58.0)
	hint.text = "WASD MOVE   SHIFT SPRINT   CTRL CROUCH   SPACE JUMP   F LIGHTER"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color("#c6b47c"))
	card.add_child(hint)

	# Separator line
	var sep := ColorRect.new()
	sep.position = Vector2(16.0, 76.0)
	sep.size = Vector2(308.0, 1.0)
	sep.color = Color(0.35, 0.30, 0.18, 0.5)
	card.add_child(sep)

	# Lighter Fuel Section
	var lighter_lbl := Label.new()
	lighter_lbl.position = Vector2(18.0, 83.0)
	lighter_lbl.text = "LIGHTER FUEL"
	lighter_lbl.add_theme_font_size_override("font_size", 10)
	lighter_lbl.add_theme_color_override("font_color", Color("#a69260"))
	card.add_child(lighter_lbl)

	hud_status_label = Label.new()
	hud_status_label.position = Vector2(230.0, 83.0)
	hud_status_label.text = "READY"
	hud_status_label.add_theme_font_size_override("font_size", 10)
	hud_status_label.add_theme_color_override("font_color", Color("#8e7c54"))
	card.add_child(hud_status_label)

	var gauge_frame := ColorRect.new()
	gauge_frame.position = Vector2(18.0, 102.0)
	gauge_frame.size = Vector2(228.0, 12.0)
	gauge_frame.color = Color(0.12, 0.10, 0.07, 0.95)
	card.add_child(gauge_frame)

	hud_fuel_fill = ColorRect.new()
	hud_fuel_fill.position = Vector2(20.0, 104.0)
	hud_fuel_fill.size = Vector2(224.0, 8.0)
	hud_fuel_fill.color = Color("#d48822")
	card.add_child(hud_fuel_fill)

	for tick_pct in [0.25, 0.50, 0.75]:
		var tick := ColorRect.new()
		tick.position = Vector2(20.0 + 224.0 * tick_pct - 0.5, 102.0)
		tick.size = Vector2(1.0, 12.0)
		tick.color = Color(0.04, 0.04, 0.03, 0.8)
		card.add_child(tick)

	hud_fuel_label = Label.new()
	hud_fuel_label.position = Vector2(256.0, 99.0)
	hud_fuel_label.text = "100%"
	hud_fuel_label.add_theme_font_size_override("font_size", 12)
	hud_fuel_label.add_theme_color_override("font_color", Color("#e8d6a8"))
	card.add_child(hud_fuel_label)

	# Translucent Reticle
	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-4.0, -18.0)
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70, 0.45))
	layer.add_child(crosshair)

	# Atmospheric HUD Toast Banner for Fuel Refills
	hud_toast_container = Control.new()
	hud_toast_container.name = "ToastContainer"
	hud_toast_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_toast_container.position = Vector2(0.0, 48.0)
	hud_toast_container.modulate = Color(1.0, 1.0, 1.0, 0.0)
	layer.add_child(hud_toast_container)

	var toast_bg := ColorRect.new()
	toast_bg.size = Vector2(320.0, 42.0)
	toast_bg.position = Vector2(-160.0, 0.0)
	toast_bg.color = Color(0.04, 0.04, 0.03, 0.88)
	hud_toast_container.add_child(toast_bg)

	var toast_border := ColorRect.new()
	toast_border.size = Vector2(320.0, 1.0)
	toast_border.position = Vector2(-160.0, 41.0)
	toast_border.color = Color(0.85, 0.60, 0.20, 0.70)
	hud_toast_container.add_child(toast_border)

	hud_toast_label = Label.new()
	hud_toast_label.size = Vector2(320.0, 42.0)
	hud_toast_label.position = Vector2(-160.0, 0.0)
	hud_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_toast_label.text = "+40% LIGHTER FLUID"
	hud_toast_label.add_theme_font_size_override("font_size", 14)
	hud_toast_label.add_theme_color_override("font_color", Color("#ffd680"))
	hud_toast_container.add_child(hud_toast_label)

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

func _add_stepping_ledge(label: String, center: Vector3, size: Vector3, cap_wood: bool = true, add_collision: bool = true) -> void:
	# Navigable stepped platform (height 0.32m - 0.36m per tier)
	var ledge := MeshInstance3D.new()
	ledge.name = label
	var box := BoxMesh.new()
	box.size = size
	box.material = soffit_material
	ledge.mesh = box
	ledge.position = center
	add_child(ledge)

	# Carpet belongs on the horizontal tread only; wallpapered risers feel built into the room.
	if not cap_wood:
		var tread := MeshInstance3D.new()
		var tread_mesh := BoxMesh.new()
		tread_mesh.size = Vector3(size.x + 0.012, 0.018, size.z + 0.012)
		tread_mesh.material = floor_material
		tread.mesh = tread_mesh
		tread.position = Vector3(center.x, center.y + size.y * 0.5 + 0.009, center.z)
		add_child(tread)

	if add_collision:
		var body := StaticBody3D.new()
		body.name = label + "_Col"
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = center
		body.add_child(col)
		add_child(body)

	# Baseboard trim along the foot
	var base_h := 0.08
	var base_t := 0.02
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(size.x + base_t * 2.0, base_h, size.z + base_t * 2.0)
	b_mesh.material = trim_material
	var trim_inst := MeshInstance3D.new()
	trim_inst.mesh = b_mesh
	trim_inst.position = Vector3(center.x, center.y - size.y * 0.5 + base_h * 0.5, center.z)
	add_child(trim_inst)

	# Optional polished wood cap nosing edge
	if cap_wood:
		var cap_h := 0.025
		var c_mesh := BoxMesh.new()
		c_mesh.size = Vector3(size.x + 0.03, cap_h, size.z + 0.03)
		c_mesh.material = cap_material
		var cap_inst := MeshInstance3D.new()
		cap_inst.mesh = c_mesh
		cap_inst.position = Vector3(center.x, center.y + size.y * 0.5 + cap_h * 0.5, center.z)
		add_child(cap_inst)

func _add_invisible_stair_ramp(label: String, start_xz: Vector2, end_xz: Vector2, width: float, y_start: float, y_end: float) -> void:
	var start_pos := Vector3(start_xz.x, y_start, start_xz.y)
	var end_pos := Vector3(end_xz.x, y_end, end_xz.y)
	var delta := end_pos - start_pos
	var length := delta.length()
	if length < 0.05:
		return

	var center := (start_pos + end_pos) * 0.5
	var thickness := 0.16
	var forward := delta / length
	var h_dir := Vector3(forward.x, 0.0, forward.z).normalized()
	if h_dir.length_squared() < 0.001:
		h_dir = Vector3.FORWARD
	var right := Vector3.UP.cross(h_dir).normalized()
	var up := forward.cross(right).normalized()
	var ramp_basis := Basis(forward, up, -right)
	var xform := Transform3D(ramp_basis, center - up * (thickness * 0.45))

	var body := StaticBody3D.new()
	body.name = label + "_ColRamp"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, thickness, width)
	col.shape = shape
	col.transform = xform
	body.add_child(col)
	add_child(body)

func _add_doorway_threshold(label: String, center_xz: Vector2, width: float, depth: float, y_val: float = 0.0) -> void:
	var plate := MeshInstance3D.new()
	plate.name = label
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.015, depth)
	box.material = trim_material
	plate.mesh = box
	plate.position = Vector3(center_xz.x, y_val + 0.0075, center_xz.y)
	add_child(plate)
