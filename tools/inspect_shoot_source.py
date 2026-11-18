"""Read-only timing and bone audit of the supplied shooting scene."""
import bpy,json,pathlib,hashlib
root=pathlib.Path(__file__).resolve().parents[1]
scene=bpy.context.scene
rig=bpy.data.objects['rig'];gun=bpy.data.objects['gun_amature']
report={'source':bpy.data.filepath,'source_sha256':hashlib.sha256(pathlib.Path(bpy.data.filepath).read_bytes()).hexdigest(),
        'fps':scene.render.fps/scene.render.fps_base,'samples':[],'meshes':[]}
for ob in scene.objects:
    if ob.type!='MESH' or not any(m.type=='ARMATURE' and m.object==gun for m in ob.modifiers):continue
    report['meshes'].append({'name':ob.name,'groups':[g.name for g in ob.vertex_groups],
      'weighted_groups':sorted({ob.vertex_groups[g.group].name for v in ob.data.vertices for g in v.groups if g.weight>.0001})})
for f in range(1,10):
    scene.frame_set(f);dep=bpy.context.evaluated_depsgraph_get()
    er=rig.evaluated_get(dep);eg=gun.evaluated_get(dep)
    report['samples'].append({'frame':f,'time':(f-1)/report['fps'],
      'pelvis':[list(r) for r in er.pose.bones['DEF-spine'].matrix],
      'hand':[list(r) for r in er.pose.bones['DEF-hand.R'].matrix],
      'gun':{b.name:{'location':list(b.location),'matrix':[list(r) for r in b.matrix]} for b in eg.pose.bones}})
(root/'docs'/'shoot-source-inspection.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('SHOOT_SOURCE',json.dumps({'fps':report['fps'],'meshes':report['meshes'],
  'slide':[(s['frame'],s['gun']['b_slide']['location']) for s in report['samples']]}))
