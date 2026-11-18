"""Check the real staircase and its separate ramp in an isolated Godot project."""
import hashlib
import json
import sys
from pathlib import Path
from types import SimpleNamespace
import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/blender_addons"))
import resident_psx_exporter as addon

fixture = Path((ROOT / "docs/blender-addon-validation-project.txt").read_text().strip())
assert fixture.name.startswith("psx-blender-export-validation-")
source = Path(bpy.data.filepath)
before = hashlib.sha256(source.read_bytes()).hexdigest()
addon.register()
addon._preferences = lambda context: SimpleNamespace(project_path=str(fixture), godot_path=addon.DEFAULT_GODOT)
try:
    stairs = bpy.data.objects["stairs_01"]
    collider = bpy.data.objects["stairs_collision"]
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    stairs.hide_set(False)
    stairs.select_set(True)
    collider.hide_set(False)
    collider.select_set(True)  # Must be excluded from the rendered selection.
    bpy.context.view_layer.objects.active = stairs
    stairs.psx_export.asset_type = "stairs"
    stairs.psx_export.asset_name = "stairs_01"
    matrix_before = collider.matrix_world.copy()
    request, payload = addon.exporter.build_payload(bpy.context, fixture / "exports/stairs_request", "stairs", "stairs_01")
    assert payload["collision"] == "CUSTOM" and payload["collision_source"] == "stairs_collision"
    assert payload["source_objects"] == ["stairs_01"]
    assert len(payload["collision_faces"]) > 0 and len(payload["collision_faces"]) % 3 == 0
    # Blender materials have backface culling disabled: their missing reverse
    # triangles must survive the PSX renderer's mandatory front-face culling.
    facings = {}
    from mathutils import Vector
    for row in payload["surfaces"]:
        for i in range(0, len(row["vertices"]), 3):
            points = [Vector(point) for point in row["vertices"][i:i+3]]
            key = tuple(sorted(tuple(round(c, 5) for c in point) for point in points))
            normal = (points[2] - points[0]).cross(points[1] - points[0]).normalized()
            facings.setdefault(key, []).append(normal)
    assert all(any(a.dot(b) < -.99 for b in directions) for directions in facings.values() for a in directions)
    assert min(v[1] for row in payload["surfaces"] for v in row["vertices"]) < -.29
    assert abs(max(v[1] for row in payload["surfaces"] for v in row["vertices"]) - 3) < .001
    # Collision and visual share one transform: no independent recentering.
    actual = {tuple(round(c, 4) for c in point) for point in payload["collision_faces"]}
    expected = {tuple(round(c, 4) for c in (p.x - 20, p.z, -(p.y - 10))) for p in (collider.matrix_world @ v.co for v in collider.data.vertices)}
    assert actual == expected
    assert bpy.ops.psx.export_asset(synchronous=True) == {"FINISHED"}
    assert bpy.context.scene.psx_export_result == "res://assets/props/stairs_01/stairs_01.tscn"
    assert collider.matrix_world == matrix_before
    # The general decor mode also accepts a manually assigned collision mesh.
    request, manual = addon.exporter.build_payload(bpy.context, fixture / "exports/stairs_manual_request", "prop", "stairs_manual", "ORIGIN", "CUSTOM", False, collider)
    assert manual["collision_source"] == "stairs_collision" and manual["source_objects"] == ["stairs_01"]
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    result = {"ok": True, "collision_triangles": len(payload["collision_faces"]) // 3, "source_unchanged": True, "relative_alignment_preserved": True}
    (ROOT / "docs/stairs-blender-validation.json").write_text(json.dumps(result, indent=2))
    print("STAIRS_BLENDER_OK", json.dumps(result))
finally:
    addon.unregister()
