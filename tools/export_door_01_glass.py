"""Export the authored fractured pane in door_01 hinge space."""
import hashlib
import json
import re
import sys
from pathlib import Path

import bpy


source = Path(bpy.data.filepath)
digest = hashlib.sha256(source.read_bytes()).hexdigest()
door = bpy.data.objects["door_01"]
rim = bpy.data.objects["door_01_glass_broken"]
glass = bpy.data.materials["M_doors_glass"]
shards = sorted((obj for obj in rim.users_collection[0].objects
                 if re.fullmatch(r"door_01_glass_+cell(?:\.\d+)?", obj.name)), key=lambda obj: obj.name)
assert shards, "No authored glass shards"


def points(obj):
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


pane = [point for face in door.data.polygons if door.material_slots[face.material_index].material == glass
        for point in (door.matrix_world @ door.data.vertices[i].co for i in face.vertices)]
fracture = points(rim)
for axis in (0, 2):
    for edge in (min, max):
        original = edge(p[axis] for p in pane) - door.matrix_world.translation[axis]
        broken = edge(p[axis] for p in fracture) - rim.matrix_world.translation[axis]
        assert abs(original - broken) < 0.0001, "Fracture does not fit the authored pane"
ground = min(p.z for p in points(door))
origin = rim.matrix_world.translation.copy()
origin.z += ground - door.matrix_world.translation.z


def godot(point):
    return [round(point.x, 7), round(point.z, 7), round(-point.y, 7)]


def export_mesh(obj, pivot):
    mesh = obj.data
    positions = points(obj)
    uv = mesh.uv_layers.active.data
    normal_basis = obj.matrix_world.to_3x3().inverted().transposed()
    mesh.calc_loop_triangles()
    triangles = []
    for triangle in mesh.loop_triangles:
        polygon = mesh.polygons[triangle.polygon_index]
        assert obj.material_slots[polygon.material_index].material == glass
        normal = godot((normal_basis @ polygon.normal).normalized())
        rows = []
        for index in (triangle.loops[0], triangle.loops[2], triangle.loops[1]):
            point = positions[mesh.loops[index].vertex_index] - pivot
            rows.append([godot(point), normal, [round(uv[index].uv.x, 7), round(uv[index].uv.y, 7)]])
        triangles.append(rows)
    return {"name": obj.name, "origin": godot(pivot - origin), "triangles": triangles}


data = {"source": source.name, "sha256": digest, "rim": export_mesh(rim, origin),
        "shards": [export_mesh(obj, obj.matrix_world.translation) for obj in shards]}
assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
path = Path(sys.argv[sys.argv.index("--") + 1])
path.write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
print(f"DOOR_GLASS_EXPORTED: {len(shards)} shards, {len(data['rim']['triangles'])} rim triangles")
