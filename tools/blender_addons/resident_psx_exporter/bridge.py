"""Run resource conversion without starting the game's autoloads or native mixer."""
import os
import shutil
from pathlib import Path

FILES = (
    "tools/import_blender_asset.gd",
    "tools/import_animated_asset.gd",
    "scripts/modular_map/kit_data.gd",
    "scripts/modular_map/kit.gd",
    "scripts/psx_materials.gd",
)


def create(project, staging):
    project, root = Path(project), Path(staging) / "godot_bridge"
    root.mkdir(parents=True, exist_ok=True)
    (root / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="PSX Asset Export"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    for relative in FILES:
        source, destination = project / relative, root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        if source.with_suffix(source.suffix + ".uid").exists():
            shutil.copy2(source.with_suffix(source.suffix + ".uid"), destination.with_suffix(destination.suffix + ".uid"))
        if relative == "scripts/psx_materials.gd":
            # Only this temporary converter copy unloads its otherwise unused flags.
            text = destination.read_text(encoding="utf-8-sig")
            if not text.startswith("@static_unload"):
                destination.write_text("@static_unload\n" + text, encoding="utf-8")
    for folder in ("assets", "exports"):
        source, destination = project / folder, root / folder
        source.mkdir(parents=True, exist_ok=True)
        if os.name == "nt":
            import _winapi
            _winapi.CreateJunction(str(source), str(destination))
        else:
            destination.symlink_to(source, target_is_directory=True)
    cache = project / ".godot/uid_cache.bin"
    if cache.exists():
        (root / ".godot").mkdir(exist_ok=True)
        shutil.copy2(cache, root / ".godot/uid_cache.bin")
    return root
