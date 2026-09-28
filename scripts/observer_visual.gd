extends Node3D
## A continuous skinned creature. The legs plant against the floor while the torso
## stays unnervingly quiet; hands and gaze trail the direction of travel.
const MODEL_SCALE := 0.87
@onready var stance: Node3D = $Stance
var skeleton: Skeleton3D
var skin: ShaderMaterial
var phase := 0.0
var age := 0.0
var motion := 0.0
var run_blend := 0.0
var crouch_blend := 0.0
var pose_variant: StringName = &"sentinel"
var bones: Dictionary = {}
var rest_rotations: Dictionary = {}
var global_rests: Dictionary = {}
var head_angle := Vector3.ZERO
var head_target := Vector3.ZERO
var head_timer := 2.4
var turn_lag := 0.0
var previous_yaw := 0.0
# Statue mode: 0 = fully alive, 1 = perfectly frozen. Driven by main.gd from the
# player's gaze signal — the Observer holds still while watched from a distance.
var statue_target := 0.0
var statue_blend := 0.0
func _ready() -> void:
	skin = ShaderMaterial.new()
	skin.shader = preload("res://shaders/observer_flesh.gdshader")
	for node in stance.find_children("*", "MeshInstance3D", true, false):
		node.material_override = skin
	var rigs := stance.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		skeleton = rigs[0] as Skeleton3D
		for index in range(skeleton.get_bone_count()):
			var bone_name := skeleton.get_bone_name(index)
			bones[bone_name] = index
			rest_rotations[bone_name] = skeleton.get_bone_pose_rotation(index)
			global_rests[bone_name] = skeleton.get_bone_global_rest(index)
	previous_yaw = rotation.y

func get_skin_material() -> ShaderMaterial:
	return skin

func set_pose_variant(value: StringName) -> void:
	pose_variant = value

func set_statue_target(value: float) -> void:
	statue_target = clampf(value, 0.0, 1.0)

func update_pose(delta: float, speed: float, threat: float, attacking: bool, crouch := 0.0) -> void:
	# Statue mode freezes every age-driven micro-motion (breath, head wander,
	# stance sway) and the gait cycle. The body still faces its target — a
	# motionless figure tracking you is the point.
	statue_blend = move_toward(statue_blend, statue_target, delta * 2.2)
	var live := 1.0 - statue_blend
	var adelta := delta * live
	age += adelta
	motion = move_toward(motion, clampf(speed * live / 0.35, 0.0, 1.0), delta * 3.5)
	run_blend = move_toward(run_blend, smoothstep(1.6, 3.5, speed), adelta * 2.0)
	var stride_length := lerpf(1.25, 1.9, run_blend)
	phase += adelta * maxf(speed, 0.0) * TAU / (stride_length * MODEL_SCALE)
	crouch_blend = move_toward(crouch_blend, crouch, adelta * 7.0)
	var stride := sin(phase)
	var breath := sin(age * 0.9) * 0.004
	var yaw_delta := angle_difference(previous_yaw, rotation.y)
	previous_yaw = rotation.y
	turn_lag = lerpf(turn_lag - yaw_delta, 0.0, minf(adelta * 4.0, 1.0))
	turn_lag = clampf(turn_lag, -0.24, 0.24)
	head_timer -= adelta
	if head_timer <= 0.0:
		# A held look, then a small late correction. No constant metronomic head bob.
		head_timer = 4.2 + fposmod(age * 1.1, 5.0)
		head_target = Vector3(sin(age * 0.29) * 0.02, sin(age * 0.47) * 0.03, sin(age * 0.83) * 0.05)
	head_angle = head_angle.lerp(head_target, minf(adelta * (5.0 if threat > 0.6 else 2.8), 1.0))
	stance.scale.y = lerpf(1.0, 0.88, crouch_blend)
	stance.position.y = (-0.08 - run_blend * 0.045 + absf(sin(phase * 2.0)) * 0.012) * motion
	stance.rotation = Vector3(0.0, 0.0, -0.012 + sin(age * 0.24) * 0.004 * (1.0 - motion))
	_pose("Spine", Vector3(-0.018 - run_blend * 0.11 - crouch_blend * 0.10 + breath, turn_lag * 0.65, -0.028 - stride * 0.014 * motion))
	_pose("Neck", Vector3(0.025 + run_blend * 0.075, -turn_lag * 0.45, -0.045))
	_pose("Head", head_angle + Vector3(-0.025, -turn_lag * 0.55, 0.072))
	_leg("L", phase, stride_length)
	_leg("R", phase + PI, stride_length)
	var reach := 1.16 if attacking else threat * 0.055
	# Arms lag the legs, with unequal reach and very little normal human arm swing.
	_pose("ArmL", Vector3(-sin(phase - 0.45) * 0.07 * motion + reach, turn_lag * 0.2, 0.04))
	_pose("ArmR", Vector3(sin(phase - 0.72) * 0.05 * motion + reach * 0.91, -turn_lag * 0.15, 0.045))
	_pose("ForearmL", Vector3(0.07 + threat * 0.12, 0.07, 0.035))
	_pose("ForearmR", Vector3(0.015 + threat * 0.10, -0.04, -0.025))
	_pose("HandL", Vector3(-0.045 + sin(age * 0.61) * 0.01, 0.03, 0.0))
	_pose("HandR", Vector3(0.018, -0.035, 0.025))
	for side in ["L", "R"]:
		for index in range(5):
			_pose("Finger" + side + str(index), Vector3(threat * 0.075 + sin(age * 0.5 + index * 0.75) * 0.004, 0, 0))

