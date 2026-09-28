extends SceneTree
## Run: godot --headless --path . --script tests/level_geometry_audit.gd
## Physics-based reachability audit; does not modify any scene or gameplay system.
const SPACING = 0.4
const ORIGIN = -51.6
const WIDTH = 259
var scene: Node3D
var cells = {}
var reached = {}
var failures: Array[String] = []
var state: PhysicsDirectSpaceState3D
var player: CharacterBody3D
var query = PhysicsShapeQueryParameters3D.new()
var capsule = CapsuleShape3D.new()

func _initialize() -> void:
 call_deferred("audit")

func audit() -> void:
 scene = load("res://main.tscn").instantiate()
 root.add_child(scene)
 current_scene = scene
 player = scene.get_node("Gameplay/Player")
 scene.set_process(false)
 player.set_physics_process(false)
 player.set_process(false)
 await physics_frame
 await physics_frame
 state = scene.get_world_3d().direct_space_state
 capsule.radius = 0.28
 query.shape = capsule
 query.collision_mask = 1
 query.exclude = [player.get_rid()]
 var ray = PhysicsRayQueryParameters3D.new()
 ray.collision_mask = 1
 ray.exclude = [player.get_rid()]
 # Test the actual player capsule, including crouch clearance and lower service floor.
 for iz in range(WIDTH):
  for ix in range(WIDTH):
   var x = ORIGIN + ix * SPACING
   var z = ORIGIN + iz * SPACING
   ray.from = Vector3(x,1.06,z)
   ray.to = Vector3(x,-1.6,z)
   var hit = state.intersect_ray(ray)
   if hit.is_empty() or hit.normal.y < 0.7: continue
   var foot: Vector3 = hit.position + Vector3(0,0.015,0)
   var posture = 0
   for height in [1.55,0.95]:
    capsule.height = height
    query.transform = Transform3D(Basis.IDENTITY,foot+Vector3(0,height/2,0))
    if state.intersect_shape(query,1).is_empty():
     posture = 1 if height > 1.0 else 2
     break
   if posture: cells[Vector2i(ix,iz)] = {"p":foot,"crouch":posture==2}
 var start = key_for(player.position)
 if not cells.has(start):
  failures.append("Spawn capsule has no clearance")
 else:
  var queue: Array[Vector2i] = [start]
  reached[start] = true
  var index = 0
  while index < queue.size():
   var cell = queue[index]
   index += 1
   for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var next: Vector2i = cell+d
    if reached.has(next) or not cells.has(next): continue
    if absf(cells[cell].p.y-cells[next].p.y)>0.42: continue
    # Swept crouch capsule prevents a grid edge from skipping thin collision walls.
    capsule.height=0.95
    var sweep_start: Vector3 = cells[cell].p
    sweep_start.y=maxf(cells[cell].p.y,cells[next].p.y)+0.03
    query.transform=Transform3D(Basis.IDENTITY,sweep_start+Vector3(0,0.475,0))
    query.motion=cells[next].p-cells[cell].p
    query.motion.y=0.0
    var sweep = state.cast_motion(query)
    query.motion=Vector3.ZERO
    if sweep[0] < 0.99: continue
    reached[next]=true
    queue.append(next)
 var targets = []
 for group in ["fuel_can","observer_anchor"]:
  for n in get_nodes_in_group(group):
   var nearest = nearest_reachable(n.global_position)
   var tolerance = 0.84 if group=="fuel_can" else 0.6
   var ok: bool = nearest.distance <= tolerance
   if group=="fuel_can":
    var pickup_shape=SphereShape3D.new()
    pickup_shape.radius=0.10
    var pickup_query=PhysicsShapeQueryParameters3D.new()
    pickup_query.shape=pickup_shape
    pickup_query.transform=Transform3D(Basis.IDENTITY,n.global_position+Vector3(0,0.12,0))
    pickup_query.exclude=[player.get_rid()]
    ok=ok and state.intersect_shape(pickup_query,1).is_empty()
   elif str(n.role) not in ["doorway","intersection","dead_end","pillar","obscured","distant"]:
    failures.append("Unsupported Observer role: "+str(n.role))
   if group=="observer_anchor":
    capsule.height = 1.8
    query.transform=Transform3D(Basis.IDENTITY,n.global_position+Vector3(0,0.92,0))
    ok = ok and state.intersect_shape(query,1).is_empty()
   targets.append({"name":str(n.name),"kind":group,"ok":ok,"distance":nearest.distance,"at":vec(n.global_position)})
   if not ok: failures.append("Unreachable or obstructed "+str(n.name)+" distance="+str(nearest.distance))
 var sector_checks = {
  "reception":Vector3(1.2,0,3.2),"north":Vector3(6,0,-30),
  "forest":Vector3(-35,0,3),"crawlspace":Vector3(33,0,-29),
  "sump":Vector3(-4.8,-1.2,36),"nowhere":Vector3(49,0,38),
  "archive":Vector3(-44.2,0,31.8)}
 for label in sector_checks:
  if nearest_reachable(sector_checks[label]).distance>0.65: failures.append("Sector unreachable: "+label)
 var fixture_positions = {}
 for n in get_nodes_in_group("troffer_fixture"):
  var key = str(n.global_position.snapped(Vector3.ONE*0.01))
  if fixture_positions.has(key): failures.append("Duplicate fixture at "+key)
  fixture_positions[key]=true
  if n.get_node_or_null("SpotLight")==null or n.get_node_or_null("FillLight")==null: failures.append("Unbound fixture "+str(n.name))
 var map = []
 for key in cells:
  map.append([key.x,key.y,cells[key].p.y,cells[key].crouch,reached.has(key)])
 var result = {"pass":failures.is_empty(),"failures":failures,"targets":targets,"reachable_cells":reached.size(),"walkable_cells":cells.size(),"fixtures":fixture_positions.size(),"cells":map}
 var output = FileAccess.open("/tmp/cliche-geometry-audit.json",FileAccess.WRITE)
 output.store_string(JSON.stringify(result))
 print("GEOMETRY AUDIT: ",reached.size()," reachable cells; ",fixture_positions.size()," fixtures; ",targets.size()," gameplay targets")
 for failure in failures: print("FAIL: ",failure)
 if failures.is_empty(): print("PASS: all sectors, pickups and anchors reachable; no duplicate fixtures")
 for audio_node in scene.find_children("*", "AudioStreamPlayer", true, false): audio_node.stop()
 for audio_node in scene.find_children("*", "AudioStreamPlayer3D", true, false): audio_node.stop()
 await create_timer(0.05).timeout
 scene.set_process(false)
 player.set_process(false)
 player.set_physics_process(false)
 scene.audio_playback=null
 scene.spatial_ambience_sources.clear()
 player.audio_playback=null
 player.footstep_playback=null
 for audio_node in scene.find_children("*", "AudioStreamPlayer",true,false): audio_node.stream=null
 for audio_node in scene.find_children("*", "AudioStreamPlayer3D",true,false): audio_node.stream=null
 scene.free()
 query = null
 capsule = null
 await process_frame
 quit(0 if failures.is_empty() else 1)

func key_for(p: Vector3) -> Vector2i:
 return Vector2i(roundi((p.x-ORIGIN)/SPACING),roundi((p.z-ORIGIN)/SPACING))

func nearest_reachable(p: Vector3) -> Dictionary:
 var distance = INF
 var nearest = Vector3.ZERO
 # Pickups may sit on a low counter: horizontal approach is sufficient for their Area3D.
 for dx in range(-4,5):
  for dz in range(-4,5):
   var key = key_for(p)+Vector2i(dx,dz)
   if not reached.has(key): continue
   var q: Vector3 = cells[key].p
   var d = Vector2(p.x-q.x,p.z-q.z).length()
   if d < distance:
    distance=d
    nearest=q
 return {"distance":distance,"position":vec(nearest)}

func vec(v: Vector3) -> Array:
 return [v.x,v.y,v.z]
