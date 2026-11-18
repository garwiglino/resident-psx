"""Read-only inspection of the artist's base and facial-expression package."""
import bpy, json, pathlib, sys
out=pathlib.Path(sys.argv[sys.argv.index('--')+1])
result={'source':bpy.data.filepath,'scene':bpy.context.scene.name,'scenes':[s.name for s in bpy.data.scenes],
        'frame':[bpy.context.scene.frame_start,bpy.context.scene.frame_end,bpy.context.scene.frame_current],
        'fps':bpy.context.scene.render.fps/bpy.context.scene.render.fps_base,'objects':[],'images':[]}
for ob in bpy.context.scene.objects:
    row={'name':ob.name,'type':ob.type,'parent':ob.parent.name if ob.parent else None}
    if ob.type=='ARMATURE':
        row['deform_bones']=[b.name for b in ob.data.bones if b.use_deform]
        row['rest']={b.name:[list(v) for v in b.matrix_local] for b in ob.data.bones if b.use_deform}
        ad=ob.animation_data
        row['action']=ad.action.name if ad and ad.action else None
        row['nla']=[{'name':s.name,'range':[s.frame_start,s.frame_end],'muted':t.mute or s.mute} for t in ad.nla_tracks for s in t.strips] if ad else []
    if ob.type=='MESH':
        row.update(vertices=len(ob.data.vertices),faces=len(ob.data.polygons),uv_layers=[l.name for l in ob.data.uv_layers],modifiers=[{'type':m.type,'object':getattr(getattr(m,'object',None),'name',None)} for m in ob.modifiers])
        row['materials']=[]
        for i,mat in enumerate(ob.data.materials):
            if not mat:continue
            entry={'name':mat.name,'faces':sum(p.material_index==i for p in ob.data.polygons),'nodes':[]}
            if mat.use_nodes:
                for n in mat.node_tree.nodes:
                    entry['nodes'].append({'type':n.type,'name':n.name,'image':n.image.name if n.type=='TEX_IMAGE' and n.image else None})
            row['materials'].append(entry)
        if ob.data.uv_layers.active:
            row['uv_ranges']={str(i):[[min(ob.data.uv_layers.active.data[l].uv[a] for p in ob.data.polygons if p.material_index==i for l in p.loop_indices),max(ob.data.uv_layers.active.data[l].uv[a] for p in ob.data.polygons if p.material_index==i for l in p.loop_indices)] for a in range(2)] for i in range(len(ob.data.materials)) if any(p.material_index==i for p in ob.data.polygons)}
    result['objects'].append(row)
for image in bpy.data.images:result['images'].append({'name':image.name,'size':list(image.size),'path':image.filepath,'packed':bool(image.packed_file),'source':image.source})
out.write_text(json.dumps(result,indent=2),encoding='utf8')
print('FACE_SOURCE_INSPECTED',out)
