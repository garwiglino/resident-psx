bl_info = {
    "name": "PSX - Export Godot",
    "author": "Resident PSX",
    "version": (1, 2, 0),
    "blender": (4, 2, 0),
    "location": "Vue 3D > Barre laterale N > PSX Export",
    "description": "Exporter modules Cartes 2m, decors et modeles animes/rigges vers le projet Godot",
    "category": "Import-Export",
}

import json
import os
import subprocess
import tempfile
from pathlib import Path

import bpy
from bpy.props import BoolProperty, EnumProperty, PointerProperty, StringProperty
if "exporter" in locals():
    import importlib
    importlib.reload(exporter)
    importlib.reload(bridge)
else:
    from . import exporter, bridge
if "animated_export" in locals():
    importlib.reload(animated_export)

DEFAULT_PROJECT = "C:/Users/sheensaw/MyApps/mgba-0.10.5/resident-psx/"
DEFAULT_GODOT = "C:/Users/sheensaw/MyApps/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"
_job = None


class PSXExportPreferences(bpy.types.AddonPreferences):
    bl_idname = __package__
    project_path: StringProperty(name="Projet Godot", subtype="DIR_PATH", default=DEFAULT_PROJECT)
    godot_path: StringProperty(name="Godot", subtype="FILE_PATH", default=DEFAULT_GODOT)

    def draw(self, context):
        self.layout.prop(self, "project_path")
        self.layout.prop(self, "godot_path")


class PSXObjectExportSettings(bpy.types.PropertyGroup):
    asset_type: EnumProperty(name="Type", items=exporter.TYPES, default="prop")
    asset_name: StringProperty(name="Nom", description="Vide : reprend le nom de l'objet actif", default="")
    origin_mode: EnumProperty(name="Pivot", items=(
        ("AUTO", "Gabarit automatique", "Portes : pied et charniere gauche ; murs : centre et pied ; decors et panneaux de fenetre : origine actuelle"),
        ("ORIGIN", "Origine actuelle", "Conserver exactement l'origine de l'objet actif, sans recentrer la geometrie"),
    ), default="AUTO")
    collision: EnumProperty(name="Collision", items=(
        ("BOX", "Boite", "Collision simple et legere autour du decor"),
        ("TRIMESH", "Forme du modele", "Collision statique suivant les triangles du decor"),
        ("NONE", "Aucune", "Decor sans collision"),
        ("CUSTOM", "Mesh separe", "Utiliser un mesh invisible distinct du modele affiche"),
    ), default="BOX")
    collision_object: PointerProperty(name="Mesh collision", type=bpy.types.Object, poll=lambda self, obj: obj.type == "MESH",
                                     description="Mesh de physique uniquement ; stairs_collision est reconnu automatiquement pour un escalier")
    two_sided: BoolProperty(name="Faces visibles des deux cotes", description="Pour un panneau ouvert ; ajoute uniquement les faces arriere manquantes", default=False)
    show_advanced: BoolProperty(name="Reglages", default=False, options={"SKIP_SAVE"})
    export_animations: BoolProperty(name="Exporter les animations", default=True)
    animation_mode: EnumProperty(name="Clips", items=(
        ("ACTIONS", "Actions et actions rangees", "Conserver les noms des actions actives ou rangees dans la NLA ; pas les actions sans lien avec ce modele"),
        ("NLA_TRACKS", "Pistes NLA", "Un clip par piste NLA, pour organiser plusieurs mouvements du mecanisme"),
        ("SCENE", "Sequence actuelle", "Un seul clip sur la plage de la scene, avec tous les objets et rigs synchronises"),
    ), default="ACTIONS")


def _preferences(context):
    addon = context.preferences.addons.get(__package__)
    return addon.preferences if addon else None


def _redraw():
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == "VIEW_3D":
                area.tag_redraw()


