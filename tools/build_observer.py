"""Reproducible creature sculpt and skinning. Run with Blender --background --python."""
import bpy
import bmesh
import math
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

def v(p):
    # Author in game coordinates (Y up, -Z forward), convert to Blender.
    return Vector((p[0], -p[2], p[1]))

parts = []
bones = []
def bone(name, a, b, parent=None):
    bones.append((name, v(a), v(b), parent))

def ellipsoid(name, p, scale):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48 if name == "Skull" else 24, ring_count=32 if name == "Skull" else 16, location=v(p))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (scale[0], scale[2], scale[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if name == "Foot":
        for vertex in obj.data.vertices:
            vertex.co.z = max(vertex.co.z, -.042)
    parts.append(obj)
    return obj

def tube(name, points, radii, depth=1.0, sides=12):
    verts, faces = [], []
    points = [v(p) for p in points]
    for i, (p, radius) in enumerate(zip(points, radii)):
        tangent = (points[min(i+1, len(points)-1)] - points[max(i-1, 0)]).normalized()
        right = tangent.cross(Vector((0, 1, 0))).normalized()
        if right.length < 0.1:
            right = tangent.cross(Vector((1, 0, 0))).normalized()
        front = tangent.cross(right).normalized()
        for j in range(sides):
            angle = j * math.tau / sides
            verts.append(p + right * math.cos(angle) * radius + front * math.sin(angle) * radius * depth)
    for i in range(len(points)-1):
        for j in range(sides):
            a = i*sides+j
            b = i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    parts.append(obj)
    return obj

bone("Pelvis", (0,1.15,0), (0,1.40,0))
bone("Spine", (0,1.40,0), (0,1.95,0), "Pelvis")
bone("Neck", (0,1.95,0), (0,2.23,-.015), "Spine")
bone("Head", (0,2.23,-.015), (0,2.62,-.035), "Neck")
ellipsoid("Pelvis", (0,1.255,.015), (.162,.137,.113))
tube("Trunk", [(0,1.22,0),(0,1.37,.015),(0,1.49,.025),(0,1.64,.015),(0,1.79,0),(0,1.92,.01),(0,2.015,.025)],
     [.165,.143,.147,.19,.232,.21,.08], .60, 24)
ellipsoid("Chest", (0,1.79,.025), (.220,.24,.135))
tube("Neck", [(0,1.96,.02),(0,2.06,.01),(0,2.18,-.01),(0,2.26,-.025)], [.085,.065,.072,.095], .8, 16)
# Ribs lie under the skin and merge into the chest, avoiding exposed ladder rungs.
for i in range(6):
    y = 1.57+i*.060
    width = .185 + math.sin(i/5*math.pi)*.045
    for side in [-1,1]:
        depth = [.080,.100,.118,.130,.140,.140][i]
        points = [(side*width*.15,y,-depth),(side*width*.55,y+.018,-depth*.86),(side*width*.90,y+.036,-depth*.46),(side*width,y+.05,.004)]
        tube("SubcutaneousRib", points, [.010,.012,.012,.008], .72, 8)

for side, suffix in [(-1,"L"),(1,"R")]:
    shoulder = (side*.255,1.915,.025)
    elbow = (side*.345,1.34,.045)
    wrist = (side*.43,.76,-.025)
    palm = (side*.455,.635,-.035)
    hip = (side*.115,1.245,.015)
    knee = (side*.145,.66,-.04)
    ankle = (side*.19,.13,.045)
    bone("Arm"+suffix, shoulder, elbow, "Spine")
    bone("Forearm"+suffix, elbow, wrist, "Arm"+suffix)
    bone("Hand"+suffix, wrist, (side*.455,.52,-.04), "Forearm"+suffix)
    bone("Thigh"+suffix, hip, knee, "Pelvis")
    bone("Shin"+suffix, knee, ankle, "Thigh"+suffix)
    bone("Foot"+suffix, ankle, (side*.19,.06,-.15), "Shin"+suffix)
    tube("Clavicle", [(0,2.015,.01),(side*.16,1.96,-.014),shoulder], [.057,.059,.073], .82)
    ellipsoid("Deltoid", shoulder, (.084,.10,.081))
    tube("UpperArm", [shoulder,(side*.285,1.78,.025),(side*.32,1.55,.035),elbow], [.067,.075,.046,.045], .84)
    ellipsoid("Elbow", elbow, (.048,.058,.048))
    tube("Forearm", [elbow,(side*.37,1.17,.035),(side*.41,.95,.008),wrist], [.046,.057,.036,.027], .83)
    ellipsoid("Palm", palm, (.068,.16,.038))
    tube("Wrist", [wrist,palm], [.028,.049], .70)
    tube("Thigh", [hip,(side*.123,1.09,.015),(side*.138,.85,-.01),knee], [.081,.087,.057,.047], .86)
    ellipsoid("Knee", knee, (.052,.065,.052))
    tube("Shin", [knee,(side*.16,.49,.009),(side*.184,.24,.044),ankle], [.043,.054,.028,.028], .87)
    ellipsoid("Foot", (side*.19,.067,-.072), (.052,.064,.166))

# Union the large anatomy before adding finer hands and skull.
bpy.ops.object.select_all(action="DESELECT")
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
body = bpy.context.object
body.name = "ObserverFlesh"
remesh = body.modifiers.new("Continuous anatomy", "REMESH")
remesh.mode = "VOXEL"
remesh.voxel_size = .010
remesh.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth = body.modifiers.new("Skin tension", "SMOOTH")
smooth.factor = .65
smooth.iterations = 4
bpy.ops.object.modifier_apply(modifier=smooth.name)
parts = [body]

# Curved, separated tapering fingers. Their roots intersect the palm.
for side, suffix in [(-1,"L"),(1,"R")]:
    for i in range(5):
        spread = (i-2)*.030
        x = side*(.455+spread)
        top = .565 + (.055 if i == 0 else 0)
        length = [.26,.37,.41,.37,.30][i]
        tipx = x+side*spread*.75
        points = [(x,top,-.045),(x+side*spread*.3,top-length*.38,-.055),
                  (tipx,top-length*.73,-.10),(tipx-side*.018,top-length,-.16)]
        tube("Finger"+suffix+str(i), points, [.016,.012,.008,.0008], .85, 10)
        bone("Finger"+suffix+str(i), points[0], points[-1], "Hand"+suffix)

head = ellipsoid("Skull", (0,2.385,-.025), (.144,.218,.145))
# Scalp narrows into the jaw; sockets are depressions in the actual mesh.
for vert in head.data.vertices:
    x, forward, z = vert.co
    lower = max(0,min(1,(-z+.03)/.24))
    vert.co.x *= 1.0-.25*lower
    if forward > 0:
        socket = sum(math.exp(-((x-s*.063)/.038)**2-((z-.044)/.055)**2) for s in [-1,1])
        mouth = math.exp(-(x/.031)**2-((z+.103)/.065)**2)
        cheek = math.exp(-((abs(x)-.094)/.028)**2-((z+.043)/.042)**2)
        vert.co.y -= (.040*socket+.017*mouth+.012*cheek)*min(1,forward/.06)
        vert.co.y += .007*math.exp(-(x/.020)**2-((z+.012)/.070)**2)

bpy.ops.object.select_all(action="DESELECT")
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for poly in body.data.polygons: poly.use_smooth = True
decimate = body.modifiers.new("Runtime topology", "DECIMATE")
decimate.ratio = .52
bpy.ops.object.modifier_apply(modifier=decimate.name)

body.data.validate(clean_customdata=True)
bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(body.data)
bm.free()

material = bpy.data.materials.new("Charcoal skin")
material.diffuse_color = (.014,.016,.017,1)
material.use_nodes = True
bsdf = material.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (.014,.016,.017,1)
bsdf.inputs["Roughness"].default_value = .68
body.data.materials.clear()
body.data.materials.append(material)

armature = bpy.data.armatures.new("ObserverSkeleton")
rig = bpy.data.objects.new("ObserverRig", armature)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
body.select_set(False)
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for name,a,b,parent in bones:
    edit = armature.edit_bones.new(name)
    edit.head, edit.tail = a,b
    if parent: edit.parent = armature.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")
groups = {name:body.vertex_groups.new(name=name) for name,_,_,_ in bones}
def distance_to_bone(point,a,b):
    d=b-a
    t=max(0,min(1,(point-a).dot(d)/d.length_squared))
    return (point-(a+d*t)).length
for vert in body.data.vertices:
    p=vert.co
    distances = sorted((distance_to_bone(p,a,b),name) for name,a,b,_ in bones)
    near=distances[:3]
    # Preserve anatomical domains where arms lie beside the trunk.
    if p.z > 2.20: near=[x for x in distances if x[1] in ["Head","Neck"]][:2]
    elif p.z < .23: near=[x for x in distances if x[1].startswith(("Foot","Shin","Finger","Hand"))][:2]
    weights=[1/max(.012,d)**4 for d,n in near]
    total=sum(weights)
    for (_,name),w in zip(near,weights): groups[name].add([vert.index],w/total,"REPLACE")
modifier=body.modifiers.new("Creature skeleton","ARMATURE")
modifier.object=rig
body.parent=rig
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
output=ROOT/"assets/observer/observer.glb"
bpy.ops.export_scene.gltf(filepath=str(output),export_format="GLB",use_selection=True,export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"tools/observer_source/observer.blend"))
print("OBSERVER EXPORTED",len(body.data.vertices),"vertices",len(body.data.polygons),"faces",len(bones),"bones",output)
