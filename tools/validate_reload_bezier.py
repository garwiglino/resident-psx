"""Reopen both files and independently compare saved keys and full pose beats."""
import bpy,pathlib,json,hashlib,math
ROOT=pathlib.Path(__file__).resolve().parents[1]
report=json.loads((ROOT/'docs'/'reload-bezier-validation.json').read_text(encoding='utf8'))
frames=report['pose_frames']+[35.0]

def curves(action):
    return [fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
def signature(fc):
    return [(tuple(k.co),k.interpolation,tuple(k.handle_left),tuple(k.handle_right),k.handle_left_type,k.handle_right_type) for k in fc.keyframe_points]
def read(path):
    bpy.ops.wm.open_mainfile(filepath=path,load_ui=False)
    scene=bpy.context.scene
    targets=[bpy.data.objects[n] for n in ['rig','gun_amature']]
    active={ob.animation_data.action.name for ob in targets}
    keys={a.name:{(fc.data_path,fc.array_index):signature(fc) for fc in curves(a)} for a in bpy.data.actions}
    timing={'fps':scene.render.fps,'fps_base':scene.render.fps_base,'range':[scene.frame_start,scene.frame_end],
      'actions':{a.name:list(a.frame_range) for a in bpy.data.actions},
      'nla':{ob.name:[(t.name,t.mute,[(s.name,s.frame_start,s.frame_end,s.scale,s.repeat,s.action_frame_start,s.action_frame_end) for s in t.strips]) for t in ob.animation_data.nla_tracks] for ob in targets}}
    meshes=[ob for ob in scene.objects if ob.type=='MESH' and any(m.type=='ARMATURE' and m.object in targets for m in ob.modifiers)]
    poses={}
    for f in frames+[4.0]:
        scene.frame_set(math.floor(f),subframe=f-math.floor(f))
        dep=bpy.context.evaluated_depsgraph_get();row={}
        for ob in meshes:
            ev=ob.evaluated_get(dep);mesh=ev.to_mesh()
            row[ob.name]=[ev.matrix_world @ v.co for v in mesh.vertices];ev.to_mesh_clear()
        poses[f]=row
    return active,keys,timing,poses

active,old_keys,old_timing,old_poses=read(report['source'])
_,new_keys,new_timing,new_poses=read(report['output'])
assert old_timing==new_timing,'Saved NLA/FPS/ranges changed'
original_keys=0
for action,channels in old_keys.items():
    for (path,axis),keys in channels.items():
        new=new_keys[action][path,axis]
        continuous=path.endswith(('.location','.rotation_euler','.rotation_quaternion','.rotation_axis_angle','.scale'))
        if action not in active or not continuous:assert new==keys,'Unrelated curve changed: '+action+' '+path
        else:
            for row in keys:
                assert any(k[0]==row[0] for k in new),'Original frame/value changed: '+action+' '+path
                original_keys+=1
            assert all(k[1]=='BEZIER' for k in new),'A continuous channel remains stepped'
errors=[]
for f in frames+[4.0]:
    error=max(((a-b).length for name,points in old_poses[f].items() for a,b in zip(points,new_poses[f][name])),default=0)
    if f in frames:assert error<1e-5,'Saved full pose changed at frame '+str(f)
    errors.append({'frame':f,'mesh_vertex_error_m':error,'reference_pose':f in frames})
assert next(v['mesh_vertex_error_m'] for v in errors if v['frame']==4)>1e-5,'No interpolation smoothing occurred between poses'
assert hashlib.sha256(pathlib.Path(report['source']).read_bytes()).hexdigest()==report['source_sha256'],'Original source changed'
result={'output':report['output'],'original_transform_keys_preserved':original_keys,'unchanged_timing':new_timing,'pose_validation':errors}
(ROOT/'docs'/'reload-bezier-saved-validation.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print('SAVED_RELOAD_BEZIER_OK',json.dumps({'file':report['output'],'original_transform_keys_preserved':original_keys,
 'max_reference_pose_error_m':max(v['mesh_vertex_error_m'] for v in errors if v['reference_pose']),
 'interpolated_pose_change_m':next(v['mesh_vertex_error_m'] for v in errors if v['frame']==4)}))
