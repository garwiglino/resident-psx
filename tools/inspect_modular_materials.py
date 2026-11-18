import bpy, json, collections
from pathlib import Path
report = {}
for name in ('door_01','door_glass','window_glass','window_condemned','wall_door'):
    obj=bpy.data.objects.get(name)
    if not obj: continue
    mesh=obj.data
    copy=mesh.copy()
    before=[p.material_index for p in copy.polygons]
    copy.materials.clear()
    report[name]={
        'scale':list(obj.scale),'determinant':obj.matrix_world.to_3x3().determinant(),
        'materials':[m.name if m else None for m in mesh.materials],
        'face_materials':dict(collections.Counter(before)),
        'after_clear':dict(collections.Counter(p.material_index for p in copy.polygons)),
        'uv_layers':[{'name':u.name,'active_render':u.active_render,'active':u==mesh.uv_layers.active} for u in mesh.uv_layers],
        'polygons':[{'index':p.index,'material':p.material_index,'normal':list(p.normal),'center':list(p.center),
          'uv':[list(mesh.uv_layers.active.data[i].uv) for i in p.loop_indices]} for p in mesh.polygons],
    }
    bpy.data.meshes.remove(copy)
path=Path(__file__).resolve().parents[1]/'docs/modular-material-source-audit.json'
path.write_text(json.dumps(report,indent=2),encoding='utf8')
print('MODULAR_MATERIAL_AUDIT',json.dumps({n:{k:v for k,v in r.items() if k!='polygons'} for n,r in report.items()}))
