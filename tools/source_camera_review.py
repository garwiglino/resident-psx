import bpy, pathlib
from mathutils import Vector
root=pathlib.Path(__file__).resolve().parents[1]
s=bpy.context.scene
s.frame_set(1)
s.render.engine='CYCLES'
s.cycles.samples=16
s.render.resolution_percentage=100
s.render.resolution_x=320
s.render.resolution_y=240
s.world.color=(.25,.25,.25)
for ob in s.objects:
    if ob.type=='MESH' and ob.name not in ['cop_char','base','bullet','hammer','mag','slide','trigger']:
        ob.hide_render=True
for location,energy,size in [((2,3,4),350,4),((-3,-1,3),250,3)]:
    data=bpy.data.lights.new('Review','AREA')
    data.energy=energy
    data.size=size
    ob=bpy.data.objects.new('Review',data)
    s.collection.objects.link(ob)
    ob.location=location
    ob.rotation_euler=(Vector((0,0,.9))-ob.location).to_track_quat('-Z','Y').to_euler()
s.render.filepath=str(root/'docs'/'blender-camera.png')
bpy.ops.render.render(write_still=True)
