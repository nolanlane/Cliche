extends SceneTree
## Run geometry audit first, then:
## godot --headless --path . --fixed-fps 60 --script tests/level_walkthrough.gd
## Drives the unchanged player controller with input actions along audited floor cells.
var scene: Node3D
var player: CharacterBody3D
var cells = {}
var graph = AStar3D.new()
var targets = []
var target_index = -1
var path = PackedVector3Array()
var path_index = 0
var ready_to_walk = false
var elapsed = 0.0
var last_progress_time = 0.0
var last_progress_position = Vector3.ZERO
var failures: Array[String] = []
var visited: Array[String] = []
const STEP = 0.4
const LOW = -51.6
const WIDTH = 259

func _initialize(): call_deferred("setup")
func setup():
 if not FileAccess.file_exists("/tmp/cliche-geometry-audit.json"):
  push_error("Run level_geometry_audit.gd first")
  quit(1)
  return
 var audit = JSON.parse_string(FileAccess.get_file_as_string("/tmp/cliche-geometry-audit.json"))
 if not audit["pass"]:
  push_error("Geometry audit must pass before walking")
  quit(1)
  return
 for row in audit.cells:
  if not row[4]: continue
  var k=Vector2i(int(row[0]),int(row[1]))
  var p=Vector3(LOW+k.x*STEP,float(row[2]),LOW+k.y*STEP)
  cells[k]={"p":p,"crouch":row[3]}
  graph.add_point(id(k),p)
 for k in cells:
  for d in [Vector2i.RIGHT,Vector2i.DOWN]:
   var other=k+d
   if cells.has(other) and absf(cells[k].p.y-cells[other].p.y)<0.42:
    graph.connect_points(id(k),id(other))
 scene=load("res://main.tscn").instantiate()
 root.add_child(scene)
 current_scene=scene
 player=scene.get_node("Gameplay/Player")
 # Keep the architecture/traversal test deterministic while leaving player physics intact.
 scene.set_process(false)
 targets=[
  ["Reception counter",Vector3(-4.2,0,0.8)],
  ["North office pickup",Vector3(-3.5,0,-29.5)],
  ["North deep dead end",Vector3(-5.4,0,-48.4)],
  ["North pocket pickup",Vector3(-11.7,0,-49)],
  ["East office pickup",Vector3(15.8,0,-20)],
  ["Crawl entry",Vector3(22,0,-23.5)],
  ["Crawl alcove pickup",Vector3(33,0,-29)],
  ["Crawl northern elbow",Vector3(44.2,0,-34)],
  ["Crawl return hatch",Vector3(17,0,-43.5)],
  ["Forest column edge",Vector3(-39.2,0,-17.2)],
  ["Forest pickup",Vector3(-36.9,0,7.1)],
  ["Forest west pickup",Vector3(-20.5,0,2)],
  ["Archive stacks",Vector3(-44.2,0,31.8)],
  ["Archive pickup",Vector3(-46.8,0,47.8)],
  ["Sump ramp down",Vector3(0,-1.2,30)],
  ["Sump pickup",Vector3(-13,-1.2,26.5)],
  ["Sump pump doorway",Vector3(-9,-1.2,40)],
  ["Sump rear service bay",Vector3(4.2,-1.2,45.8)],
  ["Sump ramp up",Vector3(0,0,20)],
  ["East connecting hall",Vector3(19.5,0,9)],
  ["Folded hall approach",Vector3(22.5,0,24)],
  ["Nowhere pickup recess",Vector3(33.65,0,36)],
  ["Nowhere end",Vector3(50.3,0,37.95)],
  ["Return to reception",Vector3(1.2,0,3.2)]]
 await physics_frame
 await physics_frame
 last_progress_position=player.position
 ready_to_walk=true
 next_target()

func id(k): return k.y*WIDTH+k.x
func cell_for(p): return Vector2i(roundi((p.x-LOW)/STEP),roundi((p.z-LOW)/STEP))
func closest(p):
 var best=-1
 var dist=INF
 for dx in range(-5,6):
  for dz in range(-5,6):
   var k=cell_for(p)+Vector2i(dx,dz)
   if not cells.has(k): continue
   var q: Vector3=cells[k].p
   var d=Vector2(q.x-p.x,q.z-p.z).length()+absf(q.y-p.y)*0.25
   if d<dist: dist=d; best=id(k)
 return best
func next_target():
 target_index+=1
 if target_index==targets.size():
  finish.call_deferred()
  ready_to_walk=false
  return
 var start=closest(player.position)
 var goal=closest(targets[target_index][1])
 if start<0 or goal<0:
  fail("Missing route cell")
  return
 path=graph.get_point_path(start,goal)
 path_index=0
 if path.is_empty(): fail("Empty route"); return
 last_progress_time=elapsed
 last_progress_position=player.position
 print("WALK ",targets[target_index][0]," via ",path.size()," cells")

func _physics_process(delta):
 if not ready_to_walk: return false
 elapsed+=delta
 if elapsed-last_progress_time>4.0:
  if player.position.distance_to(last_progress_position)<0.3:
   fail("Stalled at "+str(player.position)+" toward "+str(path[path_index]))
   return false
  last_progress_position=player.position
  last_progress_time=elapsed
 var goal=path[path_index]
 var horizontal=Vector2(goal.x-player.position.x,goal.z-player.position.z)
 if horizontal.length()<0.13:
  path_index+=1
  if path_index>=path.size():
   Input.action_release("move_forward")
   visited.append(targets[target_index][0])
   print("REACHED ",targets[target_index][0]," at ",player.position)
   next_target()
   return false
  goal=path[path_index]
  horizontal=Vector2(goal.x-player.position.x,goal.z-player.position.z)
 var k=cell_for(goal)
 var here=cell_for(player.position)
 var crouch=(cells.has(k) and cells[k].crouch) or (cells.has(here) and cells[here].crouch)
 if crouch: Input.action_press("crouch")
 else: Input.action_release("crouch")
 player.rotation.y=atan2(-horizontal.x,-horizontal.y)
 Input.action_press("move_forward")
 if player.position.y < -3: fail("Fell below floor")

 return false

func fail(reason):
 failures.append(str(targets[target_index][0])+": "+reason)
 print("FAIL: ",failures.back())
 ready_to_walk=false
 finish.call_deferred()

func finish():
 Input.action_release("move_forward")
 Input.action_release("crouch")
 var remaining=[]
 for can in get_nodes_in_group("fuel_can"):
  if not can.is_collected: remaining.append(str(can.name))
 if not remaining.is_empty(): failures.append("Uncollected fuel cans: "+str(remaining))
 var report={"pass":failures.is_empty(),"visited":visited,"failures":failures,"simulated_seconds":elapsed,"remaining_pickups":remaining}
 var f=FileAccess.open("/tmp/cliche-walkthrough.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(report,"  "))
 print("WALKTHROUGH ","PASS" if failures.is_empty() else "FAIL"," ",visited.size(),"/",targets.size()," stops; ",elapsed," seconds")
 for audio_node in scene.find_children("*", "AudioStreamPlayer",true,false): audio_node.stop()
 for audio_node in scene.find_children("*", "AudioStreamPlayer3D",true,false): audio_node.stop()
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
 await create_timer(0.1).timeout
 quit(0 if failures.is_empty() else 1)
