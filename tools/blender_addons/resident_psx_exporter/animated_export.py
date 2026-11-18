"""Export an authored hierarchy; never flatten or bake its armature into a prop."""
import hashlib
import json
from pathlib import Path

import bpy

SOURCE_TAG = "resident_psx_source_object"


def hierarchy(context, root):
    if root is None or root.type not in {"EMPTY", "ARMATURE"}:
        raise ValueError("Objet anime / rigge : rendre actif l'Empty racine du modele ou son armature.")
    objects = {root, *root.children_recursive}
    rigs = {obj for obj in objects if obj.type == "ARMATURE"}
    # A skin can be bound without being parented to its armature.
    for obj in context.scene.objects:
        if obj.type == "MESH" and any(mod.type == "ARMATURE" and mod.object in rigs for mod in obj.modifiers):
            objects.add(obj)
            objects.update(obj.children_recursive)
    widgets = {bone.custom_shape for rig in rigs for bone in rig.pose.bones if bone.custom_shape}
    objects = {obj for obj in objects if obj.type in {"EMPTY", "ARMATURE", "MESH", "CAMERA"} and obj not in widgets}
    meshes = [obj for obj in objects if obj.type == "MESH"]
    if not meshes:
        raise ValueError("La racine ne contient aucun modele visible a exporter.")
    for obj in objects:
        if obj.hide_get() or obj.hide_viewport:
            raise ValueError(f"{obj.name} est masque : le rendre visible pour cet export, ou le sortir de la hierarchie.")
    for obj in meshes:
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE" and modifier.object not in rigs:
                raise ValueError(f"{obj.name} utilise un rig hors de la racine. Choisir un Empty commun au modele et a son rig.")
        bone_names = {bone.name for modifier in obj.modifiers if modifier.type == "ARMATURE" and modifier.object for bone in modifier.object.data.bones}
        groups = {group.index for group in obj.vertex_groups if group.name in bone_names}
        if any(sum(weight.weight > 0 and weight.group in groups for weight in vertex.groups) > 8 for vertex in obj.data.vertices):
            raise ValueError(f"{obj.name} depasse huit influences par sommet, limite du modele Godot genere. Reduire les influences avant cet export ; aucun poids n'a ete tronque.")
    return sorted(objects, key=lambda obj: obj.name)


def _material(description, row, folder, materials, images):
    material = bpy.data.materials.new(row["name"])
    row["gltf_name"] = material.name
    row["two_sided"] = description["two_sided"]
    materials.append(material)
    material.use_nodes = True
    material.use_backface_culling = not description["two_sided"]
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = row["color"]
    shader.inputs["Roughness"].default_value = 1
    shader.inputs["Metallic"].default_value = 0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0
    shader.inputs["Alpha"].default_value = row["color"][3]
    if row["texture"]:
        image = bpy.data.images.load(str(folder / row["texture"]), check_existing=False)
        images.append(image)
        texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = image
        texture.interpolation = "Closest"
        material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    # Source-name metadata is restored on the Godot material after GLB import.
    material[SOURCE_TAG] = row["source_material"]
    return material


