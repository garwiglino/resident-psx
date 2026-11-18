import bpy, json, pathlib
from mathutils import Vector

out = pathlib.Path(__file__).resolve().parents[1] / 'docs' / 'source-inspection.json'
info = {'file': bpy.data.filepath, 'fps': bpy.context.scene.render.fps, 'objects': [], 'actions': [], 'images': []}
for ob in bpy.context.scene.objects:
    row = {'name': ob.name, 'type': ob.type, 'parent': ob.parent.name if ob.parent else None,
           'location': list(ob.location), 'dimensions': list(ob.dimensions), 'scale': list(ob.scale), 'hidden': ob.hide_render}
    if ob.type == 'MESH':
        row.update(vertices=len(ob.data.vertices), polygons=len(ob.data.polygons),
                   materials=[m.name if m else None for m in ob.data.materials],
                   modifiers=[{'type': m.type, 'name': m.name, 'object': getattr(getattr(m, 'object', None), 'name', None)} for m in ob.modifiers])
    if ob.type == 'ARMATURE':
        row['bones'] = [{'name': b.name, 'deform': b.use_deform} for b in ob.data.bones]
        ad = ob.animation_data
        row['animation'] = {'action': ad.action.name if ad and ad.action else None,
                            'tracks': [{'name': t.name, 'mute': t.mute, 'strips': [{'name': s.name, 'action': s.action.name if s.action else None, 'start': s.frame_start, 'end': s.frame_end} for s in t.strips]} for t in ad.nla_tracks] if ad else []}
    info['objects'].append(row)
for a in bpy.data.actions:
    info['actions'].append({'name': a.name, 'frames': list(a.frame_range), 'slots': [s.identifier for s in a.slots]})
for im in bpy.data.images:
    info['images'].append({'name': im.name, 'size': list(im.size), 'path': im.filepath, 'packed': bool(im.packed_file)})
out.write_text(json.dumps(info, indent=2), encoding='utf8')
print('INSPECTION', out)
