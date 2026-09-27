extends CharacterBody3D
## Atmospheric First-Person Controller with Zippo Lighter System
## Built for deliberate, grounded movement, realistic human scale, and tactile lighter mechanics.

enum LighterState {
	UNEQUIPPED,
	EQUIPPING,
	LIT,
	UNEQUIPPING,
	OUT_OF_FUEL
}

enum SfxType {
	NONE,
	SNAP_OPEN,
	SNAP_CLOSE,
	FLINT_STRIKE,
	IGNITE_PUFF,
	REFILL_SLOSH
}

@export_group("Movement Speeds")
@export var walk_speed := 2.85
@export var sprint_speed := 5.10
@export var crouch_speed := 1.60
@export var jump_velocity := 4.2
@export var gravity := 18.0

@export_group("Kinematics & Friction")
@export var acceleration := 32.0
@export var deceleration := 52.0
@export var air_control := 0.25

@export_group("Look & Camera")
@export var mouse_sensitivity := 0.0020
@export var standing_height := 1.38
@export var crouch_height := 0.82
@export var crouch_transition_speed := 10.0

@export_group("Head Bob & Sway")
@export var bob_frequency_walk := 7.5
@export var bob_frequency_sprint := 10.5
@export var bob_frequency_crouch := 5.5
@export var bob_amplitude_vertical := 0.024
@export var bob_amplitude_horizontal := 0.016
@export var strafe_tilt_angle := 1.0 # degrees

@export_group("Lighter & Fuel")
@export var lighter_fuel := 100.0
@export var max_fuel := 100.0
@export var fuel_drain_rate := 1.18 # ~85 seconds continuous burn

var camera: Camera3D
var head: Node3D
var collision_shape: CollisionShape3D
var capsule_shape: CapsuleShape3D
var ceiling_ray: RayCast3D

var pitch := deg_to_rad(-2.5)
var target_roll := 0.0
var current_roll := 0.0

var step_cycle := 0.0
var idle_time := 0.0
var is_crouching := false
var current_cam_height := 1.38

var was_on_floor := true
var landing_dip := 0.0

# --- Lighter Viewmodel & State Variables ---
var lighter_state: LighterState = LighterState.UNEQUIPPED
var equip_progress := 0.0 # 0.0 (lowered offscreen) to 1.0 (raised in view)
var lid_progress := 0.0   # 0.0 (closed) to 1.0 (open -105 deg)
var flame_ignited := false
var spark_flash_timer := 0.0
var elapsed := 0.0

var did_snap_open := false
var did_strike_flint := false
var did_snap_close := false

# Viewmodel nodes
var viewmodel_root: Node3D
var lighter_root: Node3D
var lid_pivot: Node3D
var striker_wheel: Node3D
var flame_root: Node3D
var flame_outer_mesh: MeshInstance3D
var flame_inner_mesh: MeshInstance3D
var flame_base_mesh: MeshInstance3D
var flame_light: OmniLight3D

# Transform targets
const VM_RESTING_POS := Vector3(0.19, -0.14, -0.32)
const VM_UNEQUIPPED_POS := Vector3(0.19, -0.62, -0.28)
const VM_BASE_ROT := Vector3(0.12, -0.24, -0.06)

# Mouse lag & sway inertia
var mouse_input_accum := Vector2.ZERO
var sway_pos := Vector3.ZERO
var sway_rot := Vector3.ZERO

# Procedural Audio for Lighter
var audio_player: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var audio_mix_rate := 22050.0
var active_sfx_type: SfxType = SfxType.NONE
var active_sfx_time := 0.0
var active_sfx_duration := 0.0

# Procedural carpet footfalls use a separate generator so lighter sounds stay crisp.
var footstep_player: AudioStreamPlayer
var footstep_playback: AudioStreamGeneratorPlayback
var footstep_mix_rate := 16000.0
var footstep_time := 1.0
var footstep_strength := 0.7
var footstep_pitch := 82.0
var footstep_cycle_index := -1

# Observer feedback is intentionally diegetic: balance loss, a reluctant flame,
# and narrowed movement communicate danger without adding a conventional health bar.
var observer_pressure := 0.0
var observer_shock := 0.0
var observer_stagger := 0.0
var observer_shock_phase := 0.0

func _ready() -> void:
	add_to_group("player")
	_setup_input_map()
	_build_body()
	_build_lighter()
	_build_audio()
	_build_footstep_audio()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.42
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true

func _setup_input_map() -> void:
	if not InputMap.has_action("toggle_lighter"):
		InputMap.add_action("toggle_lighter")
		var key_f := InputEventKey.new()
		key_f.physical_keycode = KEY_F
		InputMap.action_add_event("toggle_lighter", key_f)
		var mouse_r := InputEventMouseButton.new()
		mouse_r.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("toggle_lighter", mouse_r)

