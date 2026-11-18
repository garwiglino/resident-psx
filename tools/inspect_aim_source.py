"""Read the saved aiming pose without changing the Blender source."""
import bpy,json,pathlib,hashlib
root=pathlib.Path(__file__).resolve().parents[1]
scene=bpy.context.scene
saved=scene.frame_current
rig=bpy.data.objects['rig']
report={'source':bpy.data.filepath,'source_sha256':hashlib.sha256(pathlib.Path(bpy.data.filepath).read_bytes()).hexdigest(),
        'saved_frame':saved,'fps':scene.render.fps/scene.render.fps_base,'range':[scene.frame_start,scene.frame_end],
        'action':rig.animation_data.action.name if rig.animation_data and rig.animation_data.action else None,
        'camera':{},'samples':[]}
if scene.camera:
    camera=scene.camera
    report['camera']={'name':camera.name,'lens':camera.data.lens,'matrix':[list(r) for r in camera.matrix_world]}
for frame in sorted({saved,scene.frame_start,scene.frame_end,24,48}):
    scene.frame_set(frame)
    ev=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
    pelvis=ev.pose.bones['DEF-spine'].matrix
    row={'frame':frame,'pelvis':[list(r) for r in pelvis],'upper':{}}
    for name in ['DEF-spine.001','DEF-spine.003','DEF-spine.006','DEF-upper_arm.R','DEF-forearm.R','DEF-hand.R','DEF-hand.L']:
        row['upper'][name]=[list(r) for r in pelvis.inverted() @ ev.pose.bones[name].matrix]
    report['samples'].append(row)
(root/'docs'/'aim-source-inspection.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('AIM_SOURCE',json.dumps({k:v for k,v in report.items() if k!='samples'}))
