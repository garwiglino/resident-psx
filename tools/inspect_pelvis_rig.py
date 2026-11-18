"""Read-only Rigify inspection for source animation height harmonization."""
import bpy, json, pathlib, math
from mathutils import Vector

root = pathlib.Path(__file__).resolve().parents[1]
rig = bpy.data.objects['rig']
scene = bpy.context.scene
def fcurves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves
report = {'source': bpy.data.filepath, 'controls': [], 'actions': [], 'clips': []}
for b in rig.pose.bones:
    if b.name.startswith(('DEF-', 'ORG-', 'MCH-', 'VIS-')):continue
    if not any(s in b.name for s in ['torso','hips','chest','root','thigh','shin','foot','heel']):continue
    report['controls'].append({'name':b.name,'parent':b.parent.name if b.parent else None,
        'location':list(b.location),'rest':[list(row) for row in b.bone.matrix_local],
        'properties':{key:b[key] for key in b.keys() if isinstance(b[key],(int,float,str))},
        'constraints':[{'type':c.type,'name':c.name,'subtarget':getattr(c,'subtarget',''),'influence':c.influence} for c in b.constraints]})
for action in bpy.data.actions:
    curves=[{'path':c.data_path,'axis':c.array_index,'keys':len(c.keyframe_points),
             'range':[min(k.co.y for k in c.keyframe_points),max(k.co.y for k in c.keyframe_points)] if c.keyframe_points else []}
            for c in fcurves(action) if any(s in c.data_path for s in ['torso','hips','IK_FK','IK_Stretch','stretch','root'])]
    report['actions'].append({'name':action.name,'slots':[s.identifier for s in action.slots],'curves':curves})
tracks=list(rig.animation_data.nla_tracks)
choices=[(t,s) for t in tracks for s in t.strips if s.name.startswith('player_')]
if not choices:choices=[(None,None)]
for chosen,strip in choices:
    if chosen:
        for t in tracks:t.mute=t!=chosen
        for s in chosen.strips:s.mute=s!=strip
        rig.animation_data.action=None
    first,last=(round(strip.frame_start),round(strip.frame_end)) if strip else (scene.frame_start,scene.frame_end)
    samples=[]
    for frame in range(first,last+1):
        scene.frame_set(frame)
        ev=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        row={'frame':frame,'pelvis':list((ev.matrix_world @ ev.pose.bones['DEF-spine'].matrix).translation),'legs':{}}
        for side in ['L','R']:
            thigh=ev.pose.bones['ORG-thigh.'+side];shin=ev.pose.bones['ORG-shin.'+side]
            hip=ev.matrix_world @ thigh.head;knee=ev.matrix_world @ shin.head;ankle=ev.matrix_world @ shin.tail
            angle=180-math.degrees((hip-knee).angle(ankle-knee))
            row['legs'][side]={'hip':list(hip),'knee':list(knee),'ankle':list(ankle),
                'bend_degrees':angle,'thigh_length':(knee-hip).length,'shin_length':(ankle-knee).length,
                'rest_thigh':thigh.bone.length,'rest_shin':shin.bone.length,
                'ik_fk':rig.pose.bones.get('thigh_parent.'+side).get('IK_FK')}
        samples.append(row)
    report['clips'].append({'name':strip.name if strip else (rig.animation_data.action.name if rig.animation_data.action else 'idle'),
        'samples':samples,'pelvis_mean':sum(s['pelvis'][2] for s in samples)/len(samples),
        'knee_min':min(s['legs'][side]['bend_degrees'] for s in samples for side in ['L','R']),
        'stretch_max':max(max(s['legs'][side]['thigh_length']/s['legs'][side]['rest_thigh'],s['legs'][side]['shin_length']/s['legs'][side]['rest_shin']) for s in samples for side in ['L','R'])})
path=root/'docs'/('pelvis-source-'+pathlib.Path(bpy.data.filepath).stem+'.json')
path.write_text(json.dumps(report,indent=2),encoding='utf8')
print('PELVIS_INSPECTION',json.dumps({'file':str(path),'controls':[(c['name'],c['properties']) for c in report['controls']],
    'clips':[{k:v for k,v in c.items() if k!='samples'} for c in report['clips']]}))
