extends SceneTree
## Actual level physics plus deterministic director stepping, no forced-only success.
var scene: Node3D
var player: CharacterBody3D
var failures: Array[String] = []
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.set_physics_process(false)
	player = scene.player
	player.set_physics_process(false)
	player.set_process(false)
	await physics_frame
	await physics_frame
	while not scene.observer_navigation.ready:
		scene.observer_navigation.bake_slice(20000)
	report["navigation_cells"] = scene.observer_navigation.graph.get_point_count()
	var appearances: Array = []
	var captures: Array = []
	for trial in range(6):
		seed(700 + trial)
		scene.debug_observer_scenario("natural")
		var first := -1.0
		var died := -1.0
		for frame in range(2400):
			scene._update_observer_presence(1.0 / 60.0)
			if first < 0.0 and scene.observer.visible:
				first = float(frame) / 60.0
				var sight: Dictionary = scene._observer_visibility(player.get_node("Head/Camera3D"), scene.observer.global_position)
				check(sight.samples > 0 and sight.dot > 0.18, "First encounter must be visible at spawn, trial " + str(trial))
			if scene.observer_defeated:
				died = float(frame) / 60.0
				break
		appearances.append(first)
		captures.append(died)
		check(first >= 7.0 and first < 12.0, "Natural appearance within 7–12 seconds, trial " + str(trial))
		check(died > first + 3.5 and died < 36.0, "Idle player is caught after warning, trial " + str(trial))
		check(player.observer_capture_lock > 0.0, "Capture must lock player input")
		await process_frame
	report["natural_appearance_seconds"] = appearances
	report["idle_capture_seconds"] = captures

	# A real multi-corner chase route across authored doorways.
	scene.debug_observer_scenario("portrait")
	var start: Vector3 = scene._observer_grounded_position(Vector3(-13, 0, -6.3))
	var goal: Vector3 = scene._observer_grounded_position(Vector3(1.2, 0, 3.2))
	check(start != Vector3.INF and goal != Vector3.INF, "Route endpoints clear")
	var route: PackedVector3Array = scene.observer_navigation.route(start, goal)
	report["corner_route_points"] = route.size()
	check(route.size() > 3, "A route exists around reception walls")
	scene.observer.global_position = start
	var crossed_wall := false
	var low_door := false
	for frame in range(1800):
		var previous: Vector3 = scene.observer.global_position
		scene._move_observer_toward(goal, 3.8, 1.0 / 60.0)
		if not scene._observer_has_walk_path(previous, scene.observer.global_position): crossed_wall = true
		if not scene.observer_navigation.clearance(scene.observer.global_position, 2.30): low_door = true
		if scene.observer.global_position.distance_to(goal) < 0.2: break
	report["corner_route_end_distance"] = scene.observer.global_position.distance_to(goal)
	report["low_door_traversed"] = low_door
	check(not crossed_wall, "No chase segment may sweep through a wall")
	check(low_door, "Route exercises a low doorway")
	check(scene.observer.global_position.distance_to(goal) < 0.2, "Creature follows the full corner route")

	# Descend the actual sump ramp with the same movement/collision routine.
	var sump_goal: Vector3 = scene._observer_grounded_position(Vector3(-7.0, -1.2, 30.0))
	var sump_route: PackedVector3Array = scene.observer_navigation.route(goal, sump_goal)
	check(not sump_route.is_empty(), "Sump route crosses floor elevations")
	scene.observer_route.clear()
	scene.observer_route_timer = 0.0
	for frame in range(2400):
		scene._move_observer_toward(sump_goal, 3.8, 1.0 / 60.0)
		if scene.observer.global_position.distance_to(sump_goal) < 0.2: break
	report["sump_route_end_distance"] = scene.observer.global_position.distance_to(sump_goal)
	check(scene.observer.global_position.distance_to(sump_goal) < 0.2, "Creature descends the sump ramp")

	# Find two valid standing positions less than capture range apart across a wall.
	var wall_pair: Array[Vector3] = []
	for iz in range(-30, 20):
		if not wall_pair.is_empty(): break
		for ix in range(-30, 30):
			var a: Vector3 = scene._observer_grounded_position(Vector3(ix * 0.5, 0, iz * 0.5))
			if a == Vector3.INF: continue
			for axis in [Vector3(0.98, 0, 0), Vector3(0, 0, 0.98)]:
				var b: Vector3 = scene._observer_grounded_position(a + axis)
				if b != Vector3.INF and not scene._observer_has_walk_path(a, b):
					wall_pair = [a, b]
					break
			if not wall_pair.is_empty(): break
	check(not wall_pair.is_empty(), "Found a thin wall contact fixture")
	if not wall_pair.is_empty():
		scene.debug_observer_scenario("portrait")
		scene.observer.global_position = wall_pair[0]
		player.global_position = wall_pair[1]
		scene._begin_observer_pursuit()
		scene._update_observer_pursuit(1.0 / 60.0, player.get_node("Head/Camera3D"))
		check(scene.observer_state != scene.ObserverState.CAPTURE, "No capture through a wall")
		report["wall_contact_positions"] = [str(wall_pair[0]), str(wall_pair[1])]

	# Losing sight gives up only after searching the last known location.
	scene.debug_observer_scenario("chase")
	player.global_position = Vector3(-44, 0, 42)
	player.velocity = Vector3.ZERO
	for frame in range(345):
		scene._update_observer_presence(1.0 / 60.0)
	check(scene.observer_state in [scene.ObserverState.DISENGAGING, scene.ObserverState.RECOVERY], "Quiet player escapes after breaking sight")
	check(not scene.observer_defeated, "Escaping cannot trigger defeat")
	report["escape_state"] = scene.ObserverState.keys()[scene.observer_state]
	check(scene._observer_grounded_position(Vector3(33, 0, -29)) == Vector3.INF, "Low crawl duct rejects the creature")
	report["crawlspace_refuge"] = true
	report["pass"] = failures.is_empty()
	report["failures"] = failures
	var file := FileAccess.open("res://artifacts/observer-overhaul/behavior-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("OBSERVER AUDIT ", JSON.stringify(report))
	for node in scene.find_children("*", "AudioStreamPlayer", true, false):
		node.stop()
		node.stream = null
	for node in scene.find_children("*", "AudioStreamPlayer3D", true, false):
		node.stop()
		node.stream = null
	scene.audio_playback = null
	scene.spatial_ambience_sources.clear()
	scene.observer_audio.playback = null
	player.audio_playback = null
	player.footstep_playback = null
	scene.free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