func _build_body() -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	capsule_shape = CapsuleShape3D.new()
	capsule_shape.radius = 0.28
	capsule_shape.height = 1.55
	collision_shape.shape = capsule_shape
	collision_shape.position.y = 0.775
	add_child(collision_shape)

	ceiling_ray = RayCast3D.new()
	ceiling_ray.name = "CeilingRay"
	ceiling_ray.position = Vector3(0.0, 0.6, 0.0)
	ceiling_ray.target_position = Vector3(0.0, 1.05, 0.0)
	ceiling_ray.enabled = true
	add_child(ceiling_ray)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = standing_height
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 74.0
	camera.near = 0.035
	camera.far = 140.0
	camera.rotation.x = pitch
	head.add_child(camera)
	current_cam_height = standing_height

func _build_lighter() -> void:
	viewmodel_root = Node3D.new()
	viewmodel_root.name = "ViewmodelRoot"
	camera.add_child(viewmodel_root)

	lighter_root = Node3D.new()
	lighter_root.name = "Lighter"
	lighter_root.position = VM_UNEQUIPPED_POS
	lighter_root.rotation = VM_BASE_ROT
	lighter_root.scale = Vector3(1.3, 1.3, 1.3)
	lighter_root.visible = false
	viewmodel_root.add_child(lighter_root)

	# --- PBR Materials ---
	# Brushed Brass Casing
	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color("#c49f4c")
	brass_mat.metallic = 0.94
	brass_mat.roughness = 0.26

	# Inset Plate & Windscreen Chrome
	var chrome_mat := StandardMaterial3D.new()
	chrome_mat.albedo_color = Color("#c0c6cc")
	chrome_mat.metallic = 0.96
	chrome_mat.roughness = 0.22

	# Serrated Striker Wheel Steel
	var striker_steel_mat := StandardMaterial3D.new()
	striker_steel_mat.albedo_color = Color("#383b40")
	striker_steel_mat.metallic = 0.92
	striker_steel_mat.roughness = 0.42

	# Dark Interior Cavities
	var dark_interior_mat := StandardMaterial3D.new()
	dark_interior_mat.albedo_color = Color("#181512")
	dark_interior_mat.metallic = 0.60
	dark_interior_mat.roughness = 0.70

	# Charred Wick
	var wick_mat := StandardMaterial3D.new()
	wick_mat.albedo_color = Color("#242220")
	wick_mat.roughness = 0.95

	# Additive Emissive Flame Outer
	var flame_outer_mat := StandardMaterial3D.new()
	flame_outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_outer_mat.albedo_color = Color(1.0, 0.65, 0.25, 0.85)

	# Additive Emissive Flame Inner Core
	var flame_inner_mat := StandardMaterial3D.new()
	flame_inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_inner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_inner_mat.albedo_color = Color(1.0, 0.96, 0.82, 0.96)

	# Additive Flame Base Blue
	var flame_blue_mat := StandardMaterial3D.new()
	flame_blue_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_blue_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_blue_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_blue_mat.albedo_color = Color(0.20, 0.50, 1.0, 0.80)

	# 1. Main Casing Body (Bottom Box)
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.054, 0.062, 0.022)
	body_box.material = brass_mat
	body_mesh.mesh = body_box
	body_mesh.position = Vector3(0.0, 0.0, 0.0)
	lighter_root.add_child(body_mesh)

	# Bottom base rim
	var base_rim := MeshInstance3D.new()
	var base_box := BoxMesh.new()
	base_box.size = Vector3(0.050, 0.002, 0.019)
	base_box.material = brass_mat
	base_rim.mesh = base_box
	base_rim.position = Vector3(0.0, -0.0315, 0.0)
	lighter_root.add_child(base_rim)

	# 2. Chrome Insert Top Plate
	var insert_plate := MeshInstance3D.new()
	var insert_box := BoxMesh.new()
	insert_box.size = Vector3(0.050, 0.003, 0.020)
	insert_box.material = chrome_mat
	insert_plate.mesh = insert_box
	insert_plate.position = Vector3(0.0, 0.0315, 0.0)
	lighter_root.add_child(insert_plate)

	# 3. Flip Lid with Articulated Hinge Pivot
	lid_pivot = Node3D.new()
	lid_pivot.name = "LidPivot"
	lid_pivot.position = Vector3(-0.027, 0.031, 0.0)
	lighter_root.add_child(lid_pivot)

	# Hinge Knuckle Barrel
	var hinge_mesh := MeshInstance3D.new()
	var hinge_cyl := CylinderMesh.new()
	hinge_cyl.top_radius = 0.0026
	hinge_cyl.bottom_radius = 0.0026
	hinge_cyl.height = 0.018
	hinge_cyl.material = brass_mat
	hinge_mesh.mesh = hinge_cyl
	hinge_mesh.rotation.x = deg_to_rad(90.0)
	lid_pivot.add_child(hinge_mesh)

	# Lid Casing (rotates with pivot, opens ~105 degrees around Z)
	var lid_mesh := MeshInstance3D.new()
	var lid_box := BoxMesh.new()
	lid_box.size = Vector3(0.054, 0.035, 0.022)
	lid_box.material = brass_mat
	lid_mesh.mesh = lid_box
	lid_mesh.position = Vector3(0.027, 0.0175, 0.0)
	lid_pivot.add_child(lid_mesh)

	# Lid Top Rounded Cap
	var lid_cap := MeshInstance3D.new()
	var cap_box := BoxMesh.new()
	cap_box.size = Vector3(0.050, 0.004, 0.018)
	cap_box.material = brass_mat
	lid_cap.mesh = cap_box
	lid_cap.position = Vector3(0.027, 0.0355, 0.0)
	lid_pivot.add_child(lid_cap)

	# Hollow interior liner for opened lid
	var lid_liner := MeshInstance3D.new()
	var liner_box := BoxMesh.new()
	liner_box.size = Vector3(0.050, 0.031, 0.018)
	liner_box.material = dark_interior_mat
	lid_liner.mesh = liner_box
	lid_liner.position = Vector3(0.027, 0.015, 0.0)
	lid_pivot.add_child(lid_liner)

	# 4. Chimney / Perforated Windscreen
	var chimney_root := Node3D.new()
	chimney_root.position = Vector3(-0.007, 0.032, 0.0)
	lighter_root.add_child(chimney_root)

	var chimney_box := MeshInstance3D.new()
	var c_box := BoxMesh.new()
	c_box.size = Vector3(0.030, 0.028, 0.018)
	c_box.material = chrome_mat
	chimney_box.mesh = c_box
	chimney_box.position = Vector3(0.0, 0.014, 0.0)
	chimney_root.add_child(chimney_box)

	var chimney_interior := MeshInstance3D.new()
	var c_int := BoxMesh.new()
	c_int.size = Vector3(0.026, 0.026, 0.014)
	c_int.material = dark_interior_mat
	chimney_interior.mesh = c_int
	chimney_interior.position = Vector3(0.0, 0.016, 0.0)
	chimney_root.add_child(chimney_interior)

	# Perforation holes on chimney (8 holes: 4 front, 4 back)
	var hole_offsets := [
		Vector2(-0.007, 0.009), Vector2(0.007, 0.009),
		Vector2(-0.007, 0.018), Vector2(0.007, 0.018)
	]
	for h in hole_offsets:
		for z_side in [0.0091, -0.0091]:
			var hole := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.0016
			cyl.bottom_radius = 0.0016
			cyl.height = 0.002
			cyl.material = dark_interior_mat
			hole.mesh = cyl
			hole.rotation.x = deg_to_rad(90.0)
			hole.position = Vector3(h.x, h.y, z_side)
			chimney_root.add_child(hole)

	# 5. Flint Striker Wheel & Fork
	var striker_root := Node3D.new()
	striker_root.position = Vector3(0.014, 0.032, 0.0)
	lighter_root.add_child(striker_root)

	var fork_mesh := MeshInstance3D.new()
	var fork_box := BoxMesh.new()
	fork_box.size = Vector3(0.006, 0.014, 0.016)
	fork_box.material = chrome_mat
	fork_mesh.mesh = fork_box
	fork_mesh.position = Vector3(0.0, 0.007, 0.0)
	striker_root.add_child(fork_mesh)

	striker_wheel = Node3D.new()
	striker_wheel.position = Vector3(0.0, 0.013, 0.0)
	striker_root.add_child(striker_wheel)

	var wheel_mesh := MeshInstance3D.new()
	var wheel_cyl := CylinderMesh.new()
	wheel_cyl.top_radius = 0.0062
	wheel_cyl.bottom_radius = 0.0062
	wheel_cyl.height = 0.0055
	wheel_cyl.material = striker_steel_mat
	wheel_mesh.mesh = wheel_cyl
	wheel_mesh.rotation.z = deg_to_rad(90.0)
	striker_wheel.add_child(wheel_mesh)

	# Cam toggle lever near hinge
	var cam_lever := MeshInstance3D.new()
	var cam_box := BoxMesh.new()
	cam_box.size = Vector3(0.005, 0.010, 0.006)
	cam_box.material = chrome_mat
	cam_lever.mesh = cam_box
	cam_lever.position = Vector3(-0.018, 0.036, 0.0)
	lighter_root.add_child(cam_lever)

	# 6. Braided Wick
	var wick := MeshInstance3D.new()
	var wick_cyl := CylinderMesh.new()
	wick_cyl.top_radius = 0.0016
	wick_cyl.bottom_radius = 0.0016
	wick_cyl.height = 0.012
	wick_cyl.material = wick_mat
	wick.mesh = wick_cyl
	wick.position = Vector3(-0.007, 0.038, 0.0)
	lighter_root.add_child(wick)

	# 7. Flame Hierarchy & Dynamic OmniLight3D
	flame_root = Node3D.new()
	flame_root.name = "FlameRoot"
	flame_root.position = Vector3(-0.007, 0.046, 0.0)
	flame_root.visible = false
	lighter_root.add_child(flame_root)

	# Outer glowing flame teardrop
	flame_outer_mesh = MeshInstance3D.new()
	var outer_sphere := SphereMesh.new()
	outer_sphere.radius = 0.0065
	outer_sphere.height = 0.024
	outer_sphere.material = flame_outer_mat
	flame_outer_mesh.mesh = outer_sphere
	flame_outer_mesh.position = Vector3(0.0, 0.009, 0.0)
	flame_root.add_child(flame_outer_mesh)

	# Inner intense white-yellow core
	flame_inner_mesh = MeshInstance3D.new()
	var inner_sphere := SphereMesh.new()
	inner_sphere.radius = 0.0035
	inner_sphere.height = 0.013
	inner_sphere.material = flame_inner_mat
	flame_inner_mesh.mesh = inner_sphere
	flame_inner_mesh.position = Vector3(0.0, 0.006, 0.0)
	flame_root.add_child(flame_inner_mesh)

	# Realistic blue flame base
	flame_base_mesh = MeshInstance3D.new()
	var blue_sphere := SphereMesh.new()
	blue_sphere.radius = 0.0040
	blue_sphere.height = 0.0045
	blue_sphere.material = flame_blue_mat
	flame_base_mesh.mesh = blue_sphere
	flame_base_mesh.position = Vector3(0.0, 0.001, 0.0)
	flame_root.add_child(flame_base_mesh)

	# Flame Point / Omni Light
	flame_light = OmniLight3D.new()
	flame_light.name = "FlameLight"
	flame_light.position = Vector3(0.0, 0.015, 0.0)
	flame_light.light_color = Color("#ff9933")
	flame_light.light_energy = 1.70
	flame_light.omni_range = 7.2
	flame_light.omni_attenuation = 1.25
	flame_light.shadow_enabled = true
	flame_light.shadow_bias = 0.035
	flame_light.shadow_blur = 1.6
	flame_light.light_volumetric_fog_energy = 1.8
	flame_light.visible = false
	flame_root.add_child(flame_light)

	var casing_glow := OmniLight3D.new()
	casing_glow.name = "CasingGlow"
	casing_glow.position = Vector3(0.01, -0.015, 0.02)
	casing_glow.light_color = Color("#ffb347")
	casing_glow.light_energy = 0.65
	casing_glow.omni_range = 0.35
	casing_glow.omni_attenuation = 1.0
	casing_glow.shadow_enabled = false
	flame_root.add_child(casing_glow)

