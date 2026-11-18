import bpy,pathlib,json
from mathutils import Vector,Matrix
ROOT=pathlib.Path(__file__).resolve().parents[1]
exec((ROOT/'tools'/'game_rig_bake.py').read_text())
s=bpy.context.scene;s.frame_set(1);dep=bpy.context.evaluated_depsgraph_get()
r=bpy.data.objects['rig'];o=bpy.data.objects['cop_char'];b=GameRigBake(r,[o],1);b.sample(1,dep)
ev=o.evaluated_get(dep);mesh=ev.to_mesh();expected=[v.co.copy() for v in mesh.vertices];ev.to_mesh_clear()
errors=[];rest_scale=[]
for v,row in zip(o.data.vertices,b.weights[o.name]):
    point=Vector()
    for name,weight in row:
        rest=Matrix.Translation(b.vertex_bones[name][0]) if name in b.vertex_bones else (b.segments[name][2] if name in b.segments else b.rest[name])
        point+=(b.samples[0][2][name] @ rest.inverted() @ v.co)*weight
    errors.append((point-expected[v.index]).length)
new,meshes=b.build('test');s.frame_set(1);dep=bpy.context.evaluated_depsgraph_get()
ev=meshes[0].evaluated_get(dep);mesh=ev.to_mesh()
game_errors=[(v.co-expected[v.index]).length for v in mesh.vertices];ev.to_mesh_clear()
for name,(_,_,rest) in b.segments.items():
    actual=new.data.bones[name].matrix_local
    rest_scale.append((max(abs(rest[i][j]-actual[i][j]) for i in range(4) for j in range(4)),name,list(rest.to_scale())))
print('AUDIT_GAME_RIG',json.dumps({'math_max':max(errors),'math_mean':sum(errors)/len(errors),'game_max':max(game_errors),'game_mean':sum(game_errors)/len(game_errors),'rest_difference':sorted(rest_scale,reverse=True)[:8],'worst':sorted(enumerate(errors),key=lambda v:v[1],reverse=True)[:8]}))
