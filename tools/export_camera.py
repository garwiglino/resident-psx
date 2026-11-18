import bpy, pathlib, json, math
from mathutils import Matrix
root=pathlib.Path(__file__).resolve().parents[1]
s=bpy.context.scene
s.frame_set(1)
cam=s.camera
assert cam, 'No active camera in source Blender scene'
rig=bpy.data.objects['rig']
conversion=Matrix.Rotation(math.pi,4,'Y') @ Matrix.Rotation(-math.pi/2,4,'X')
relative=conversion @ rig.matrix_world.inverted() @ cam.matrix_world
projection=cam.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=320,y=240,scale_x=1,scale_y=1)
config={'source':bpy.data.filepath,'camera':cam.name,'source_resolution':[s.render.resolution_x,s.render.resolution_y],
    'resolution':[320,240],'lens_mm':cam.data.lens,'sensor_width_mm':cam.data.sensor_width,
    'position':list(relative.translation),'rotation_degrees':[math.degrees(a) for a in relative.to_euler('YXZ')],
    'fov_vertical_degrees':math.degrees(2*math.atan(1/projection[1][1])),
    'near':cam.data.clip_start,'matrix':[list(r) for r in relative]}
(root/'assets'/'character'/'camera.json').write_text(json.dumps(config,indent=2),encoding='utf8')
print('CAMERA_CONFIG',json.dumps(config))