func _build_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "LighterAudio"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = audio_mix_rate
	gen.buffer_length = 0.12
	audio_player.stream = gen
	audio_player.volume_db = -6.0
	add_child(audio_player)
	audio_player.play()
	audio_playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _build_footstep_audio() -> void:
	footstep_player = AudioStreamPlayer.new()
	footstep_player.name = "FootstepAudio"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = footstep_mix_rate
	generator.buffer_length = 0.12
	footstep_player.stream = generator
	footstep_player.volume_db = -10.0
	add_child(footstep_player)
	footstep_player.play()
	footstep_playback = footstep_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _trigger_footstep(strength: float) -> void:
	footstep_time = 0.0
	footstep_strength = clampf(strength, 0.25, 1.0)
	footstep_pitch = randf_range(72.0, 94.0)

func _fill_footstep_audio() -> void:
	if footstep_playback == null:
		return
	var frames_available := footstep_playback.get_frames_available()
	var frame_delta := 1.0 / footstep_mix_rate
	for _frame in range(frames_available):
		var sample := 0.0
		if footstep_time < 0.19:
			var attack := clampf(footstep_time / 0.006, 0.0, 1.0)
			var envelope := attack * exp(-footstep_time * 24.0)
			var sole_thump := sin(footstep_time * TAU * footstep_pitch) * exp(-footstep_time * 18.0)
			var carpet_grit := randf_range(-1.0, 1.0) * (0.72 + sin(footstep_time * TAU * 310.0) * 0.16)
			var fabric_scuff := sin(footstep_time * TAU * 165.0) * randf_range(0.10, 0.26)
			sample = (sole_thump * 0.38 + carpet_grit * 0.48 + fabric_scuff) * envelope * footstep_strength * 0.42
			footstep_time += frame_delta
		footstep_playback.push_frame(Vector2(sample * 0.96, sample))

