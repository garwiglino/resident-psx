"""Inspect actual evaluated object placement before changing the artist frame."""
import bpy, json, pathlib, hashlib
scene=bpy.context.scene
result={'source_sha256':hashlib.sha256(pathlib.Path(bpy.data.filepath).read_bytes()).hexdigest(),'saved_frame':scene.frame_current,'frames':[]}
for frame in dict.fromkeys([scene.frame_current,1,122]):
    scene.frame_set(frame);dep=bpy.context.evaluated_depsgraph_get();row={'frame':frame,'objects':{}}
    for name in ['rig','cop_char','winter_jacket']:
        ob=bpy.data.objects[name];evaluated=ob.evaluated_get(dep)
        item={'world':[list(v) for v in evaluated.matrix_world], 'basis':[list(v) for v in ob.matrix_basis], 'parent_inverse':[list(v) for v in ob.matrix_parent_inverse],
              'modifiers':[{'type':m.type,'rig':m.object.name if m.type=='ARMATURE' and m.object else None,'volume':m.use_deform_preserve_volume if m.type=='ARMATURE' else None,'vertex_group':m.vertex_group if m.type=='ARMATURE' else None,'show_viewport':m.show_viewport,'show_render':m.show_render} for m in ob.modifiers]}
        if ob.type=='MESH':
            mesh=evaluated.to_mesh();points=[evaluated.matrix_world @ v.co for v in mesh.vertices]
            item['bounds']=[[min(p[a] for p in points) for a in range(3)],[max(p[a] for p in points) for a in range(3)]]
            item['materials']=[(m.name,sum(p.material_index==i for p in mesh.polygons)) for i,m in enumerate(mesh.materials)]
            evaluated.to_mesh_clear()
        if ob.type=='ARMATURE':
            item['bones']={n:list(evaluated.pose.bones[n].matrix.translation) for n in ['root','DEF-spine','DEF-spine.003','DEF-upper_arm.L','DEF-upper_arm.R']}
            item['action']=ob.animation_data.action.name if ob.animation_data and ob.animation_data.action else None
            item['nla']=[{'track':t.name,'mute':t.mute,'strips':[(s.name,s.mute,s.frame_start,s.frame_end) for s in t.strips]} for t in ob.animation_data.nla_tracks]
        row['objects'][name]=item
    result['frames'].append(row)
out=pathlib.Path(__file__).resolve().parents[1]/'docs/garment-evaluated-state.json'
out.write_text(json.dumps(result,indent=2),encoding='utf8')
print('GARMENT_EVALUATED_STATE',json.dumps(result))
