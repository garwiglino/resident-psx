"""Export the authored stairs_01 + stairs_collision pair through the Blender add-on."""
import sys
from pathlib import Path
from types import SimpleNamespace
import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/blender_addons"))
import resident_psx_exporter as addon

addon.register()
addon._preferences = lambda context: SimpleNamespace(project_path=str(ROOT), godot_path=addon.DEFAULT_GODOT)
try:
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    stairs = bpy.data.objects["stairs_01"]
    stairs.hide_set(False)
    stairs.select_set(True)
    bpy.context.view_layer.objects.active = stairs
    stairs.psx_export.asset_type = "stairs"
    stairs.psx_export.asset_name = "stairs_01"
    stairs.psx_export.collision_object = bpy.data.objects["stairs_collision"]
    assert bpy.ops.psx.export_asset(synchronous=True) == {"FINISHED"}, bpy.context.scene.psx_export_status
    print("STAIRS_PREFAB_EXPORTED", bpy.context.scene.psx_export_result)
finally:
    addon.unregister()
