"""Restore the active blocking actions to Bezier without moving reference poses.

The artist file and existing shooting NLA strips are preserved. Added breakdown
keys retain the full pose at every original pose beat before smoothing it.
"""
import bpy,json,pathlib,hashlib,math,collections
from mathutils import Vector

ROOT=pathlib.Path(__file__).resolve().parents[1]
SOURCE=pathlib.Path(bpy.data.filepath)
OUTPUT=ROOT/'exports'/'blender'/'cop_shoot_reload_bezier.blend'
if OUTPUT.exists():
    version=2
    while OUTPUT.with_stem(OUTPUT.stem+'_v'+str(version)).exists():version+=1
    OUTPUT=OUTPUT.with_stem(OUTPUT.stem+'_v'+str(version))
scene=bpy.context.scene
source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
saved_frame=scene.frame_current
targets=[bpy.data.objects[name] for name in ['rig','gun_amature']]
actions=list(dict.fromkeys(ob.animation_data.action for ob in targets if ob.animation_data and ob.animation_data.action))
assert len(actions)==2,'Expected the two active reload actions'

def curves(action):
    return [fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]

def continuous(fc):
    return fc.data_path.endswith(('.location','.rotation_euler','.rotation_quaternion','.rotation_axis_angle','.scale'))

def signature(action):
    return [(fc.data_path,fc.array_index,[(tuple(k.co),k.interpolation,tuple(k.handle_left),tuple(k.handle_right),k.handle_left_type,k.handle_right_type,k.type) for k in fc.keyframe_points]) for fc in curves(action)]

def timing():
    return {'fps':scene.render.fps,'fps_base':scene.render.fps_base,'scene_range':[scene.frame_start,scene.frame_end],
      'actions':{a.name:list(a.frame_range) for a in bpy.data.actions},
      'nla':{ob.name:[(t.name,t.mute,t.is_solo,[(s.name,s.action.name,s.frame_start,s.frame_end,s.action_frame_start,s.action_frame_end,s.scale,s.repeat,s.influence,s.mute,s.blend_type) for s in t.strips]) for t in ob.animation_data.nla_tracks] for ob in targets}}

all_before={a.name:signature(a) for a in bpy.data.actions}
timing_before=timing()
pose_frames=sorted({float(k.co.x) for action in actions for fc in curves(action) for k in fc.keyframe_points})
meshes=[ob for ob in scene.objects if ob.type=='MESH' and any(m.type=='ARMATURE' and m.object in targets for m in ob.modifiers)]

def snapshot(frame):
    scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame))
    dep=bpy.context.evaluated_depsgraph_get()
    poses={ob.name:{b.name:(ob.evaluated_get(dep).matrix_world @ b.matrix).copy() for b in ob.evaluated_get(dep).pose.bones} for ob in targets}
    vertices={}
    for ob in meshes:
        ev=ob.evaluated_get(dep);mesh=ev.to_mesh()
        vertices[ob.name]=[ev.matrix_world @ v.co for v in mesh.vertices]
        ev.to_mesh_clear()
    return poses,vertices

before={frame:snapshot(frame) for frame in pose_frames}
report={'source':str(SOURCE),'source_sha256':source_hash,'output':str(OUTPUT),'fps':scene.render.fps/scene.render.fps_base,
        'pose_frames':pose_frames,'actions':[],'validation':[]}
for action in actions:
    first,last=action.frame_range
    support=[f for f in pose_frames if first<=f<=last]
    edited=0;added=0
    for fc in curves(action):
        if not continuous(fc) or not any(k.interpolation!='BEZIER' for k in fc.keyframe_points):continue
        original=[tuple(k.co) for k in fc.keyframe_points]
        values=[k[1] for k in original]
        samples=[]
        if len(original)>1 and max(values)-min(values)>1e-8:
            modifiers=[(m,m.mute) for m in fc.modifiers]
            for m,_ in modifiers:m.mute=True
            samples=[(frame,fc.evaluate(frame)) for frame in support if not any(abs(frame-t)<1e-5 for t,_ in original)]
            for m,mute in modifiers:m.mute=mute
        for frame,value in samples:
            key=fc.keyframe_points.insert(frame,value,options={'FAST'})
            key.type='BREAKDOWN';added+=1
        for key in fc.keyframe_points:
            key.interpolation='BEZIER'
            key.handle_left_type=key.handle_right_type='AUTO_CLAMPED'
        fc.update();edited+=1
        for time,value in original:
            found=[k for k in fc.keyframe_points if abs(k.co.x-time)<1e-6]
            assert len(found)==1 and found[0].co.y==value,'Original key changed: '+action.name+' '+fc.data_path
    report['actions'].append({'name':action.name,'range':[first,last],'converted_curves':edited,'added_breakdown_keys':added})

assert timing()==timing_before,'Animation ranges, NLA timing or frame rate changed'
for action in bpy.data.actions:
    if action not in actions:assert signature(action)==all_before[action.name],'Unrelated action changed: '+action.name
for frame in pose_frames:
    poses,vertices=snapshot(frame)
    old_poses,old_vertices=before[frame]
    max_matrix=0.0;max_vertex=0.0
    for ob,bones in poses.items():
        for name,matrix in bones.items():
            max_matrix=max(max_matrix,max(abs(matrix[r][c]-old_poses[ob][name][r][c]) for r in range(4) for c in range(4)))
    for name,points in vertices.items():
        assert len(points)==len(old_vertices[name])
        max_vertex=max(max_vertex,max(((a-b).length for a,b in zip(points,old_vertices[name])),default=0))
    report['validation'].append({'frame':frame,'max_bone_matrix_error':max_matrix,'max_mesh_vertex_error_m':max_vertex})
    assert max_matrix<1e-5 and max_vertex<1e-5,'A reference pose changed on frame '+str(frame)
scene.frame_set(saved_frame)
OUTPUT.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT),check_existing=False,copy=True)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash,'Artist source was changed'
(ROOT/'docs'/'reload-bezier-validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('RELOAD_BEZIER_OK',json.dumps(report))
