"""Independently reopen and validate saved Rigify edits at 60 samples/second."""
import bpy, pathlib, json, math, hashlib
from mathutils import Vector
ROOT=pathlib.Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'docs'/'pelvis-harmonization.json').read_text())
results=[]
def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:yield from bag.fcurves
def unchanged_channels(action):
    rows={}
    editable=['pose.bones["torso"].location']
    editable+=['pose.bones["thigh_ik.%s"].scale'%s for s in ['L','R']]
    editable+=['pose.bones["thigh_parent.%s"]["IK_Stretch"]'%s for s in ['L','R']]
    for curve in curves(action):
        if curve.data_path in editable:continue
        rows[(curve.data_path,curve.array_index)]=[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in curve.keyframe_points]
    return rows
def choose(rig,track):
    rig.animation_data.action=None
    for other in rig.animation_data.nla_tracks:other.mute=other!=track
def landmarks(rig):
    ev=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
    names=['root','foot_ik.L','foot_ik.R','DEF-foot.L','DEF-foot.R','DEF-toe.L','DEF-toe.R']
    return {name:(ev.matrix_world @ ev.pose.bones[name].matrix).copy() for name in names}
for file in manifest['files']:
    source=pathlib.Path(file['source'])
    assert hashlib.sha256(source.read_bytes()).hexdigest()==file['source_sha256'],'Artist source was altered'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig=bpy.data.objects['rig'];scene=bpy.context.scene
    references={}
    for track in rig.animation_data.nla_tracks:
        strip=track.strips[0]
        if not strip.name.startswith('player_'):continue
        choose(rig,track)
        samples=[]
        for step in range(241):
            time=1+step*.5;scene.frame_set(int(time),subframe=time%1)
            samples.append(landmarks(rig))
        references[strip.name]={'channels':unchanged_channels(strip.action),'samples':samples,
            'rest':{b.name:b.matrix_local.copy() for b in rig.data.bones},
            'timing':(strip.frame_start,strip.frame_end,strip.scale,strip.action_frame_start,strip.action_frame_end)}
    bpy.ops.wm.open_mainfile(filepath=file['output'])
    rig=bpy.data.objects['rig'];scene=bpy.context.scene
    for track in rig.animation_data.nla_tracks:
        strip=track.strips[0]
        if strip.name not in references:continue
        reference=references[strip.name]
        assert unchanged_channels(strip.action)==reference['channels'],('Unrequested animation channels changed',strip.name)
        assert (strip.frame_start,strip.frame_end,strip.scale,strip.action_frame_start,strip.action_frame_end)==reference['timing']
        assert all(max(abs(b.matrix_local[i][j]-reference['rest'][b.name][i][j]) for i in range(4) for j in range(4))<1e-8 for b in rig.data.bones)
        choose(rig,track)
        max_foot=0;max_root=0;min_knee=180;max_stretch=0;minimum_scale=2
        for step in range(241):
            time=1+step*.5;scene.frame_set(int(time),subframe=time%1)
            ev=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            actual=landmarks(rig);before=reference['samples'][step]
            max_root=max(max_root,max(abs(actual['root'][i][j]-before['root'][i][j]) for i in range(4) for j in range(4)))
            for name in ['foot_ik.L','foot_ik.R']:
                assert max(abs(actual[name][i][j]-before[name][i][j]) for i in range(4) for j in range(4))<1e-6
            for name in ['DEF-foot.L','DEF-foot.R','DEF-toe.L','DEF-toe.R']:
                max_foot=max(max_foot,(actual[name].translation-before[name].translation).length)
            for side in ['L','R']:
                thigh=ev.pose.bones['ORG-thigh.'+side];shin=ev.pose.bones['ORG-shin.'+side]
                hip=thigh.head;knee=shin.head;ankle=shin.tail
                min_knee=min(min_knee,180-math.degrees((hip-knee).angle(ankle-knee)))
                for length,rest in [((knee-hip).length,thigh.bone.length),((ankle-knee).length,shin.bone.length)]:
                    max_stretch=max(max_stretch,length/rest);minimum_scale=min(minimum_scale,length/rest)
                assert ev.pose.bones['thigh_parent.'+side]['IK_Stretch']==0
        row={'clip':strip.name,'samples':241,'minimum_knee_degrees':min_knee,'max_foot_shift_m':max_foot,
            'root_matrix_error':max_root,'leg_length_ratio_min':minimum_scale,'leg_length_ratio_max':max_stretch}
        results.append(row);print('SAVED_RIG_VALIDATION',json.dumps(row),flush=True)
        assert max_root<1e-6,(strip.name,'root',max_root)
        assert max_foot<.001,(strip.name,'feet',max_foot)
        assert min_knee>11.5,(strip.name,'knee',min_knee)
        assert .999<minimum_scale and max_stretch<1.001,(strip.name,'stretch',minimum_scale,max_stretch)
(ROOT/'docs'/'pelvis-saved-validation.json').write_text(json.dumps(results,indent=2))
print('SAVED_PELVIS_VALIDATION_OK: nine clips at 60 Hz; source files/root/foot controls unchanged; no leg stretching',flush=True)
