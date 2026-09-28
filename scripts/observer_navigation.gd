extends RefCounted
## Collision-derived routes: supports the authored ramps and low door lintels.
## A short capsule represents the creature's hunched posture; crawl ducts exclude it.
const STEP := 0.65
const LOW := -51.35
const WIDTH := 159
const HEIGHT := 2.0
const RADIUS := 0.32
var graph := AStar3D.new()
var cells: Dictionary = {}
var cursor := 0
var connection_cursor := 0
var keys: Array = []
var ready := false
var space: PhysicsDirectSpaceState3D
var excluded: Array[RID] = []
var shape := CapsuleShape3D.new()
var query := PhysicsShapeQueryParameters3D.new()

func setup(world: World3D, player_rid: RID) -> void:
	space = world.direct_space_state
	excluded = [player_rid]
	shape.radius = RADIUS
	shape.height = HEIGHT
	query.shape = shape
	query.collision_mask = 1
	query.exclude = excluded

func bake_slice(budget_usec: int = 3500) -> void:
	if ready: return
	var until := Time.get_ticks_usec() + budget_usec
	while Time.get_ticks_usec() < until:
		if cursor < WIDTH * WIDTH:
			var key := Vector2i(cursor % WIDTH, cursor / WIDTH)
			cursor += 1
			var point := ground(Vector3(LOW + key.x * STEP, 0.0, LOW + key.y * STEP), true)
			if point != Vector3.INF:
				cells[key] = point
				graph.add_point(_id(key), point)
			if cursor == WIDTH * WIDTH: keys = cells.keys()
		elif connection_cursor < keys.size():
			var key: Vector2i = keys[connection_cursor]
			connection_cursor += 1
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next: Vector2i = key + direction
				if cells.has(next) and can_cross(cells[key], cells[next]):
					graph.connect_points(_id(key), _id(next))
		else:
			ready = true
			print("[Observer] Navigation ready: %d floor cells" % graph.get_point_count())
			return

func _id(key: Vector2i) -> int:
	return key.y * WIDTH + key.x

func ground(candidate: Vector3, whole_floor: bool = false) -> Vector3:
	var top := Vector3(candidate.x, 1.15 if whole_floor else candidate.y + 0.60, candidate.z)
	var bottom := Vector3(candidate.x, -1.65 if whole_floor else candidate.y - 0.65, candidate.z)
	var ray := PhysicsRayQueryParameters3D.create(top, bottom, 1, excluded)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.7: return Vector3.INF
	var foot: Vector3 = hit.position + Vector3(0, 0.018, 0)
	if not whole_floor and absf(foot.y - candidate.y) > 0.48: return Vector3.INF
	if not clearance(foot, HEIGHT): return Vector3.INF
	return foot

func clearance(foot: Vector3, height: float) -> bool:
	shape.height = height
	query.motion = Vector3.ZERO
	query.transform = Transform3D(Basis.IDENTITY, foot + Vector3(0, height * 0.5, 0))
	return space.intersect_shape(query, 1).is_empty()

func can_cross(from: Vector3, to: Vector3) -> bool:
	if absf(from.y - to.y) > 0.48: return false
	shape.height = HEIGHT
	var origin := from
	origin.y = maxf(from.y, to.y) + 0.035
	query.transform = Transform3D(Basis.IDENTITY, origin + Vector3(0, HEIGHT * 0.5, 0))
	query.motion = Vector3(to.x - from.x, 0, to.z - from.z)
	var sweep := space.cast_motion(query)
	query.motion = Vector3.ZERO
	return sweep[0] > 0.995

func nearest(point: Vector3) -> int:
	var center := Vector2i(roundi((point.x - LOW) / STEP), roundi((point.z - LOW) / STEP))
	var best := -1
	var best_distance := 1.6
	for x in range(-2, 3):
		for z in range(-2, 3):
			var key := center + Vector2i(x, z)
			if not cells.has(key): continue
			var candidate: Vector3 = cells[key]
			var distance := candidate.distance_to(point)
			if distance < best_distance and can_cross(point, candidate):
				best_distance = distance
				best = _id(key)
	return best

func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not ready: return PackedVector3Array()
	var start := nearest(from)
	var finish := nearest(to)
	if start < 0 or finish < 0: return PackedVector3Array()
	return graph.get_point_path(start, finish)

func reachable(from: Vector3, to: Vector3) -> bool:
	return not route(from, to).is_empty()