func _leg(side: String, cycle: float, stride_length: float) -> void:
	if skeleton == null: return
	var t := fposmod(cycle / TAU, 1.0)
	var duty := lerpf(0.64, 0.55, run_blend)
	var travel := stride_length * duty
	var foot_z := 0.0
	var lift := 0.0
	if t < duty:
		foot_z = lerpf(-travel * 0.5, travel * 0.5, t / duty)
	else:
		var swing := (t - duty) / (1.0 - duty)
		foot_z = lerpf(travel * 0.5, -travel * 0.5, smoothstep(0.0, 1.0, swing))
		lift = sin(swing * PI) * lerpf(0.06, 0.14, run_blend)
	var hip: Vector3 = global_rests["Thigh" + side].origin
	var knee_rest: Vector3 = global_rests["Shin" + side].origin
	var ankle_rest: Vector3 = global_rests["Foot" + side].origin
	var target := ankle_rest + Vector3(0.0, lift * motion - stance.position.y / (stance.scale.y * MODEL_SCALE), foot_z * motion + (0.04 if side == "L" else -0.025))
	var upper := hip.distance_to(knee_rest)
	var lower := knee_rest.distance_to(ankle_rest)
	var offset := target - hip
	var distance := clampf(offset.length(), 0.05, upper + lower - 0.002)
	var direction := offset.normalized()
	target = hip + direction * distance
	var along := (upper * upper + distance * distance - lower * lower) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var bend := Vector3.FORWARD - direction * Vector3.FORWARD.dot(direction)
	bend = bend.normalized()
	var knee := hip + direction * along + bend * height
	_point_bone("Thigh" + side, knee - hip)
	_point_bone("Shin" + side, target - knee)
	# The sole remains level throughout the planted part of a stride.
	_point_bone("Foot" + side, global_rests["Foot" + side].basis.y)

func _point_bone(bone_name: String, direction: Vector3) -> void:
	var index: int = bones[bone_name]
	var rest: Transform3D = global_rests[bone_name]
	var rotation_delta := Quaternion(rest.basis.y.normalized(), direction.normalized())
	var desired := Basis(rotation_delta) * rest.basis
	var parent := skeleton.get_bone_parent(index)
	if parent >= 0:
		desired = skeleton.get_bone_global_pose(parent).basis.inverse() * desired
	skeleton.set_bone_pose_rotation(index, desired.get_rotation_quaternion())

func _pose(bone_name: String, rotation_value: Vector3) -> void:
	if skeleton != null and bones.has(bone_name):
		skeleton.set_bone_pose_rotation(bones[bone_name], rest_rotations[bone_name] * Quaternion.from_euler(rotation_value))
