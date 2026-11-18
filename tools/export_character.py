"""Non-destructive evaluated Rigify -> glTF export. Run on the source copy in background."""
import bpy, json, pathlib, math
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
exec((ROOT/'tools'/'bake_gun.py').read_text())
scene = bpy.context.scene
rig = bpy.data.objects['rig']
char = bpy.data.objects['cop_char']
scene.frame_set(1)
report = {'markers': [(m.name, m.frame) for m in scene.timeline_markers], 'samples': [], 'materials': []}
for frame in [1, 13, 25, 37, 49, 61, 72]:
    scene.frame_set(frame)
    deps = bpy.context.evaluated_depsgraph_get()
    ev = char.evaluated_get(deps)
    coords = [ev.matrix_world @ v.co for v in ev.data.vertices]
    report['samples'].append({'frame': frame, 'min': [min(v[i] for v in coords) for i in range(3)], 'max': [max(v[i] for v in coords) for i in range(3)], 'bones': {b.name: list((rig.matrix_world @ b.matrix).translation) for b in rig.pose.bones if b.name in ['root','torso','DEF-hand.R','DEF-hand.L','DEF-foot.R','DEF-foot.L','DEF-spine','DEF-spine.006']}})
for mat in bpy.data.materials:
    report['materials'].append({'name': mat.name, 'color': list(mat.diffuse_color), 'nodes': [{'name': n.name, 'type': n.type, 'image': n.image.name if n.type == 'TEX_IMAGE' and n.image else None} for n in mat.node_tree.nodes] if mat.use_nodes else []})
(ROOT/'docs'/'animation-inspection.json').write_text(json.dumps(report, indent=2), encoding='utf8')

keep = [rig, char, bpy.data.objects['gun_amature']] + [ob for ob in scene.objects if ob.type == 'MESH' and ob.parent == bpy.data.objects['gun_amature']]
bpy.ops.object.select_all(action='DESELECT')
for ob in keep:
    ob.hide_set(False)
    ob.hide_viewport = False
    ob.select_set(True)
bpy.context.view_layer.objects.active = rig
scene.frame_start = 1
scene.frame_end = 72
scene.frame_set(1)
props = bpy.ops.export_scene.gltf.get_rna_type().properties
kwargs = dict(filepath=str(ROOT/'assets'/'character'/'cop.glb'), export_format='GLB', use_selection=True,
              export_animations=True, export_frame_range=True, export_force_sampling=True,
              export_def_bones=True, export_apply=False, export_yup=True)
if 'export_animation_mode' in props:
    kwargs['export_animation_mode'] = 'SCENE'
if 'export_sampling_interpolation_fallback' in props:
    kwargs['export_sampling_interpolation_fallback'] = 'LINEAR'
restore_gun=bake_gun(1,72)
kwargs['export_optimize_animation_size']=False
bpy.ops.export_scene.gltf(**kwargs)
restore_gun()

# Contact sheet source frames. Hiding is in-memory only; the .blend is never saved.
for ob in scene.objects:
    if ob.type == 'MESH' and ob not in keep:
        ob.hide_render = True
scene.render.engine = 'CYCLES'
scene.cycles.samples = 8
scene.world.color = (0.25,0.25,0.25)
scene.render.resolution_x = 400
scene.render.resolution_y = 400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
for location, energy, size in [((2,-3,5),350,4),((-3,1,3),200,3)]:
    ld = bpy.data.lights.new('Preview light','AREA')
    ld.energy = energy
    ld.shape = 'DISK'
    ld.size = size
    lo = bpy.data.objects.new('Preview light',ld)
    scene.collection.objects.link(lo)
    lo.location = location
    lo.rotation_euler = (Vector((0,0,0.85))-lo.location).to_track_quat('-Z','Y').to_euler()
camera_data = bpy.data.cameras.new('Preview')
camera = bpy.data.objects.new('Preview',camera_data)
scene.collection.objects.link(camera)
camera.location = (2.6,-4,1.8)
camera.rotation_euler = (Vector((0,0,0.85))-camera.location).to_track_quat('-Z','Y').to_euler()
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 2.1
scene.camera = camera
for f in [1,25,49]:
    scene.frame_set(f)
    scene.render.filepath = str(ROOT/'docs'/('source-frame-%02d.png' % f))
    bpy.ops.render.render(write_still=True)
print('EXPORT_DONE')
