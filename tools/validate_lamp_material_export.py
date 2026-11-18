"""Focused Blender-to-Godot test; all generated exports stay in a temp fixture."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/blender_addons"))
from resident_psx_exporter import exporter, bridge, DEFAULT_GODOT

fixture = Path(tempfile.mkdtemp(prefix="psx-lamp-material-export-"))
for relative in bridge.FILES:
    target = fixture / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / relative, target)
conversion = bridge.create(fixture, fixture / "staging")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_cube_add()
obj = bpy.context.object
lamp_material = bpy.data.materials.new("M_light")
housing = bpy.data.materials.new("M_surfaces")
obj.data.materials.append(lamp_material)
obj.data.materials.append(housing)
for polygon in obj.data.polygons:
    polygon.material_index = polygon.index % 2
request, payload = exporter.build_payload(bpy.context, fixture / "exports/request", "prop", "lamp_metadata", collision="NONE")
assert {row["source_material"] for row in payload["materials"]} == {"M_light", "M_surfaces"}
assert {row["name"] for row in payload["materials"]} == {"prop__m_light__couleur", "prop__m_surfaces__couleur"}
assert [m.name for m in obj.data.materials] == ["M_light", "M_surfaces"]
result = subprocess.run([DEFAULT_GODOT, "--headless", "--path", str(conversion), "--script", "res://tools/import_blender_asset.gd", "--", "--input", str(request), "--output-root", "res://exports/output"], capture_output=True, text=True, timeout=60)
assert result.returncode == 0, result.stdout + result.stderr
verify = conversion / "verify_metadata.gd"
verify.write_text('''extends SceneTree
func _initialize() -> void:
    var model: Node3D=load("res://exports/output/lamp_metadata/lamp_metadata.tscn").instantiate()
    var mesh: Mesh=model.get_node("Modele").mesh
    var sources := []
    for surface in mesh.get_surface_count():
        var material := mesh.surface_get_material(surface)
        sources.append(material.get_meta("psx_source_material",""))
        assert(material.resource_name.begins_with("prop__"))
    assert("M_light" in sources and "M_surfaces" in sources)
    print("LAMP_MATERIAL_IMPORT_OK ",sources)
    model.free();quit()
''', encoding="utf-8")
result = subprocess.run([DEFAULT_GODOT, "--headless", "--path", str(conversion), "--script", str(verify)], capture_output=True, text=True, timeout=60)
assert result.returncode == 0 and "LAMP_MATERIAL_IMPORT_OK" in result.stdout, result.stdout + result.stderr
print(result.stdout.strip())
(ROOT / "docs/lamp-material-export-validation.json").write_text(json.dumps({"ok": True, "fixture": str(fixture), "materials": payload["materials"]}, indent=2), encoding="utf-8")
print("LAMP_MATERIAL_EXPORT_OK", fixture)