def build_payload(context, folder, asset_name):
    from .exporter import Pages, material_description, slug
    if context.mode != "OBJECT":
        raise ValueError("Passer en mode Objet avant l'export anime.")
    root = context.view_layer.objects.active
    objects = hierarchy(context, root)
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    name = slug(asset_name or root.name)
    settings = getattr(root, "psx_export", None)
    mode = getattr(settings, "animation_mode", "ACTIONS")
    animations = getattr(settings, "export_animations", True)
    if mode not in {"ACTIONS", "NLA_TRACKS", "SCENE"}:
        raise ValueError("Mode de clips d'animation inconnu.")
    meshes = [obj for obj in objects if obj.type == "MESH"]
    has_shapes = any(obj.data.shape_keys for obj in meshes)
    if has_shapes and any(mod.show_viewport and mod.type != "ARMATURE" for obj in meshes for mod in obj.modifiers):
        raise ValueError("Avec des shape keys, appliquer les autres modificateurs au modele avant export pour conserver sa geometrie. L'armature reste intacte.")
    original_selection = list(context.selected_objects)
    original_frame, original_subframe = context.scene.frame_current, context.scene.frame_subframe
    originals, tags, temporary_meshes, temporary_materials, temporary_images = [], [], [], [], []
    pages = Pages(folder, "animated")
    prepared = {}
    try:
        for obj in objects:
            tags.append((obj, SOURCE_TAG in obj, obj.get(SOURCE_TAG)))
            obj[SOURCE_TAG] = obj.name
        for obj in meshes:
            original = obj.data
            copy = original.copy()
            temporary_meshes.append(copy)
            originals.append((obj, original, [(slot.link, slot.material) for slot in obj.material_slots], obj.active_material_index))
            # Only UV/material copies change. Vertex indices, shape keys, weights,
            # custom normals, armature modifiers and transforms keep their data.
            obj.data = copy
            uv = copy.uv_layers.new(name="__PSXExportUV")
            copy.uv_layers.active = uv
            uv.active_render = True
            rows = []
            for polygon in copy.polygons:
                source = obj.material_slots[polygon.material_index].material if polygon.material_index < len(obj.material_slots) else None
                description = material_description(source)
                source_uv = original.uv_layers.get(description["uv_map"]) if description["uv_map"] else original.uv_layers.active
                if description["image"] and source_uv is None:
                    raise ValueError(f"{obj.name} : la texture exige une couche UV.")
                coords = [tuple(source_uv.data[index].uv) if source_uv else (0, 0) for index in polygon.loop_indices]
                coords, page = pages.material(description, coords)
                rows.append((polygon, page))
                for index, coordinate in zip(polygon.loop_indices, coords):
                    uv.data[index].uv = coordinate
                if page not in prepared:
                    prepared[page] = _material(description, pages.materials[page], folder, temporary_materials, temporary_images)
            copy.materials.clear()
            for page in range(len(pages.materials)):
                copy.materials.append(prepared[page])
            for slot in obj.material_slots:
                slot.link = "DATA"
            for polygon, page in rows:
                polygon.material_index = page
        for obj in context.selected_objects:
            obj.select_set(False)
        for obj in objects:
            obj.select_set(True)
        context.view_layer.objects.active = root
        path = folder / "model.glb"
        options = dict(filepath=str(path), export_format="GLB", use_selection=True,
                       export_extras=True, export_yup=True, export_cameras=True, export_lights=False,
                       export_animations=animations, export_animation_mode=mode,
                       export_anim_single_armature=False, export_anim_scene_split_object=False,
                       export_nla_strips_merged_animation_name="sequence", export_frame_range=True,
                       export_anim_slide_to_zero=True,
                       export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=False,
                       export_def_bones=False, export_armature_object_remove=False,
                       export_rest_position_armature=True, export_all_influences=True,
                       export_apply=not has_shapes, export_morph=True)
        supported = bpy.ops.export_scene.gltf.get_rna_type().properties
        result = bpy.ops.export_scene.gltf(**{key: value for key, value in options.items() if key in supported})
        if result != {"FINISHED"} or not path.is_file():
            raise RuntimeError("L'export glTF du modele anime a echoue.")
        payload = {"format_version": 2, "asset_type": "animated", "asset_name": name,
                   "source_blend": bpy.data.filepath, "source_objects": [obj.name for obj in objects],
                   "root_object": root.name, "gltf": "model.glb", "materials": pages.materials,
                   "fps": context.scene.render.fps / context.scene.render.fps_base,
                   "animation_mode": mode, "export_animations": animations,
                   "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        request = folder / "request.json"
        request.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
        return request, payload
    finally:
        for obj, original, slots, active_material in originals:
            obj.data = original
            for slot, (link, material) in zip(obj.material_slots, slots):
                slot.link = link
                if link == "OBJECT":
                    slot.material = material
            obj.active_material_index = active_material
        for obj, existed, value in tags:
            if existed:
                obj[SOURCE_TAG] = value
            elif SOURCE_TAG in obj:
                del obj[SOURCE_TAG]
        context.scene.frame_set(original_frame, subframe=original_subframe)
        for obj in context.selected_objects:
            obj.select_set(False)
        for obj in original_selection:
            obj.select_set(True)
        context.view_layer.objects.active = root
        for mesh in temporary_meshes:
            bpy.data.meshes.remove(mesh)
        for material in temporary_materials:
            bpy.data.materials.remove(material)
        for image in temporary_images:
            bpy.data.images.remove(image)