def _complete(job):
    try:
        job["log"].close()
        result_path = job["request"].with_suffix(".result.json")
        result = json.loads(result_path.read_text(encoding="utf-8")) if result_path.exists() else {}
        success = job["process"].returncode == 0 and result.get("ok", False)
        message = result.get("message", "Export interrompu. Voir le journal dans exports/blender_addon_exports.")
        scene = job["scene"]
        scene.psx_export_status = message
        scene.psx_export_result = result.get("resource", "") if success else ""
        scene.psx_export_log = str(job["log_path"])
        _redraw()
        return success
    except (ReferenceError, AttributeError, OSError, ValueError):
        return False


def _poll_job():
    global _job
    if _job is None:
        return None
    if _job["process"].poll() is None:
        return .2
    _complete(_job)
    _job = None
    _redraw()
    return None


class PSX_OT_export_asset(bpy.types.Operator):
    bl_idname = "psx.export_asset"
    bl_label = "Exporter vers Godot"
    bl_description = "Exporter la selection avec ses UV, normales et modificateurs, puis preparer le modele Godot"
    synchronous: BoolProperty(default=False, options={"HIDDEN", "SKIP_SAVE"})

    @classmethod
    def poll(cls, context):
        return context.active_object is not None and context.mode == "OBJECT" and _job is None

    def execute(self, context):
        global _job
        preferences = _preferences(context)
        project = Path(bpy.path.abspath(preferences.project_path if preferences else DEFAULT_PROJECT)).resolve()
        godot = Path(bpy.path.abspath(preferences.godot_path if preferences else DEFAULT_GODOT)).resolve()
        importer = project / "tools/import_blender_asset.gd"
        if not (project / "project.godot").is_file() or not importer.is_file():
            self.report({"ERROR"}, "Choisir le projet Resident PSX contenant l'importeur Godot.")
            return {"CANCELLED"}
        if not godot.is_file():
            self.report({"ERROR"}, "Choisir le fichier executable Godot dans les reglages.")
            return {"CANCELLED"}
        settings = context.active_object.psx_export
        context.scene.psx_export_result = ""
        staging = Path(tempfile.mkdtemp(prefix="resident_psx_export_"))
        try:
            request, payload = exporter.build_payload(context, staging, settings.asset_type, settings.asset_name,
                                                      settings.origin_mode, settings.collision, settings.two_sided, settings.collision_object)
        except (ValueError, RuntimeError, OSError) as error:
            context.scene.psx_export_status = str(error)
            self.report({"ERROR"}, str(error))
            return {"CANCELLED"}
        log_folder = project / "exports/blender_addon_exports"
        log_path = log_folder / (payload["asset_name"] + ".log")
        try:
            log_folder.mkdir(parents=True, exist_ok=True)
            log = log_path.open("w", encoding="utf-8")
            conversion_project = bridge.create(project, staging)
            process = subprocess.Popen([str(godot), "--headless", "--audio-driver", "Dummy", "--path", str(conversion_project), "--script",
                                        "res://tools/import_blender_asset.gd", "--", "--input", str(request)],
                                       stdout=log, stderr=subprocess.STDOUT, cwd=str(project),
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        except OSError as error:
            if "log" in locals():
                log.close()
            self.report({"ERROR"}, "Impossible de lancer Godot : " + str(error))
            return {"CANCELLED"}
        job = {"process": process, "log": log, "log_path": log_path, "request": request, "scene": context.scene}
        context.scene.psx_export_status = "Preparation dans Godot..."
        context.scene.psx_export_result = ""
        context.scene.psx_export_log = str(log_path)
        if self.synchronous:
            process.wait()
            return {"FINISHED"} if _complete(job) else {"CANCELLED"}
        _job = job
        bpy.app.timers.register(_poll_job, first_interval=.2)
        self.report({"INFO"}, "Export envoye vers Godot.")
        return {"FINISHED"}


class PSX_OT_open_export_folder(bpy.types.Operator):
    bl_idname = "psx.open_export_folder"
    bl_label = "Voir le dossier exporte"

    def execute(self, context):
        preferences = _preferences(context)
        root = Path(bpy.path.abspath(preferences.project_path if preferences else DEFAULT_PROJECT))
        relative = context.scene.psx_export_result.removeprefix("res://")
        bpy.ops.wm.path_open(filepath=str((root / relative).parent))
        return {"FINISHED"}


class PSX_PT_export(bpy.types.Panel):
    bl_label = "Export vers Godot"
    bl_idname = "PSX_PT_export"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "PSX Export"

    def draw(self, context):
        layout = self.layout
        obj = context.active_object
        if obj is None:
            layout.label(text="Selectionner un modele.", icon="INFO")
            return
        settings = obj.psx_export
        layout.prop(settings, "asset_type")
        if settings.asset_type == "animated":
            layout.prop(settings, "asset_name")
            layout.prop(settings, "export_animations")
            if settings.export_animations:
                layout.prop(settings, "animation_mode")
            layout.label(text="Actif : Empty racine ou armature.", icon="INFO")
            layout.label(text="Rig, meshes et reperes conserves.")
            layout.label(text="Reexport : reglages Godot conserves.")
        elif settings.asset_type in {"prop", "stairs"}:
            layout.prop(settings, "asset_name")
            if settings.asset_type == "prop":
                layout.prop(settings, "collision")
            if settings.asset_type == "stairs" or settings.collision == "CUSTOM":
                layout.prop(settings, "collision_object")
                collision = exporter.resolve_collision(context, settings.asset_type, obj, settings.collision_object)
                layout.label(text=("Collision invisible : " + collision.name) if collision else "Choisir le mesh de collision.", icon="INFO" if collision else "ERROR")
            layout.label(text="Scene prete a glisser dans Godot.")
        else:
            layout.label(text="Met a jour ce module dans Cartes 2m.", icon="INFO")
            layout.label(text=dict((row[0], row[2]) for row in exporter.TYPES)[settings.asset_type])
        layout.prop(settings, "show_advanced", icon="TRIA_DOWN" if settings.show_advanced else "TRIA_RIGHT", emboss=False)
        if settings.show_advanced:
            box = layout.box()
            if settings.asset_type != "animated":
                box.prop(settings, "origin_mode")
                box.prop(settings, "two_sided")
            else:
                box.label(text="Pivot : origine de la racine active.")
                box.label(text="Collisions et interactions dans Godot.")
            box.label(text="Axes Blender : X largeur, Y profondeur, Z hauteur.")
            preferences = _preferences(context)
            if preferences:
                box.prop(preferences, "project_path")
                box.prop(preferences, "godot_path")
        row = layout.row()
        row.scale_y = 1.5
        row.enabled = _job is None
        row.operator("psx.export_asset", icon="EXPORT", text="Export en cours..." if _job else "Exporter vers Godot")
        if context.mode != "OBJECT":
            layout.label(text="Passer en mode Objet.", icon="ERROR")
        if context.scene.psx_export_status:
            column = layout.column()
            column.scale_y = .85
            for line in context.scene.psx_export_status.splitlines():
                column.label(text=line)
        if context.scene.psx_export_result:
            layout.operator("psx.open_export_folder", icon="FILE_FOLDER")


CLASSES = (PSXExportPreferences, PSXObjectExportSettings, PSX_OT_export_asset, PSX_OT_open_export_folder, PSX_PT_export)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Object.psx_export = PointerProperty(type=PSXObjectExportSettings)
    bpy.types.Scene.psx_export_status = StringProperty(options={"SKIP_SAVE"})
    bpy.types.Scene.psx_export_result = StringProperty(options={"SKIP_SAVE"})
    bpy.types.Scene.psx_export_log = StringProperty(options={"SKIP_SAVE"})


def unregister():
    global _job
    if _job is not None:
        _job["process"].terminate()
        try:
            _job["process"].wait(timeout=5)
        except subprocess.TimeoutExpired:
            _job["process"].kill()
        _job["log"].close()
        _job = None
    if bpy.app.timers.is_registered(_poll_job):
        bpy.app.timers.unregister(_poll_job)
    for name in ("psx_export_status", "psx_export_result", "psx_export_log"):
        delattr(bpy.types.Scene, name)
    del bpy.types.Object.psx_export
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
