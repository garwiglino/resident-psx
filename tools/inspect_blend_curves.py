"""Read-only action/NLA/key interpolation audit."""
import bpy,json,pathlib,collections,hashlib
root=pathlib.Path(__file__).resolve().parents[1]
scene=bpy.context.scene
report={'source':bpy.data.filepath,'sha256':hashlib.sha256(pathlib.Path(bpy.data.filepath).read_bytes()).hexdigest(),
 'blender_version':bpy.app.version_string,'file_version':list(bpy.data.version),'saved_frame':scene.frame_current,
 'scene_range':[scene.frame_start,scene.frame_end],'fps':scene.render.fps/scene.render.fps_base,'objects':[],'actions':[],'markers':[]}
for marker in scene.timeline_markers:report['markers'].append({'name':marker.name,'frame':marker.frame})
for ob in scene.objects:
    if ob.type not in ['ARMATURE','CAMERA']:continue
    ad=ob.animation_data
    report['objects'].append({'name':ob.name,'type':ob.type,'action':ad.action.name if ad and ad.action else None,
      'tracks':[{'name':t.name,'mute':t.mute,'solo':t.is_solo,'strips':[{'name':s.name,'action':s.action.name if s.action else None,
        'start':s.frame_start,'end':s.frame_end,'action_start':s.action_frame_start,'action_end':s.action_frame_end,
        'scale':s.scale,'repeat':s.repeat,'blend_type':s.blend_type,'influence':s.influence,'mute':s.mute} for s in t.strips]} for t in ad.nla_tracks] if ad else []})
for action in bpy.data.actions:
    curves=[]
    for layer in action.layers:
      for strip in layer.strips:
       for bag in strip.channelbags:
        for curve in bag.fcurves:
          curves.append({'path':curve.data_path,'axis':curve.array_index,'keys':len(curve.keyframe_points),
           'interpolation':dict(collections.Counter(k.interpolation for k in curve.keyframe_points)),
           'handles':dict(collections.Counter((k.handle_left_type+'/'+k.handle_right_type) for k in curve.keyframe_points)),
           'samples':[{'co':list(k.co),'interpolation':k.interpolation,'left_type':k.handle_left_type,'right_type':k.handle_right_type,
                       'left':list(k.handle_left),'right':list(k.handle_right)} for k in list(curve.keyframe_points)[:3]]})
    report['actions'].append({'name':action.name,'range':list(action.frame_range),'curves':curves})
out=root/'docs'/'cop-shoot-curve-inspection.json';out.write_text(json.dumps(report,indent=2),encoding='utf8')
print('BLEND_CURVES',json.dumps({**{k:v for k,v in report.items() if k!='actions'},'actions':[
 {'name':a['name'],'range':a['range'],'curves':len(a['curves']),'keys':sum(c['keys'] for c in a['curves']),
  'interpolation':dict(sum((collections.Counter(c['interpolation']) for c in a['curves']),collections.Counter())),
  'handles':dict(sum((collections.Counter(c['handles']) for c in a['curves']),collections.Counter()))} for a in report['actions']]}))