func play_lighter_sfx(type: SfxType) -> void:
	active_sfx_type = type
	active_sfx_time = 0.0
	match type:
		SfxType.SNAP_OPEN:
			active_sfx_duration = 0.065
		SfxType.SNAP_CLOSE:
			active_sfx_duration = 0.075
		SfxType.FLINT_STRIKE:
			active_sfx_duration = 0.070
		SfxType.IGNITE_PUFF:
			active_sfx_duration = 0.080
		SfxType.REFILL_SLOSH:
			active_sfx_duration = 0.42
		_:
			active_sfx_duration = 0.0

func _fill_lighter_audio() -> void:
	if audio_playback == null:
		return
	var frames_avail := audio_playback.get_frames_available()
	if frames_avail <= 0:
		return
	var dt := 1.0 / audio_mix_rate
	for _i in range(frames_avail):
		var sample := 0.0
		if active_sfx_type != SfxType.NONE and active_sfx_time < active_sfx_duration:
			var t := active_sfx_time
			match active_sfx_type:
				SfxType.SNAP_OPEN:
					var env := exp(-t * 85.0)
					var click := (randf_range(-1.0, 1.0) if t < 0.003 else 0.0)
					var tone := sin(t * TAU * 3600.0) * 0.45 + sin(t * TAU * 5400.0) * 0.35 + sin(t * TAU * 7200.0) * 0.20
					sample = (click * 0.5 + tone * env) * 0.40
				SfxType.SNAP_CLOSE:
					var env := exp(-t * 70.0)
					var thud := (randf_range(-1.0, 1.0) if t < 0.004 else 0.0)
					var tone := sin(t * TAU * 1900.0) * 0.55 + sin(t * TAU * 3100.0) * 0.30 + sin(t * TAU * 480.0) * 0.25
					sample = (thud * 0.55 + tone * env) * 0.45
				SfxType.FLINT_STRIKE:
					var env := (1.0 - t / active_sfx_duration) * (1.0 if t > 0.006 else t / 0.006)
					var rasp := randf_range(-0.5, 0.5) + sin(t * TAU * 2800.0) * 0.35 + sin(t * TAU * 4200.0) * 0.20
					sample = rasp * env * 0.34
				SfxType.IGNITE_PUFF:
					var env := exp(-t * 32.0)
					var whoosh := (randf_range(-0.4, 0.4) + sin(t * TAU * 340.0) * 0.32)
					sample = whoosh * env * 0.28
				SfxType.REFILL_SLOSH:
					var env := 1.0 - (t / active_sfx_duration)
					var click := (randf_range(-0.7, 0.7) + sin(t * TAU * 3800.0) * 0.35) if t < 0.02 else 0.0
					var glug_t := fmod(t, 0.12)
					var bubble_f := 420.0 + (t / active_sfx_duration) * 340.0 + sin(glug_t * TAU * 15.0) * 60.0
					var glug_env := exp(-glug_t * 24.0)
					var liquid_tone := sin(t * TAU * bubble_f) * glug_env
					var slosh_noise := randf_range(-0.14, 0.14) * env
					sample = (click * 0.40 + (liquid_tone * 0.65 + slosh_noise * 0.30) * env) * 0.52
			active_sfx_time += dt
			if active_sfx_time >= active_sfx_duration:
				active_sfx_type = SfxType.NONE
		audio_playback.push_frame(Vector2(sample, sample))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pitch = clamp(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-82.0), deg_to_rad(82.0))
		camera.rotation.x = pitch
		mouse_input_accum += event.relative
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Lighter toggle input detection (<kbd>F</kbd>, <kbd>Right Click</kbd>, or action)
	var wants_lighter_toggle := false
	if event.is_action_pressed("toggle_lighter"):
		wants_lighter_toggle = true
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		wants_lighter_toggle = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		wants_lighter_toggle = true

	if wants_lighter_toggle:
		toggle_lighter()

