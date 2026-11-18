import bpy,json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
s=bpy.context.scene
info={'file':bpy.data.filepath,'range':[s.frame_start,s.frame_end],'fps':s.render.fps,'fps_base':s.render.fps_base,'objects':[],'actions':[],'samples':[]}
for o in s.objects:
    if o.name.startswith('WGT-'):continue
    row={'name':o.name,'type':o.type,'parent':o.parent.name if o.parent else None,'parent_type':o.parent_type,'parent_bone':o.parent_bone,
         'matrix_world':[list(r) for r in o.matrix_world],'matrix_local':[list(r) for r in o.matrix_local],
         'matrix_parent_inverse':[list(r) for r in o.matrix_parent_inverse], 'scale':list(o.scale),
         'constraints':[{'name':c.name,'type':c.type,'target':getattr(getattr(c,'target',None),'name',None),'bone':getattr(c,'subtarget',None),'influence':c.influence} for c in o.constraints]}
    if o.type=='ARMATURE':row['bones']=[{'name':b.name,'parent':b.parent.name if b.parent else None,'deform':b.use_deform,'rest':[list(r) for r in b.matrix_local]} for b in o.data.bones]
    if o.type=='MESH':row.update(vertices=len(o.data.vertices),polygons=len(o.data.polygons),modifiers=[{'type':m.type,'target':getattr(getattr(m,'object',None),'name',None)} for m in o.modifiers])
    a=o.animation_data
    row['animation']={'action':a.action.name if a and a.action else None,'tracks':[{'name':t.name,'mute':t.mute,'strips':[(st.name,st.action.name if st.action else None,st.frame_start,st.frame_end) for st in t.strips]} for t in a.nla_tracks] if a else []}
    info['objects'].append(row)
for a in bpy.data.actions:info['actions'].append({'name':a.name,'frames':list(a.frame_range),'slots':[s.identifier for s in a.slots]})
for f in [s.frame_start,round((s.frame_start+s.frame_end)/2),s.frame_end]:
    s.frame_set(f)
    dep=bpy.context.evaluated_depsgraph_get()
    row={'frame':f,'objects':{},'hand':None}
    for o in s.objects:
        if o.name.startswith('WGT-') or o.type not in ['ARMATURE','MESH'] or o.name=='Plane':continue
        ev=o.evaluated_get(dep)
        row['objects'][o.name]={'matrix':[list(r) for r in ev.matrix_world]}
        if o.type=='ARMATURE':
            row['objects'][o.name]['poses']={b.name:[list(r) for r in b.matrix] for b in ev.pose.bones if b.name.startswith('b_') or b.name in ['DEF-hand.R','hand_ik.R']}
    info['samples'].append(row)
(root/'docs'/'cop-idle-inspection.json').write_text(json.dumps(info,indent=2),encoding='utf8')
print('SPLIT_INSPECTION',[(o['name'],o['type'],o['animation']) for o in info['objects'] if o['type']=='ARMATURE'],info['actions'])
