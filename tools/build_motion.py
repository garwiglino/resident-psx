import bpy, pathlib, math
from mathutils import Vector, Matrix

ROOT = pathlib.Path(__file__).resolve().parents[1]
exec((ROOT/'tools'/'bake_gun.py').read_text())
scene = bpy.context.scene
rig = bpy.data.objects['rig']
source = rig.animation_data.action
scene.frame_set(1)
base = {n: rig.pose.bones[n].matrix.copy() for n in ['foot_ik.L','foot_ik.R','hand_ik.L','hand_ik.R','torso']}
keep = [rig,bpy.data.objects['cop_char'],bpy.data.objects['gun_amature']]
keep += [o for o in scene.objects if o.type=='MESH' and o.parent==bpy.data.objects['gun_amature']]
bpy.ops.object.select_all(action='DESELECT')
for ob in keep:
    ob.hide_set(False)
    ob.select_set(True)
bpy.context.view_layer.objects.active=rig

clips = [('walk',(0,-1,0),.30,19,False),('backward',(0,1,0),.23,23,False),
         ('strafe_left',(1,0,0),.23,23,False),('strafe_right',(-1,0,0),.23,23,False),
         ('run',(0,-1,0),.40,17,False),('aim',(0,0,0),0,25,True),
         ('aim_walk',(0,-1,0),.20,23,True)]
for name,direction,amplitude,frames,aim in clips:
    action = source.copy()
    action.name=name
    rig.animation_data.action=action
    rig.animation_data.action_slot=action.slots[0]
    # Write sampled Rigify control keys; exporter evaluates constraints for deform bones and gun.
    for f in range(1,frames+1):
        scene.frame_set(f)
        phase=(f-1)/(frames-1)*math.tau
        for side,offset in [('L',0),('R',math.pi)]:
            bone=rig.pose.bones['foot_ik.'+side]
            m=base[bone.name].copy()
            m.translation=Vector((.105 if side=='L' else -.105,-.01,.11674))
            angle=phase+offset
            m.translation += Vector(direction)*math.cos(angle)*amplitude
            m.translation.z += max(0,math.sin(angle))*(.15 if name=='run' else .09)
            bone.matrix=m
            bone.keyframe_insert('location',frame=f)
            bone.keyframe_insert('rotation_quaternion',frame=f)
        if aim:
            turn=Matrix.Translation(Vector((-.10,-.46,1.28))) @ Matrix.Rotation(math.pi/2,4,'X') @ Matrix.Translation(-base['hand_ik.R'].translation)
            for side in ['L','R']:
                bone=rig.pose.bones['hand_ik.'+side]
                bone.matrix=turn @ base[bone.name]
                bone.keyframe_insert('location',frame=f)
                bone.keyframe_insert('rotation_quaternion',frame=f)
    scene.frame_start=1
    scene.frame_end=frames
    scene.frame_set(1)
    restore_gun=bake_gun(1,frames)
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets'/'character'/(name+'.glb')),
        export_format='GLB',use_selection=True,export_animations=True,
        export_animation_mode='SCENE',export_frame_range=True,export_force_sampling=True,
        export_def_bones=True,export_apply=False,export_yup=True,export_optimize_animation_size=False)
    restore_gun()
    rig.animation_data.action=source
    rig.animation_data.action_slot=source.slots[0]
    bpy.data.actions.remove(action)
print('MOTION_DONE')
