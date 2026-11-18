"""Read-only inspection of the artist's base character and modular garments."""
import bpy, json, pathlib, collections
result = {'source': bpy.data.filepath, 'frame': bpy.context.scene.frame_current, 'objects': [], 'images': []}
for ob in bpy.context.scene.objects:
    row = {'name': ob.name, 'type': ob.type, 'parent': ob.parent.name if ob.parent else None,
           'hidden': ob.hide_get(), 'matrix': [list(v) for v in ob.matrix_world]}
    if ob.type == 'MESH':
        row.update(vertices=len(ob.data.vertices), polygons=len(ob.data.polygons),
                   groups=[g.name for g in ob.vertex_groups], active_material=ob.active_material_index, shape_keys=list(ob.data.shape_keys.key_blocks.keys()) if ob.data.shape_keys else [],
                   modifiers=[{'name': m.name, 'type': m.type, 'rig': m.object.name if m.type == 'ARMATURE' and m.object else None} for m in ob.modifiers],
                   materials=[])
        for index, mat in enumerate(ob.data.materials):
            polys = [p for p in ob.data.polygons if p.material_index == index]
            uv = [ob.data.uv_layers.active.data[loop].uv[:] for p in polys for loop in p.loop_indices] if ob.data.uv_layers.active else []
            row['materials'].append({'name': mat.name if mat else None, 'polygons': len(polys),
                'selected_polygons': sum(p.select for p in polys),
                'bounds': [[min((ob.matrix_world @ ob.data.vertices[v].co)[axis] for p in polys for v in p.vertices) for axis in range(3)], [max((ob.matrix_world @ ob.data.vertices[v].co)[axis] for p in polys for v in p.vertices) for axis in range(3)]] if polys else [],
                'uv_min': [min(v[i] for v in uv) for i in range(2)] if uv else [],
                'uv_max': [max(v[i] for v in uv) for i in range(2)] if uv else [],
                'images': [node.image.name for node in mat.node_tree.nodes if node.type == 'TEX_IMAGE' and node.image] if mat and mat.use_nodes else []})
    if ob.type == 'ARMATURE':
        row.update(bones=len(ob.data.bones), deform_bones=[b.name for b in ob.data.bones if b.use_deform],
                   action=ob.animation_data.action.name if ob.animation_data and ob.animation_data.action else None)
    result['objects'].append(row)
for image in bpy.data.images:
    result['images'].append({'name': image.name, 'size': list(image.size), 'path': image.filepath, 'packed': bool(image.packed_file)})
out=pathlib.Path(__file__).resolve().parents[1]/'docs/player-base-inspection.json'
out.write_text(json.dumps(result, indent=2), encoding='utf8')
print('PLAYER_BASE_INSPECTION', json.dumps({'objects': [{k:v for k,v in row.items() if k not in ['matrix','deform_bones']} for row in result['objects'] if row['name'] in ['rig','cop_char','winter_jacket']]}))
scene=bpy.context.scene; scene.frame_set(1)
for name in ['cop_char','winter_jacket']:
    ob=bpy.data.objects[name]
    if name=='winter_jacket' and not any(mod.type=='ARMATURE' for mod in ob.modifiers):
        mod=ob.modifiers.new('ExportOnlySkinCheck','ARMATURE');mod.object=bpy.data.objects['rig']
    evaluated=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
    bounds=[]
    for index in range(len(mesh.materials)):
        points=[evaluated.matrix_world @ mesh.vertices[v].co for p in mesh.polygons if p.material_index==index for v in p.vertices]
        bounds.append([[min(p[a] for p in points) for a in range(3)],[max(p[a] for p in points) for a in range(3)]] if points else [])
    print('FRAME1_SKIN_BOUNDS',name,json.dumps(bounds));evaluated.to_mesh_clear()
print('FRAME1_RIG_SPINE',json.dumps({name:{'pose':list(bpy.data.objects['rig'].pose.bones[name].matrix.translation),'rest':list(bpy.data.objects['rig'].data.bones[name].matrix_local.translation)} for name in ['DEF-spine','DEF-spine.003','DEF-head'] if name in bpy.data.objects['rig'].pose.bones}))
import struct
project=pathlib.Path(__file__).resolve().parents[1]
exec((project/'tools/game_rig_bake.py').read_text())
rig=bpy.data.objects['rig']; body=bpy.data.objects['cop_char']; jacket=bpy.data.objects['winter_jacket']
bake=GameRigBake(rig,[body,jacket],1)
raw=(project/'assets/character/cop_player.glb').read_bytes(); count=struct.unpack_from('<I',raw,12)[0]; gltf=json.loads(raw[20:20+count])
known={gltf['nodes'][n]['name'] for n in gltf['skins'][0]['joints']}
print('JACKET_SKIN_COMPATIBILITY',json.dumps({'new_segments':sorted(set(bake.segments)-known),'unweighted':{name:sum(not row for row in weights) for name,weights in bake.weights.items()},'overflow_vertices':len(bake.vertex_bones)}))
