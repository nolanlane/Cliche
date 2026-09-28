extends SceneTree
## Rendered animation review: idle, planted creeping gait, then a real chase/capture.
var scene: Node3D
var frame := 0
var ready := false

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.player.set_process(false)
	await physics_frame
	await physics_frame
	while not scene.observer_navigation.ready:
		scene.observer_navigation.bake_slice(30000)
	scene.debug_observer_scenario("portrait")
	scene.player.global_position = Vector3(1.2, 0.018, -1.0)
	scene.observer.global_position = Vector3(1.0, 0.018, -3.8)
	ready = true

func _process(delta: float) -> bool:
	if not ready: return false
	frame += 1
	if frame < 49:
		scene.observer.update_pose(delta, 0.0, 0.15, false, headroom())
	elif frame < 145:
		if frame == 49:
			scene.observer.global_position = Vector3(1.0, 0.018, -5.0)
			scene.player.global_position = Vector3(1.2, 0.018, 0.0)
		scene.observer.global_position.z += 0.65 * delta
		scene.observer.update_pose(delta, 0.65, 0.28, false, headroom())
	else:
		if frame == 145:
			scene.debug_observer_scenario("chase")
		if not scene.observer_defeated: scene._update_observer_presence(delta)
	if frame in [36, 112, 183]:
		capture.call_deferred(frame)
	if frame >= 248:
		quit()
	return false

func capture(number: int) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://artifacts/observer-overhaul/review-%03d.png" % number)

func headroom() -> float:
	return 0.0 if scene.observer_navigation.clearance(scene.observer.global_position, 2.30) else 1.0
