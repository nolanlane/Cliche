extends SceneTree
## Tests actual imported skeleton rest rotations, floor planting, and crouch height.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var creature = load("res://scenes/gameplay/observer.tscn").instantiate()
	root.add_child(creature)
	creature.visible = true
	await process_frame
	var skeleton: Skeleton3D = creature.skeleton
	var results: Array = []
	for speed in [0.0, 0.65, 1.25, 3.6]:
		creature.position = Vector3.ZERO
		creature.motion = 0.0
		creature.phase = 0.0
		var previous: Dictionary = {}
		var maximum_slide := 0.0
		var minimum_ankle := INF
		var maximum_ankle := -INF
		for frame in range(300):
			creature.position.z -= speed / 60.0
			creature.update_pose(1.0 / 60.0, speed, 0.4, false)
			for side in ["L", "R"]:
				var pose := skeleton.get_bone_global_pose(creature.bones["Foot" + side])
				var ankle: Vector3 = skeleton.global_transform * pose.origin
				var phase_offset := 0.0 if side == "L" else PI
				var cycle := fposmod((creature.phase + phase_offset) / TAU, 1.0)
				var duty := lerpf(0.64, 0.55, creature.run_blend)
				var planted := cycle > 0.03 and cycle < duty - 0.03
				if frame > 60:
					minimum_ankle = minf(minimum_ankle, ankle.y)
					maximum_ankle = maxf(maximum_ankle, ankle.y)
					if planted and previous.has(side) and previous[side].planted:
						maximum_slide = maxf(maximum_slide, ankle.distance_to(previous[side].position))
				previous[side] = {"position": ankle, "planted": planted}
		if minimum_ankle < 0.07 or maximum_ankle > 0.48:
			failures.append("Bad foot height at speed " + str(speed))
		if maximum_slide > 0.024:
			failures.append("Foot skating at speed " + str(speed) + ": " + str(maximum_slide))
		results.append({"speed": speed, "min_ankle": minimum_ankle, "max_ankle": maximum_ankle, "max_planted_slide_per_frame": maximum_slide})
	creature.update_pose(1.0, 0.0, 0.0, false, 1.0)
	if absf(creature.stance.scale.y - 0.88) > 0.001: failures.append("Crouch not applied")
	var report := {"pass": failures.is_empty(), "gaits": results, "failures": failures}
	var output := FileAccess.open("res://artifacts/observer-overhaul/pose-audit.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("POSE AUDIT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
