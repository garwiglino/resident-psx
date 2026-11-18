import bpy, pathlib
from mathutils import Vector
scene=bpy.context.scene
for ob in scene.objects:
    if ob.type=='MESH':ob.hide_render=ob.name not in ['cop_char','winter_jacket']
camera=bpy.data.objects.new('ExportReferenceCamera',bpy.data.cameras.new('ExportReferenceCamera'))
scene.collection.objects.link(camera);camera.location=(0,-4,1.25)
camera.rotation_euler=(Vector((0,0,1.25))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=2.8;scene.camera=camera
scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='TEXTURE'
scene.display.shading.show_shadows=False;scene.display.shading.show_cavity=False
scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(pathlib.Path(__file__).resolve().parents[1]/'docs/blender-garment-reference.png')
bpy.ops.render.render(write_still=True)