func toggle_lighter() -> void:
	if lighter_state == LighterState.UNEQUIPPED or lighter_state == LighterState.UNEQUIPPING:
		equip_lighter()
	else:
		unequip_lighter()

func equip_lighter() -> void:
	lighter_state = LighterState.EQUIPPING
	lighter_root.visible = true
	did_snap_open = false
	did_strike_flint = false
	did_snap_close = false

func unequip_lighter() -> void:
	lighter_state = LighterState.UNEQUIPPING
	flame_ignited = false
	if flame_root != null:
		flame_root.visible = false
	if flame_light != null:
		flame_light.visible = false
	did_snap_close = false

func _process(delta: float) -> void:
	elapsed += delta
	observer_shock = move_toward(observer_shock, 0.0, delta * 0.42)
	observer_stagger = move_toward(observer_stagger, 0.0, delta * 0.34)
	observer_shock_phase += delta * (13.0 + observer_pressure * 8.0)
	if camera != null:
		var target_fov := 74.0 - observer_pressure * 1.35 + sin(observer_shock_phase * 0.37) * observer_shock * 1.1
		camera.fov = lerpf(camera.fov, target_fov, delta * 4.0)
	_update_lighter_animation(delta)
	_fill_lighter_audio()
	_fill_footstep_audio()

