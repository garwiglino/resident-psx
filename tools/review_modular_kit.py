import bpy, math, json
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
collection=bpy.data.collections['Modular']
scene=bpy.context.scene
for obj in scene.objects:obj.hide_render=obj.name not in collection.all_objects
for material in bpy.data.materials:
    if not material.use_nodes:continue
    tree=material.node_tree;out=next((n for n in tree.nodes if n.type=='OUTPUT_MATERIAL'),None)
    image=next((n for n in tree.nodes if n.type=='TEX_IMAGE' and n.image),None)
    if out and image:
        emission=tree.nodes.new('ShaderNodeEmission');tree.links.new(image.outputs['Color'],emission.inputs['Color']);tree.links.new(emission.outputs[0],out.inputs['Surface'])
    elif out:
        emission=tree.nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=(.22,.42,.48,1);tree.links.new(emission.outputs[0],out.inputs['Surface'])
camera_data=bpy.data.cameras.new('KitAudit');camera=bpy.data.objects.new('KitAudit',camera_data);scene.collection.objects.link(camera)
camera.location=(36,-13,24);target=Vector((15.5,10.5,1.25));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.type='ORTHO';camera_data.ortho_scale=29
scene.camera=camera;scene.render.engine='CYCLES';scene.cycles.samples=1
scene.render.resolution_x=1700;scene.render.resolution_y=700;scene.render.resolution_percentage=100
scene.world.color=(.06,.06,.06);scene.view_settings.view_transform='Standard';scene.render.filepath=str(root/'docs/modular-kit-source-overview.png')
bpy.ops.render.render(write_still=True)
details={}
for name in ['wall_loop','wall_door','wall_door_double','wall_corner_in','wall_corner_out','wall_loop_window']:
    mesh=bpy.data.objects[name].data;mesh.update()
    details[name]=[{'area':round(p.area,5),'normal':[round(x,4) for x in p.normal],
                    'min':[round(min(mesh.vertices[v].co[a] for v in p.vertices),5) for a in range(3)],
                    'max':[round(max(mesh.vertices[v].co[a] for v in p.vertices),5) for a in range(3)]} for p in mesh.polygons]
(root/'docs/modular-kit-face-audit.json').write_text(json.dumps(details,indent=2))
print('MODULAR_REVIEW_OK')
