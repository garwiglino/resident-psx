"""Blender CLI integration test; every export targets a separate fixture project."""
import hashlib
import json
import re
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/blender_addons"))
import resident_psx_exporter as addon

fixture = Path((ROOT / "docs/blender-addon-validation-project.txt").read_text().strip())
assert fixture != ROOT and fixture.name.startswith("psx-blender-export-validation-")
original_kit = ROOT / "assets/environment/modular_2m/default_kit.tres"
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
kit_before = digest(original_kit)
source_before = digest(Path(bpy.data.filepath))
addon.register()
addon._preferences = lambda context: SimpleNamespace(project_path=str(fixture), godot_path=addon.DEFAULT_GODOT)
results = []
seen_uids = {}


def select(obj):
    for value in bpy.context.selected_objects:
        value.select_set(False)
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def export(obj, asset_type, name="", collision="BOX"):
    select(obj)
    obj.psx_export.asset_type = asset_type
    obj.psx_export.asset_name = name
    obj.psx_export.collision = collision
    obj.psx_export.origin_mode = "AUTO"
    assert bpy.ops.psx.export_asset(synchronous=True) == {"FINISHED"}, bpy.context.scene.psx_export_status
    assert bpy.context.scene.psx_export_result
    result = fixture / bpy.context.scene.psx_export_result.removeprefix("res://")
    assert result.is_file()
    log = (fixture / "exports/blender_addon_exports" / ((name or asset_type) + ".log")).read_text(encoding="utf-8")
    record = json.loads(next(line.split("BLENDER_PSX_EXPORT_OK ", 1)[1] for line in log.splitlines() if "BLENDER_PSX_EXPORT_OK " in line))
    assert record["asset_uid"].startswith("uid://") and "invalid" not in record["asset_uid"]
    if str(result) in seen_uids:
        assert seen_uids[str(result)] == record["asset_uid"]
    seen_uids[str(result)] = record["asset_uid"]
    results.append({"type": asset_type, "path": str(result), "collision": collision})


try:
    last_kit_uid = ""
    for asset_type, _, _ in addon.exporter.TYPES:
        if asset_type not in {"prop", "stairs", "animated"}:
            obj = bpy.data.objects[asset_type]
            uv_before = [tuple(value.uv) for value in obj.data.uv_layers.active.data] if obj.data.uv_layers.active else []
            material_before = [material.name if material else "" for material in obj.data.materials]
            matrix_before = obj.matrix_world.copy()
            export(obj, asset_type)
            header = (fixture / "assets/environment/modular_2m/default_kit.tres").read_text().splitlines()[0]
            kit_uid = re.search(r'uid="([^"]+)"', header).group(1)
            if last_kit_uid:
                assert last_kit_uid == kit_uid
            last_kit_uid = kit_uid
            assert matrix_before == obj.matrix_world
            assert material_before == [material.name if material else "" for material in obj.data.materials]
            assert uv_before == ([tuple(value.uv) for value in obj.data.uv_layers.active.data] if obj.data.uv_layers.active else [])
    # Re-export an already overridden module: atomic replacement must work on Windows.
    export(bpy.data.objects["door_glass"], "door_glass")
    bpy.ops.mesh.primitive_cube_add()
    prop = bpy.context.object
    prop.name = "Decor test incline"
    prop.scale = (-.5, .75, 1.25)
    prop.location = (40, -20, 12)
    bevel = prop.modifiers.new("Bevel de validation", "BEVEL")
    bevel.width = .08
    bevel.segments = 2
    for face in prop.data.polygons:
        face.use_smooth = True
    image = bpy.data.images.new("Texture test 32px", width=32, height=32, alpha=True)
    pixels = [component for y in range(32) for x in range(32) for component in (x / 31, y / 31, .25, 1)]
    image.pixels.foreach_set(pixels)
    image.update()
    material = bpy.data.materials.new("Peinture test")
    material.use_nodes = True
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    material.node_tree.links.new(tex.outputs["Color"], material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    prop.data.materials.append(material)
    # Out-of-range UVs must keep their tiling when the source image is <=256px.
    for loop in prop.data.uv_layers.active.data:
        loop.uv *= 3
    for collision in ("BOX", "TRIMESH", "NONE"):
        export(prop, "prop", "validation_decor_" + collision.lower(), collision)
    prop.psx_export.asset_name = "validation_async"
    assert bpy.ops.psx.export_asset() == {"FINISHED"}
    assert addon._job is not None
    deadline = time.monotonic() + 20
    while addon._job is not None and time.monotonic() < deadline:
        addon._poll_job()
        time.sleep(.05)
    assert addon._job is None and bpy.context.scene.psx_export_result.endswith("validation_async.tscn")
    assert len(prop.data.vertices) == 8 and len(prop.modifiers) == 1
    assert tuple(prop.location) == (40, -20, 12)
    fixture_kit = fixture / "assets/environment/modular_2m/default_kit.tres"
    before_refusal = digest(fixture_kit)
    door = bpy.data.objects["door_01"]
    select(door)
    saved_scale = door.scale.copy()
    door.scale.x *= 2
    try:
        bpy.context.view_layer.update()
        try:
            response = bpy.ops.psx.export_asset(synchronous=True)
            assert response == {"CANCELLED"}
        except RuntimeError as error:
            assert "Gabarit attendu" in str(error)
        assert "Gabarit attendu" in bpy.context.scene.psx_export_status
    finally:
        door.scale = saved_scale
    assert digest(fixture_kit) == before_refusal
    assert digest(original_kit) == kit_before
    assert digest(Path(bpy.data.filepath)) == source_before
    result = {"ok": True, "exports": results, "original_kit_unchanged": True, "source_blend_unchanged": True}
    (ROOT / "docs/blender-addon-validation.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("BLENDER_ADDON_OK", json.dumps({"exports": len(results), "asynchronous_button": True, "source_unchanged": True}))
finally:
    addon.unregister()
