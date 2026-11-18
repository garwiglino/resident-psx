"""Read-only Blender source reference for the staircase export investigation."""
import bpy, math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
scene=bpy.context.scene
stairs=bpy.data.objects['stairs_01']
for obj in scene.objects:obj.hide_render=obj!=stairs
stairs.data=stairs.data.copy()
for index, old in enumerate(list(stairs.data.materials)):
    mat=bpy.data.materials.new('__review_'+old.name);mat.use_nodes=True
    nodes=mat.node_tree.nodes;nodes.clear();output=nodes.new('ShaderNodeOutputMaterial');emission=nodes.new('ShaderNodeEmission')
    image=next((n.image for n in old.node_tree.nodes if n.type=='TEX_IMAGE' and n.image),None) if old.use_nodes else None
    if image:
        tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest';mat.node_tree.links.new(tex.outputs['Color'],emission.inputs['Color'])
    else:emission.inputs['Color'].default_value=old.diffuse_color
    mat.node_tree.links.new(emission.outputs[0],output.inputs['Surface']);stairs.data.materials[index]=mat
camera_data=bpy.data.cameras.new('__review_camera');camera=bpy.data.objects.new('__review_camera',camera_data);scene.collection.objects.link(camera)
camera_data.sensor_fit='VERTICAL';camera_data.sensor_height=24;camera_data.lens=24/(2*math.tan(math.radians(55)/2));scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1;scene.cycles.use_denoising=False
scene.render.resolution_x=320;scene.render.resolution_y=240;scene.render.resolution_percentage=100
scene.world.color=(0,0,0);scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='Standard'
pivot=Vector((20,10,0));target=pivot+Vector((0,2,1.35))
for name,local in [('front',(-3,3,4)),('side',(-4,2.5,-2)),('back',(3,4,-6))]:
    camera.location=pivot+Vector((local[0],-local[2],local[1]));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(ROOT/'docs'/('stairs-source-'+name+'.png'));bpy.ops.render.render(write_still=True)
print('STAIRS_SOURCE_RENDER_OK')
