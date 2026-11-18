import bpy, json
dep=bpy.context.evaluated_depsgraph_get()
for ob in bpy.data.objects:
    if ob.type!='MESH' or not ob.data.polygons or ob.name.startswith('WGT'):continue
    ev=ob.evaluated_get(dep);mesh=ev.to_mesh()
    points=[ev.matrix_world @ v.co for v in mesh.vertices]
    print('SCENE_MESH',json.dumps({'name':ob.name,'in_scene':ob.name in bpy.context.scene.objects,'visible':ob.visible_get(),'hidden':ob.hide_get(),'hide_render':ob.hide_render,'hide_viewport':ob.hide_viewport,
          'collections':[c.name for c in ob.users_collection],'parent':ob.parent.name if ob.parent else None,'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),
          'bounds':[[min(v[a] for v in points) for a in range(3)],[max(v[a] for v in points) for a in range(3)]],
          'materials':[m.name for m in mesh.materials]}))
    ev.to_mesh_clear()
print('SCENES',[(s.name,s.frame_current) for s in bpy.data.scenes], 'ACTIVE',bpy.context.scene.name)
