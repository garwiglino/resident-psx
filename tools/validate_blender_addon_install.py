"""Run with temporary BLENDER_USER_SCRIPTS/CONFIG, never the artist's preferences."""
from pathlib import Path
import bpy
import addon_utils
import importlib
import sys

ROOT = Path(__file__).resolve().parents[1]
archive = ROOT / "exports/addons/PSX_Export_Godot.zip"
assert bpy.ops.preferences.addon_install(filepath=str(archive), overwrite=True) == {"FINISHED"}
addon_utils.enable("resident_psx_exporter", default_set=True)
assert "resident_psx_exporter" in bpy.context.preferences.addons
assert bpy.context.object.psx_export.asset_type == "prop"
assert len(bpy.context.object.psx_export.bl_rna.properties["asset_type"].enum_items) == 14
assert bpy.context.object.psx_export.bl_rna.properties["asset_type"].enum_items["stairs"].value == 12
assert bpy.context.object.psx_export.bl_rna.properties["asset_type"].enum_items["door_01"].value == 1
assert bpy.ops.psx.export_asset.poll()
addon_utils.disable("resident_psx_exporter", default_set=True)
assert not hasattr(bpy.types.Object, "psx_export")
module = sys.modules["resident_psx_exporter"]
module.exporter.TYPES = tuple(row for row in module.exporter.TYPES if row[0] != "stairs")
importlib.reload(module)
addon_utils.enable("resident_psx_exporter", default_set=True)
assert len(bpy.context.object.psx_export.bl_rna.properties["asset_type"].enum_items) == 14
addon_utils.disable("resident_psx_exporter", default_set=True)
print("BLENDER_ADDON_ZIP_INSTALL_OK")
