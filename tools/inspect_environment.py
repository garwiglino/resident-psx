import bpy,json,pathlib,hashlib
from mathutils import Vector
root=pathlib.Path(__file__).resolve().parents[1]
source=pathlib.Path(bpy.data.filepath)
report={'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'objects':[],'materials':[],'images':[]}
for ob in bpy.context.scene.objects:
    row={'name':ob.name,'type':ob.type,'parent':ob.parent.name if ob.parent else None,'collections':[c.name for c in ob.users_collection],
         'location':list(ob.location),'rotation':list(ob.rotation_euler),'scale':list(ob.scale),'hidden':ob.hide_render}
    if ob.type=='MESH':
        ev=ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
        points=[ev.matrix_world @ Vector(p) for p in ev.bound_box]
        row.update(mesh=ob.data.name,vertices=len(ob.data.vertices),polygons=len(ob.data.polygons),triangles=sum(len(p.vertices)-2 for p in ob.data.polygons),
            minimum=[min(p[i] for p in points) for i in range(3)],maximum=[max(p[i] for p in points) for i in range(3)],
            dimensions=list(ev.dimensions),materials=[s.material.name if s.material else None for s in ob.material_slots],
            modifiers=[{'type':m.type,'name':m.name} for m in ob.modifiers])
    report['objects'].append(row)
for mat in bpy.data.materials:
    row={'name':mat.name,'color':list(mat.diffuse_color),'nodes':[]}
    if mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type=='TEX_IMAGE':row['nodes'].append({'type':n.type,'image':n.image.name if n.image else None})
    report['materials'].append(row)
for im in bpy.data.images:
    report['images'].append({'name':im.name,'path':im.filepath,'packed':bool(im.packed_file),'size':list(im.size)})
(root/'docs'/'environment-source.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('ENVIRONMENT_OBJECTS',json.dumps([{k:v for k,v in r.items() if k in ['name','type','dimensions','minimum','maximum','triangles','collections','hidden','materials']} for r in report['objects']]))
print('ENVIRONMENT_IMAGES',json.dumps(report['images']))
