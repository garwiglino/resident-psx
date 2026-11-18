"""Blender + standalone Godot integration; synthetic assets and isolated output."""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/blender_addons"))
import resident_psx_exporter as addon

fixture = Path(tempfile.mkdtemp(prefix="psx-animated-export-"))
for relative in addon.bridge.FILES:
    destination = fixture / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / relative, destination)
(fixture / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Animated Export Test"\n', encoding="utf-8")
addon.register()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.scene.render.fps = 24
root = bpy.data.objects.new("MachineRoot", None)
bpy.context.collection.objects.link(root)
root.location = (10, -6, 2)
root.rotation_euler.z = .35
root.scale = (1.2, 1.2, 1.2)
rig_data = bpy.data.armatures.new("MachineRigData")
rig = bpy.data.objects.new("MachineRig", rig_data)
bpy.context.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
base = rig.data.edit_bones.new("body")
base.head, base.tail = (0, 0, 0), (0, 0, .5)
hinge = rig.data.edit_bones.new("hinge")
hinge.head, hinge.tail, hinge.parent = (.2, 0, .6), (.2, 0, .9), base
for index, x in enumerate((-.2, .2)):
    bone = rig.data.edit_bones.new("socket_%d" % index)
    bone.head, bone.tail, bone.parent = (x, -.1, .3), (x, -.1, .4), base
    bone.use_deform = False
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.mesh.primitive_cube_add(size=.4)
mesh = bpy.context.object
mesh.name = "PanelSkinned"
mesh.parent = root
mesh.location = (.1, 0, .65)
modifier = mesh.modifiers.new("Skin", "ARMATURE")
modifier.object = rig
group = mesh.vertex_groups.new(name="hinge")
group.add(list(range(len(mesh.data.vertices))), 1, "REPLACE")
image = bpy.data.images.new("Original512Atlas", width=512, height=512)
image.generated_color = (.4, .6, .2, 1)
material = bpy.data.materials.new("OriginalPaint")
material.use_nodes = True
texture = material.node_tree.nodes.new("ShaderNodeTexImage")
texture.image = image
material.node_tree.links.new(texture.outputs["Color"], material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
mesh.data.materials.append(material)
override = material.copy()
override.name = "OriginalObjectOverride"
mesh.material_slots[0].link = "OBJECT"
mesh.material_slots[0].material = override
for polygon in mesh.data.polygons:
    for index, coordinate in zip(polygon.loop_indices, ((.125, .125), (.375, .125), (.375, .375), (.125, .375))):
        mesh.data.uv_layers.active.data[index].uv = coordinate
for index in range(2):
    marker = bpy.data.objects.new("point_%d" % index, None)
    bpy.context.collection.objects.link(marker)
    marker.parent, marker.parent_type, marker.parent_bone = rig, "BONE", "socket_%d" % index
    marker.empty_display_type = "ARROWS"
camera_data = bpy.data.cameras.new("InspectionCameraData")
camera = bpy.data.objects.new("InspectionCamera", camera_data)
bpy.context.collection.objects.link(camera)
camera.parent = root
camera.location = (0, -2, 1)
pose = rig.pose.bones["hinge"]
pose.rotation_mode = "XYZ"
pose.rotation_euler.y = 0
pose.keyframe_insert("rotation_euler", frame=1)
pose.rotation_euler.y = .8
pose.keyframe_insert("rotation_euler", frame=25)
rig.animation_data.action.name = "open_panel"
scene = bpy.context.scene
scene.frame_start, scene.frame_end = 1, 25
scene.frame_set(7)
bpy.context.view_layer.update()
for obj in bpy.context.selected_objects:
    obj.select_set(False)
root.select_set(True)
bpy.context.view_layer.objects.active = root
root.psx_export.asset_type = "animated"
root.psx_export.asset_name = "generic_machine"
source_mesh = mesh.data
source_slots = [(slot.link, slot.material) for slot in mesh.material_slots]
source_uv = [tuple(row.uv) for row in source_mesh.uv_layers.active.data]
source_matrices = {obj.name: tuple(tuple(row) for row in obj.matrix_world) for obj in root.children_recursive + [root]}
source_action = rig.animation_data.action
expected = {}
expected_markers = {}
origin = root.matrix_world.translation.copy()
for frame in (1, 7, 13, 25):
    scene.frame_set(frame)
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    geometry = evaluated.to_mesh()
    points = []
    for vertex in geometry.vertices:
        p = evaluated.matrix_world @ vertex.co - origin
        points.append([p.x, p.z, -p.y])
    expected[str(frame)] = points
    expected_markers[str(frame)] = []
    for index in range(2):
        p = bpy.data.objects["point_%d" % index].matrix_world.translation - origin
        expected_markers[str(frame)].append([p.x, p.z, -p.y])
    evaluated.to_mesh_clear()
scene.frame_set(7)
before_counts = (len(bpy.data.meshes), len(bpy.data.materials), len(bpy.data.images))
request, payload = addon.exporter.build_payload(bpy.context, fixture / "request", "animated", "generic_machine")
assert mesh.data == source_mesh
assert [(slot.link, slot.material) for slot in mesh.material_slots] == source_slots
assert source_uv == [tuple(row.uv) for row in source_mesh.uv_layers.active.data]
assert source_action == rig.animation_data.action and scene.frame_current == 7
assert before_counts == (len(bpy.data.meshes), len(bpy.data.materials), len(bpy.data.images))
assert all(tuple(tuple(row) for row in bpy.data.objects[name].matrix_world) == matrix for name, matrix in source_matrices.items())
assert all("resident_psx_source_object" not in obj for obj in root.children_recursive + [root])
assert all(not row["texture"] or (fixture / "request" / row["texture"]).is_file() for row in payload["materials"])
conversion = addon.bridge.create(fixture, fixture / "staging")


def convert(path):
    result = subprocess.run([addon.DEFAULT_GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(conversion), "--script", "res://tools/import_blender_asset.gd", "--", "--input", str(path)], capture_output=True, text=True, timeout=60)
    (ROOT / "docs/animated-export-converter.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    assert result.returncode == 0 and "BLENDER_PSX_EXPORT_OK" in result.stdout, result.stdout + result.stderr
    return json.loads(path.with_suffix(".result.json").read_text(encoding="utf-8"))


first = convert(request)
assert not first["scene_preserved"]
output = fixture / "assets/props/generic_machine"
info = json.loads((output / "source.json").read_text(encoding="utf-8"))
assert "point_0" in info["nodes"] and "point_1" in info["nodes"] and "PanelSkinned" in info["nodes"]
assert all("socket_%d" % index in info["skeletons"][0]["bones"] for index in range(2))
(conversion / "expected.json").write_text(json.dumps({"points": expected, "markers": expected_markers, "info": info}), encoding="utf-8")
verify = conversion / "verify.gd"
verify.write_text('''extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    create_timer(15).timeout.connect(func():push_error("Animation verification timed out");quit(2))
    var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"))
    var model: Node3D=load(data.info.model_resource).instantiate();root.add_child(model)
    var mesh: MeshInstance3D=model.get_node(data.info.nodes.PanelSkinned)
    var sk: Skeleton3D=mesh.get_node(mesh.skeleton)
    var player: AnimationPlayer=model.get_node(data.info.animations[0].player)
    var clip: String=data.info.animations[0].name
    assert(abs(player.get_animation(clip).length-1.0)<.001)
    player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;player.play(clip)
    var maximum := 0.0
    for frame in [1,7,13,25]:
        player.seek(float(frame-1)/24.0,true,true)
        for attach in model.find_children("*","BoneAttachment3D",true,false):attach.on_skeleton_update()
        for index in 2:
            var marker: Node3D=model.get_node(data.info.nodes["point_%d" % index]);var row: Array=data.markers[str(frame)][index]
            assert(marker.global_position.distance_to(Vector3(row[0],row[1],row[2]))<.0002,"Bone-attached marker differs from Blender")
        for surface in mesh.mesh.get_surface_count():
            var material: StandardMaterial3D=mesh.get_active_material(surface)
            assert(material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and material.specular_mode==BaseMaterial3D.SPECULAR_DISABLED)
            assert(material.albedo_texture.get_width()<=256 and material.albedo_texture.get_height()<=256)
            assert(material.cull_mode==BaseMaterial3D.CULL_DISABLED)
            var arrays := mesh.mesh.surface_get_arrays(surface)
            var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
            assert(uvs.has(Vector2(0,0)) and uvs.has(Vector2(1,1)),"Cropped page UVs must cover the source texels without resizing")
            var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
            var stride: int=bones.size()/vertices.size()
            for vertex in vertices.size():
                var actual := Vector3.ZERO
                for slot in stride:
                    var bind: int=bones[vertex*stride+slot];var weight: float=weights[vertex*stride+slot]
                    if weight<=0:continue
                    var bone := mesh.skin.get_bind_bone(bind)
                    if bone<0:bone=sk.find_bone(mesh.skin.get_bind_name(bind))
                    assert(bone>=0)
                    actual+=(sk.global_transform*sk.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind)*vertices[vertex])*weight
                var best := INF
                for row in data.points[str(frame)]:best=minf(best,actual.distance_to(Vector3(row[0],row[1],row[2])))
                maximum=maxf(maximum,best)
    assert(maximum<.0002,"Exported skin differs from Blender: "+str(maximum))
    var marker: Node3D=model.get_node(data.info.nodes.point_0)
    assert(marker.get_parent() is BoneAttachment3D)
    for visual in model.find_children("*","MeshInstance3D",true,false):visual.mesh=null
    model.free();await process_frame
    print("ANIMATED_SKIN_AND_CLIPS_OK ",maximum);quit()
''', encoding="utf-8")
result = subprocess.run([addon.DEFAULT_GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(conversion), "--script", "res://verify.gd"], capture_output=True, text=True, timeout=30)
(ROOT / "docs/animated-export-skin.log").write_text(result.stdout + result.stderr, encoding="utf-8")
assert result.returncode == 0 and "ANIMATED_SKIN_AND_CLIPS_OK" in result.stdout, result.stdout + result.stderr
# Reexport updates the model, retains its UID and never edits the user's scene.
wrapper = output / "generic_machine.tscn"
text = wrapper.read_text(encoding="utf-8").replace('[node name="generic_machine"', '[node name="MyEditedMechanism"')
wrapper.write_text(text, encoding="utf-8")
wrapper_hash = hashlib.sha256(wrapper.read_bytes()).hexdigest()
third = bpy.data.objects.new("point_2", None)
bpy.context.collection.objects.link(third)
third.parent = root
third.location = (0, 0, 1.2)
request, payload = addon.exporter.build_payload(bpy.context, fixture / "request2", "animated", "generic_machine")
second = convert(request)
assert second["scene_preserved"] and second["asset_uid"] == first["asset_uid"]
assert hashlib.sha256(wrapper.read_bytes()).hexdigest() == wrapper_hash
assert "point_2" in json.loads((output / "source.json").read_text(encoding="utf-8"))["nodes"]
# Named NLA clips and the single synchronized scene are separate generic modes.
open_action = rig.animation_data.action
track = rig.animation_data.nla_tracks.new()
track.name = "opening"
track.strips.new("opening", 1, open_action)
rig.animation_data.action = None
pose.rotation_euler.y = .8
pose.keyframe_insert("rotation_euler", frame=1)
pose.rotation_euler.y = 0
pose.keyframe_insert("rotation_euler", frame=13)
close_action = rig.animation_data.action
close_action.name = "close_panel"
track = rig.animation_data.nla_tracks.new()
track.name = "closing"
track.strips.new("closing", 30, close_action)
rig.animation_data.action = None
scene.frame_end = 50
nla_state = [(track.name, track.mute, track.is_solo) for track in rig.animation_data.nla_tracks]
root.psx_export.animation_mode = "NLA_TRACKS"
request, _ = addon.exporter.build_payload(bpy.context, fixture / "request_nla", "animated", "generic_nla")
nla = convert(request)
assert any("opening" in clip["name"] and abs(clip["length"] - 1) < .001 for clip in nla["animations"]), nla
assert any("closing" in clip["name"] and abs(clip["length"] - .5) < .001 for clip in nla["animations"]), nla
assert nla_state == [(track.name, track.mute, track.is_solo) for track in rig.animation_data.nla_tracks]
root.psx_export.animation_mode = "SCENE"
request, _ = addon.exporter.build_payload(bpy.context, fixture / "request_sequence", "animated", "generic_sequence")
sequence = convert(request)
assert len(sequence["animations"]) == 1 and abs(sequence["animations"][0]["length"] - 49 / 24) < .001, sequence
root.psx_export.export_animations = False
request, _ = addon.exporter.build_payload(bpy.context, fixture / "request_rest", "animated", "generic_rest")
rest = convert(request)
assert not rest["animations"]
from types import SimpleNamespace
addon._preferences = lambda context: SimpleNamespace(project_path=str(fixture), godot_path=addon.DEFAULT_GODOT)
root.psx_export.asset_name = "operator_model"
assert bpy.ops.psx.export_asset(synchronous=True) == {"FINISHED"}, bpy.context.scene.psx_export_status
assert bpy.context.scene.psx_export_result == "res://assets/props/operator_model/operator_model.tscn"
(ROOT / "docs/animated-export-validation.json").write_text(json.dumps({"ok": True, "fixture": str(fixture), "source_unchanged": True, "scene_preserved": True, "source_slots": 3, "first": first, "nla": nla["animations"], "sequence": sequence["animations"], "without_animation": True}, indent=2), encoding="utf-8")
addon.unregister()
print("ANIMATED_EXPORT_OK", fixture)
