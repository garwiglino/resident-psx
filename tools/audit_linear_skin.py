import bpy,json,pathlib
from mathutils import Vector
s=bpy.context.scene;s.frame_set(1);d=bpy.context.evaluated_depsgraph_get()
o=bpy.data.objects['cop_char'];r=bpy.data.objects['rig'];ev=o.evaluated_get(d);mesh=ev.to_mesh()
transforms={b.name:b.matrix @ b.bone.matrix_local.inverted() for b in r.pose.bones if b.bone.use_deform}
results=[]
for limit in [4,8,32]:
    errors=[]
    for v in o.data.vertices:
        groups=sorted([(g.weight,o.vertex_groups[g.group].name) for g in v.groups if o.vertex_groups[g.group].name in transforms],reverse=True)[:limit]
        total=sum(w for w,n in groups)
        p=sum((transforms[n] @ v.co * (w/total) for w,n in groups),Vector())
        errors.append((p-mesh.vertices[v.index].co).length)
    indices=sorted(range(len(errors)),key=lambda i:errors[i],reverse=True)[:6]
    results.append({'limit':limit,'max':max(errors),'mean':sum(errors)/len(errors),'worst':[{'vertex':i,'error':errors[i],'groups':[(o.vertex_groups[g.group].name,g.weight) for g in o.data.vertices[i].groups]} for i in indices]})
ev.to_mesh_clear()
(pathlib.Path(__file__).resolve().parents[1]/'docs'/'linear-skin-audit.json').write_text(json.dumps(results,indent=2))
print('LINEAR_SKIN',[(r['limit'],r['max'],r['mean']) for r in results])
