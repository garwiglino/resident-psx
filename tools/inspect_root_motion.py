import bpy,json,pathlib
from mathutils import Matrix
s=bpy.context.scene;r=bpy.data.objects['rig'];out=[]
for chosen in r.animation_data.nla_tracks:
    for track in r.animation_data.nla_tracks:track.mute=track!=chosen
    for f in [1,61,121]:
        s.frame_set(f)
        out.append({'track':chosen.name,'frame':f,'bones':{n:list((r.matrix_world@r.pose.bones[n].matrix).translation) for n in ['root','torso','DEF-spine','DEF-hand.R']}})
print('ROOT_SAMPLES',json.dumps(out))
errors=[]
for b in r.pose.bones:
    if not b.bone.use_deform:continue
    t,q,sc=b.matrix.decompose();m=Matrix.Translation(t) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((*sc,1))
    errors.append((max(abs(m[i][j]-b.matrix[i][j]) for i in range(4) for j in range(4)),b.name))
print('SHEAR_MAX',max(errors))
(pathlib.Path(__file__).resolve().parents[1]/'docs'/'root-motion-samples.json').write_text(json.dumps({'fps':s.render.fps,'samples':out,'shear':max(errors)},indent=2))