func _update_lighter_animation(delta: float) -> void:
	# 1. State Progression
	match lighter_state:
		LighterState.EQUIPPING:
			equip_progress = move_toward(equip_progress, 1.0, delta * 2.3)
			
			# Lid snaps open around 35% through the raise
			if equip_progress >= 0.35:
				lid_progress = move_toward(lid_progress, 1.0, delta * 7.5)
				if not did_snap_open and lid_progress > 0.15:
					did_snap_open = true
					play_lighter_sfx(SfxType.SNAP_OPEN)
			
			# Flint wheel strike spark around 65%
			if equip_progress >= 0.65 and not did_strike_flint:
				did_strike_flint = true
				play_lighter_sfx(SfxType.FLINT_STRIKE)
				spark_flash_timer = 0.065
				if striker_wheel != null:
					striker_wheel.rotation.z += 1.3
			
			# Flame ignites around 80% if fuel remaining
			if equip_progress >= 0.80 and not flame_ignited:
				if lighter_fuel > 0.0:
					flame_ignited = true
					flame_root.visible = true
					flame_light.visible = true
					play_lighter_sfx(SfxType.IGNITE_PUFF)
			
			# Reached full resting position
			if equip_progress >= 1.0:
				if lighter_fuel > 0.0:
					lighter_state = LighterState.LIT
				else:
					lighter_state = LighterState.OUT_OF_FUEL

		LighterState.UNEQUIPPING:
			# Flame is extinguished immediately on unequip
			if flame_ignited:
				flame_ignited = false
				flame_root.visible = false
				flame_light.visible = false
			
			# Lid snaps shut
			lid_progress = move_toward(lid_progress, 0.0, delta * 8.5)
			if not did_snap_close and lid_progress < 0.80:
				did_snap_close = true
				play_lighter_sfx(SfxType.SNAP_CLOSE)
			
			# Lower lighter offscreen once lid is mostly shut
			if lid_progress <= 0.15:
				equip_progress = move_toward(equip_progress, 0.0, delta * 2.6)
			
			if equip_progress <= 0.0:
				lighter_state = LighterState.UNEQUIPPED
				lighter_root.visible = false

		LighterState.LIT:
			equip_progress = 1.0
			lid_progress = 1.0

		LighterState.OUT_OF_FUEL:
			equip_progress = 1.0
			lid_progress = 1.0
			flame_ignited = false
			flame_root.visible = false
			flame_light.visible = false

		LighterState.UNEQUIPPED:
			equip_progress = 0.0
			lid_progress = 0.0
			lighter_root.visible = false

	# 2. Spark Flash Logic
	if spark_flash_timer > 0.0:
		spark_flash_timer -= delta
		flame_light.visible = true
		flame_light.light_energy = 3.6
		flame_light.light_color = Color("#ffe8aa")
	elif not flame_ignited and lighter_state != LighterState.LIT:
		flame_light.visible = false

	# 3. Fuel Consumption & Flame Sputter
	if flame_ignited:
		lighter_fuel -= delta * fuel_drain_rate
		if lighter_fuel <= 0.0:
			lighter_fuel = 0.0
			flame_ignited = false
			flame_root.visible = false
			flame_light.visible = false
			lighter_state = LighterState.OUT_OF_FUEL
			play_lighter_sfx(SfxType.IGNITE_PUFF)
		else:
			# Organic flame micro-jitter and flicker
			var flicker := sin(elapsed * 25.0) * 0.08 + sin(elapsed * 43.0) * 0.05 + randf_range(-0.03, 0.03)
			var sputter := 1.0
			if lighter_fuel < 20.0:
				var sputter_chance := 0.22 if lighter_fuel < 10.0 else 0.10
				if randf() < sputter_chance:
					sputter = randf_range(0.20, 0.65)
			elif observer_pressure > 0.48 and randf() < observer_pressure * delta * 1.8:
				# Sparse pressure sputters warn that the pursuit phase is close, but the
				# lighter remains useful as a deliberate counterplay tool.
				sputter = randf_range(0.45, 0.82)
			
			flame_light.light_energy = (1.70 + flicker) * sputter
			flame_light.light_color = Color("#ff9933")
			
			# Dynamic flame teardrop stretch/dance
			var flame_sy := (1.0 + sin(elapsed * 28.0) * 0.12 + randf_range(-0.04, 0.04)) * sputter
			var flame_sxz := (1.0 + sin(elapsed * 20.0 + 1.2) * 0.08) * sputter
			flame_root.scale = Vector3(flame_sxz, flame_sy, flame_sxz)

	# 4. Apply Lid Hinge Rotation (~105 degrees open around Z)
	if lid_pivot != null:
		lid_pivot.rotation.z = lerp(0.0, deg_to_rad(-105.0), lid_progress)

	# 5. Viewmodel Placement, Sway & Headbob Inertia
	var base_pos := VM_UNEQUIPPED_POS.lerp(VM_RESTING_POS, equip_progress)
	
	# Mouse sway inertia
	sway_pos.x = lerp(sway_pos.x, -mouse_input_accum.x * 0.00014, delta * 12.0)
	sway_pos.y = lerp(sway_pos.y, mouse_input_accum.y * 0.00014, delta * 12.0)
	sway_rot.y = lerp(sway_rot.y, -mouse_input_accum.x * 0.00030, delta * 10.0)
	sway_rot.x = lerp(sway_rot.x, mouse_input_accum.y * 0.00030, delta * 10.0)
	mouse_input_accum = Vector2.ZERO

	# Gentle sync with walking gait headbob
	var bob_vm := Vector3.ZERO
	if is_on_floor() and velocity.length() > 0.2:
		bob_vm.y = sin(step_cycle) * 0.004
		bob_vm.x = cos(step_cycle * 0.5) * 0.003
	else:
		bob_vm.y = sin(idle_time * 1.5) * 0.0012

	lighter_root.position = base_pos + sway_pos + bob_vm
	lighter_root.rotation = VM_BASE_ROT + sway_rot

