import bpy, json, sys, math
from pathlib import Path
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
collection = next((c for c in bpy.data.collections if c.name.lower() == 'modular'), None)
report = {'source': bpy.data.filepath, 'unit_scale': bpy.context.scene.unit_settings.scale_length,
          'collections': [c.name for c in bpy.data.collections], 'modules': []}
if collection:
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in sorted(collection.all_objects, key=lambda o: o.name):
        row = {'name': obj.name, 'type': obj.type, 'location': list(obj.location),
               'rotation': list(obj.rotation_euler), 'scale': list(obj.scale),
               'parent': obj.parent.name if obj.parent else None,
               'modifiers': [{'name': m.name, 'type': m.type, 'enabled': m.show_viewport} for m in obj.modifiers]}
        if obj.type == 'MESH':
            evaluated = obj.evaluated_get(graph); mesh = evaluated.to_mesh()
            points = [v.co.copy() for v in mesh.vertices]
            low = Vector([min(p[i] for p in points) for i in range(3)])
            high = Vector([max(p[i] for p in points) for i in range(3)])
            row.update(bounds_min=list(low), bounds_max=list(high), dimensions=list(high-low),
                       vertices=len(mesh.vertices), faces=len(mesh.polygons),
                       axis_values=[[round(v,6) for v in sorted({round(p[i],6) for p in points})] for i in range(3)],
                       materials=[m.name if m else None for m in obj.data.materials],
                       uv_layers=[layer.name for layer in obj.data.uv_layers],
                       face_normals=[{'center': list(p.center), 'normal': list(p.normal), 'material': p.material_index, 'vertices': list(p.vertices)} for p in mesh.polygons])
            evaluated.to_mesh_clear()
        report['modules'].append(row)
report['images'] = [{'name': i.name, 'path': i.filepath, 'size': list(i.size), 'packed': bool(i.packed_file)} for i in bpy.data.images]
target = root/'docs/modular-kit-source-audit.json';target.write_text(json.dumps(report, indent=2), encoding='utf-8')
print('MODULAR_KIT_AUDIT', json.dumps({'collections': report['collections'], 'modules': [{k: m.get(k) for k in ['name','dimensions','vertices','faces','modifiers']} for m in report['modules']]}))
