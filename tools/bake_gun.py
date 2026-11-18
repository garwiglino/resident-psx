"""Bake object constraints explicitly: Blender glTF can double-apply Child Of."""
import bpy

def bake_gun(first, last):
    scene=bpy.context.scene
    gun=bpy.data.objects['gun_amature']
    original=gun.matrix_basis.copy()
    original_mode=gun.rotation_mode
    matrices=[]
    for f in range(first,last+1):
        scene.frame_set(f)
        matrices.append(gun.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world.copy())
    mute=[c.mute for c in gun.constraints]
    for c in gun.constraints:
        c.mute=True
    gun.animation_data_clear()
    gun.rotation_mode='QUATERNION'
    for f,m in zip(range(first,last+1),matrices):
        scene.frame_set(f)
        gun.location,gun.rotation_quaternion,gun.scale=m.decompose()
        for path in ['location','rotation_quaternion','scale']:
            gun.keyframe_insert(path,frame=f)
    action=gun.animation_data.action
    scene.frame_set(first)
    def restore():
        gun.animation_data_clear()
        bpy.data.actions.remove(action)
        gun.rotation_mode=original_mode
        gun.matrix_basis=original
        for c,state in zip(gun.constraints,mute):
            c.mute=state
        scene.frame_set(first)
    return restore