func is_lighter_lit() -> bool:
	return flame_ignited

func is_lighter_equipped() -> bool:
	return lighter_state != LighterState.UNEQUIPPED

func get_fuel_ratio() -> float:
	return clampf(lighter_fuel / max_fuel, 0.0, 1.0)

func add_fuel(amount: float) -> void:
	lighter_fuel = clampf(lighter_fuel + amount, 0.0, max_fuel)
	play_lighter_sfx(SfxType.REFILL_SLOSH)
	if lighter_state == LighterState.OUT_OF_FUEL and lighter_fuel > 0.0:
		if equip_progress >= 0.8:
			flame_ignited = true
			if flame_root != null:
				flame_root.visible = true
			if flame_light != null:
				flame_light.visible = true
			lighter_state = LighterState.LIT
		else:
			lighter_state = LighterState.UNEQUIPPED

func set_observer_pressure(amount: float) -> void:
	observer_pressure = clampf(amount, 0.0, 1.0)

func apply_observer_strike(severity: float, away_direction: Vector3) -> void:
	observer_shock = maxf(observer_shock, clampf(0.75 + severity * 0.45, 0.0, 1.25))
	observer_stagger = maxf(observer_stagger, clampf(0.65 + severity * 0.40, 0.0, 1.0))
	if away_direction.length_squared() > 0.001:
		velocity += away_direction.normalized() * (1.6 + severity * 1.2)
	velocity.y = maxf(velocity.y, 1.0)
	lighter_fuel = maxf(0.0, lighter_fuel - lerpf(8.0, 16.0, severity))
	unequip_lighter()

