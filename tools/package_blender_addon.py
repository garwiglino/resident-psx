"""Produce the installable legacy Blender add-on ZIP, without Python caches."""
import hashlib
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/blender_addons/resident_psx_exporter"
OUTPUT = ROOT / "exports/addons/PSX_Export_Godot.zip"
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as archive:
    for filename in ("__init__.py", "exporter.py", "bridge.py", "animated_export.py"):
        archive.write(SOURCE / filename, "resident_psx_exporter/" + filename)
    archive.write(ROOT / "EXPORT-BLENDER.txt", "resident_psx_exporter/LIRE-MOI.txt")
    archive.write(ROOT / "MODELES-RIGGES.txt", "resident_psx_exporter/MODELES-RIGGES.txt")
with zipfile.ZipFile(OUTPUT) as archive:
    assert archive.testzip() is None
    assert "resident_psx_exporter/__init__.py" in archive.namelist()
    assert not any("__pycache__" in name for name in archive.namelist())
destination = Path.home() / "Downloads/PSX_Export_Godot.zip"
if destination.exists() and destination.read_bytes() != OUTPUT.read_bytes():
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()[:12]
    backup = ROOT / "exports/backups" / ("PSX_Export_Godot_" + digest + ".zip")
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        shutil.copy2(destination, backup)
shutil.copy2(OUTPUT, destination)
print("BLENDER_ADDON_ZIP_OK", destination, OUTPUT.stat().st_size)
