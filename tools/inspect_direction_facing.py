import bpy,math,json
from mathutils import Vector,Matrix
rig=bpy.data.objects['rig'];rows=[];C=Matrix.Rotation(-math.pi/2,3,'X')
for chosen in rig.animation_data.nla_tracks:
    for track in rig.animation_data.nla_tracks:track.mute=track!=chosen
    bpy.context.scene.frame_set(31)
    ev=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
    angles={}
    for name in ['root','DEF-spine','DEF-spine.003','DEF-spine.006']:
        b=ev.pose.bones[name]
        forward=C @ ((b.matrix @ b.bone.matrix_local.inverted()).to_3x3() @ Vector((0,-1,0)))
        angles[name]={'yaw':math.degrees(math.atan2(forward.x,forward.z)),'pitch':math.degrees(math.atan2(forward.y,math.hypot(forward.x,forward.z)))}
    rows.append({'clip':chosen.strips[0].name,'angles':angles})
print('DIRECTION_FACING',json.dumps(rows))