func reset_after_observer_collapse(safe_position: Vector3) -> void:
	global_position = safe_position
	velocity = Vector3.ZERO
	observer_shock = 1.25
	observer_stagger = 1.0
	lighter_fuel = maxf(0.0, lighter_fuel - 22.0)
	unequip_lighter()

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# Landing impact detection
	if on_floor and not was_on_floor:
		var fall_speed: float = absf(velocity.y)
		landing_dip = clampf(fall_speed * 0.015, 0.02, 0.07)
		_trigger_footstep(clampf(fall_speed / 7.0, 0.45, 1.0))
	was_on_floor = on_floor

	# Crouch input & state
	var wants_crouch := Input.is_action_pressed("crouch") or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	if wants_crouch:
		is_crouching = true
	else:
		# Only stand up if there is ceiling clearance
		if not ceiling_ray.is_colliding():
			is_crouching = false

	# Crouch collision adjustment
	var target_capsule_h := 0.95 if is_crouching else 1.55
	var target_capsule_y := 0.475 if is_crouching else 0.775
	capsule_shape.height = lerp(capsule_shape.height, target_capsule_h, delta * crouch_transition_speed)
	collision_shape.position.y = lerp(collision_shape.position.y, target_capsule_y, delta * crouch_transition_speed)

	# Movement input
	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_2d.is_zero_approx():
		var kx := 0.0
		var ky := 0.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			kx -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			kx += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			ky -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			ky += 1.0
		input_2d = Vector2(kx, ky).normalized()
	var move_direction := (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()

	# Determine speed
	var wants_sprint := (Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)) and not is_crouching
	var target_speed := walk_speed
	if is_crouching:
		target_speed = crouch_speed
	elif wants_sprint and input_2d.y < 0.0:
		target_speed = sprint_speed
	var threat_slow := clampf(observer_pressure * 0.12 + observer_stagger * 0.30, 0.0, 0.38)
	target_speed *= 1.0 - threat_slow

	# Kinematics & Friction
	var current_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_horizontal := move_direction * target_speed

	if on_floor:
		if move_direction.length_squared() > 0.0:
			var dot := current_horizontal.normalized().dot(move_direction)
			var accel_rate := acceleration
			if dot < 0.2 and current_horizontal.length() > 0.5:
				accel_rate = deceleration * 1.5
			current_horizontal = current_horizontal.move_toward(target_horizontal, accel_rate * delta)
		else:
			current_horizontal = current_horizontal.move_toward(Vector3.ZERO, deceleration * delta)
			if current_horizontal.length() < 0.04:
				current_horizontal = Vector3.ZERO
		
		velocity.x = current_horizontal.x
		velocity.z = current_horizontal.z

		# Jump & Ground snapping
		if Input.is_action_just_pressed("jump") or (Input.is_key_pressed(KEY_SPACE) and not wants_crouch):
			if not is_crouching:
				velocity.y = jump_velocity
		else:
			velocity.y = -0.2
	else:
		velocity.y -= gravity * delta
		var air_accel := acceleration * air_control
		velocity.x = move_toward(velocity.x, target_horizontal.x, air_accel * delta)
		velocity.z = move_toward(velocity.z, target_horizontal.z, air_accel * delta)

	# Dynamic step-climb traversal for steps/curbs <= 0.42m
	_snap_up_stairs_check(delta, move_direction)

	move_and_slide()

	# --- Camera & Head Mechanics ---
	var h_speed := Vector2(velocity.x, velocity.z).length()
	var target_cam_h := crouch_height if is_crouching else standing_height
	current_cam_height = lerp(current_cam_height, target_cam_h, delta * crouch_transition_speed)

	# Dynamic Step Cycle & Head Bobbing
	var bob_offset := Vector3.ZERO
	if on_floor and h_speed > 0.15:
		var freq := bob_frequency_walk
		if is_crouching:
			freq = bob_frequency_crouch
		elif wants_sprint and h_speed > walk_speed + 0.3:
			freq = bob_frequency_sprint
		
		step_cycle += delta * freq * (h_speed / target_speed)
		var current_step_index := int(floor(step_cycle / PI))
		if current_step_index != footstep_cycle_index:
			footstep_cycle_index = current_step_index
			var gait_strength := 0.48 if is_crouching else (0.92 if wants_sprint else 0.68)
			_trigger_footstep(gait_strength)
		
		var amp_y := bob_amplitude_vertical * (0.6 if is_crouching else (1.25 if wants_sprint else 1.0))
		var amp_x := bob_amplitude_horizontal * (0.6 if is_crouching else (1.25 if wants_sprint else 1.0))
		
		bob_offset.y = -absf(sin(step_cycle)) * amp_y
		bob_offset.x = cos(step_cycle * 0.5) * amp_x
	else:
		step_cycle = fmod(step_cycle, TAU * 2.0)
		idle_time += delta * 1.6
		bob_offset.y = sin(idle_time) * 0.003
		bob_offset.x = cos(idle_time * 0.7) * 0.002

	# Strafe tilt (camera roll)
	var strafe_input := input_2d.x
	target_roll = deg_to_rad(-strafe_input * strafe_tilt_angle)
	current_roll = lerp(current_roll, target_roll, delta * 8.0)
	camera.rotation.z = current_roll + sin(observer_shock_phase) * observer_shock * 0.035

	# Landing dip recovery
	landing_dip = lerp(landing_dip, 0.0, delta * 12.0)

	# Final head positioning
	var target_head_y := current_cam_height + bob_offset.y - landing_dip
	head.position.y = lerp(head.position.y, target_head_y, delta * 24.0)
	var shock_offset := sin(observer_shock_phase * 0.73) * observer_shock * 0.026
	head.position.x = lerp(head.position.x, bob_offset.x + shock_offset, delta * 18.0)

const MAX_STEP_HEIGHT := 0.42

func _snap_up_stairs_check(delta: float, wish_dir: Vector3) -> void:
	if not is_on_floor() or velocity.y > 0.1:
		return

	var forward_dir := Vector3.ZERO
	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	if h_vel.length_squared() > 0.01:
		forward_dir = h_vel.normalized()
	elif wish_dir.length_squared() > 0.01:
		forward_dir = wish_dir.normalized()
	else:
		return

	var move_dist := h_vel.length() * delta
	var probe_dist := maxf(move_dist, 0.10)
	var test_forward := forward_dir * probe_dist

	# Test collision horizontally
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, test_forward, col):
		return # No collision ahead

	# If already a steep walkable slope and moving up freely, standard move_and_slide handles it
	if col.get_normal().y >= 0.85:
		return

	# Step 1: Upward clearance check
	var up_vec := Vector3(0.0, MAX_STEP_HEIGHT, 0.0)
	if test_move(global_transform, up_vec):
		return # Blocked overhead

	# Step 2: Forward clearance check from elevated position
	var elevated_xform := global_transform.translated(up_vec)
	if test_move(elevated_xform, test_forward):
		return # Wall too tall to step over

	# Step 3: Cast downward to locate the step tread surface
	var forward_elevated_xform := elevated_xform.translated(test_forward)
	var down_vec := Vector3(0.0, -(MAX_STEP_HEIGHT + 0.08), 0.0)
	var down_col := KinematicCollision3D.new()
	if test_move(forward_elevated_xform, down_vec, down_col):
		if down_col.get_normal().y >= 0.65:
			var step_up := MAX_STEP_HEIGHT + down_col.get_travel().y
			if step_up > 0.01 and step_up <= MAX_STEP_HEIGHT + 0.04:
				global_position.y += step_up
				global_position += forward_dir * maxf(move_dist * 0.5, 0.04)
