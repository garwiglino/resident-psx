"""Read evaluated static meshes without changing their objects, UVs or materials."""
import hashlib
import json
import math
import re
import unicodedata
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

TYPES = (
    ("prop", "Objet decoratif", "Accessoire libre, exporte en scene Godot avec collision au choix"),
    ("door_01", "Porte pleine", "Vantail 1 m x 2,20 m, charniere gauche"),
    ("door_glass", "Porte vitree", "Vantail vitre 1 m x 2,20 m"),
    ("wall_door", "Mur avec cadre de porte", "Module 2 m x 3 m, sans le vantail mobile"),
    ("wall_door_double", "Mur avec cadre double", "Module 4 m x 3 m, sans les vantaux mobiles"),
    ("wall_loop", "Mur", "Cloison de 2 m x 3 m"),
    ("wall_loop_simple", "Mur simple", "Variante de cloison 2 m x 3 m"),
    ("wall_loop_window", "Mur avec cadre de fenetre", "Module 2 m x 3 m, sans le panneau vitre"),
    ("window_glass", "Panneau de fenetre vitre", "Panneau conserve a sa hauteur par rapport au pied du mur"),
    ("window_condemned", "Panneau de fenetre condamnee", "Panneau avec planches, a sa hauteur dans le mur"),
    ("floor", "Sol", "Case de 2 m x 2 m"),
    ("ceiling", "Plafond", "Case de 2 m x 2 m, normales vers le bas"),
    ("stairs", "Escalier", "Scene placable avec son mesh de collision invisible pour une montee lisse"),
    ("animated", "Objet anime / rigge", "Hierarchie complete, skin, animations, cameras et reperes ; pour tous les mecanismes ou decors animes"),
)
WALLS = {"wall_door", "wall_door_double", "wall_loop", "wall_loop_simple", "wall_loop_window"}


def slug(value):
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    value = re.sub(r"[^a-z0-9_]+", "_", value).strip("_")[:80]
    if not value:
        raise ValueError("Donner un nom au modele.")
    return value


def selected_meshes(context):
    objects = set(context.selected_objects)
    for obj in list(objects):
        if obj.type == "EMPTY":
            objects.update(obj.children_recursive)
    meshes = sorted((obj for obj in objects if obj.type == "MESH"), key=lambda obj: obj.name)
    if not meshes:
        raise ValueError("Selectionner le modele, ou un Empty parent contenant ses meshes.")
    if any(mod.type == "ARMATURE" for obj in meshes for mod in obj.modifiers):
        raise ValueError("Ce type exporte une geometrie fixe. Pour conserver le rig et les animations, choisir Objet anime / rigge.")
    return meshes


def material_description(material):
    color = list(material.diffuse_color) if material else [0.8, 0.8, 0.8, 1.0]
    name = material.name if material else "Sans_materiau"
    image = None
    uv_map = ""
    glass = "glass" in name.lower() or "vitre" in name.lower()
    if material and material.use_nodes:
        output = next((node for node in material.node_tree.nodes if node.type == "OUTPUT_MATERIAL" and node.is_active_output), None)
        shader = output.inputs["Surface"].links[0].from_node if output and output.inputs["Surface"].is_linked else None
        if shader and shader.type in {"BSDF_PRINCIPLED", "BSDF_GLASS", "BSDF_DIFFUSE", "EMISSION"}:
            base = shader.inputs.get("Base Color") or shader.inputs.get("Color")
            glass = glass or shader.type == "BSDF_GLASS"
            if base:
                color = list(base.default_value)
                if base.is_linked:
                    node = base.links[0].from_node
                    if node.type == "TEX_IMAGE" and node.image:
                        image = node.image
                        color[:3] = [1.0, 1.0, 1.0]
                        vector = node.inputs["Vector"]
                        if vector.is_linked:
                            source = vector.links[0].from_node
                            if source.type == "UVMAP":
                                uv_map = source.uv_map
                            elif not (source.type == "TEX_COORD" and vector.links[0].from_socket.name == "UV"):
                                raise ValueError(f"{name} : utiliser une Image Texture avec des UV directs, ou baker les noeuds de couleur.")
                    elif node.type == "RGB":
                        color = list(node.outputs[0].default_value)
                    else:
                        raise ValueError(f"{name} : baker la couleur procedurale dans une image avant l'export.")
            alpha = shader.inputs.get("Alpha")
            if alpha:
                color[3] = float(alpha.default_value) if not alpha.is_linked else 1.0
        elif shader:
            raise ValueError(f"{name} : utiliser un materiau Principled avec couleur ou Image Texture.")
    if glass and color[3] >= 0.999:
        color[3] = 0.3
    return {"name": name, "color": color, "image": image, "uv_map": uv_map, "glass": glass,
            "two_sided": not material.use_backface_culling if material else True}


class Pages:
    def __init__(self, folder, asset_type):
        self.folder = Path(folder)
        self.asset_type = asset_type
        self.images = {}
        self.pages = {}
        self.materials = []
        self.material_keys = {}

    def page(self, image, coords):
        width, height = image.size
        if not width or not height:
            raise ValueError(f"Image introuvable ou non chargee : {image.name}")
        if max(width, height) <= 256:
            rect = (0, 0, width, height)
        else:
            uv = np.asarray(coords, dtype=float) * [width, height]
            low, high = uv.min(axis=0), uv.max(axis=0)
            x, y = (math.floor((float(value) + 1e-4) / 64) * 64 for value in low)
            power2 = lambda value: 1 << max(0, math.ceil(math.log2(max(1, value - 1e-4))))
            rect = (x, y, power2(high[0] - x), power2(high[1] - y))
            if max(rect[2:]) > 256:
                raise ValueError(f"{image.name} : une face couvre plus de 256 texels. Decouper ses UV ou utiliser une texture repetable de 256 px maximum.")
        key = (image.as_pointer(), rect)
        if key not in self.pages:
            if image.as_pointer() not in self.images:
                pixels = np.empty(width * height * 4, dtype=np.float32)
                image.pixels.foreach_get(pixels)
                self.images[image.as_pointer()] = pixels.reshape(height, width, 4)
            x, y, w, h = rect
            crop = self.images[image.as_pointer()][np.ix_(np.arange(y, y + h) % height, np.arange(x, x + w) % width)].copy()
            digest = hashlib.sha256(crop.tobytes() + image.colorspace_settings.name.encode()).hexdigest()[:16]
            relative = f"textures/page_{digest}.png"
            path = self.folder / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            page = bpy.data.images.new("__PSX_export_page", width=w, height=h, alpha=True)
            try:
                page.colorspace_settings.name = image.colorspace_settings.name
                page.pixels.foreach_set(crop.ravel())
                page.update()
                page.filepath_raw = str(path)
                page.file_format = "PNG"
                page.save()
            finally:
                bpy.data.images.remove(page)
            self.pages[key] = (relative, bool(np.any(crop[:, :, 3] < 0.999)))
        relative, alpha = self.pages[key]
        x, y, w, h = rect
        transformed = [((u * width - x) / w, (v * height - y) / h) for u, v in coords]
        return transformed, relative, rect, alpha

    def material(self, description, coords):
        image = description["image"]
        transformed, texture, rect, alpha = self.page(image, coords) if image else (coords, "", (), False)
        key = (description["name"], tuple(description["color"]), texture)
        if key not in self.material_keys:
            suffix = "_".join(str(value) for value in rect) if rect else "couleur"
            name = f"{self.asset_type}__{slug(description['name'])}__{suffix}"
            self.material_keys[key] = len(self.materials)
            self.materials.append({"name": name, "source_material": description["name"], "color": description["color"], "texture": texture,
                                   "transparent": description["glass"] or description["color"][3] < 0.999 or alpha})
        return transformed, self.material_keys[key]


def split_seam(triangle):
    """Give T/X mitres a real center seam, interpolating every corner attribute."""
    if min(row[0][2] for row in triangle) >= -1e-7 or max(row[0][2] for row in triangle) <= 1e-7:
        return [triangle]
    polygons = []
    for sign in (-1, 1):
        clipped = []
        for current, following in zip(triangle, triangle[1:] + triangle[:1]):
            a, b = current[0][2] * sign, following[0][2] * sign
            if a >= 0:
                clipped.append(current)
            if (a >= 0) != (b >= 0):
                t = a / (a - b)
                position = current[0].lerp(following[0], t)
                normal = current[1].lerp(following[1], t).normalized()
                uv = tuple(current[2][i] + (following[2][i] - current[2][i]) * t for i in range(2))
                clipped.append((position, normal, uv))
        for i in range(1, len(clipped) - 1):
            polygons.append([clipped[0], clipped[i], clipped[i + 1]])
    return polygons


def resolve_collision(context, asset_type, active, explicit=None):
    if explicit:
        return explicit
    names = [active.name + "_collision"]
    if asset_type == "stairs":
        names.append("stairs_collision")
    return next((context.scene.objects.get(name) for name in names if context.scene.objects.get(name)), None)


def collision_geometry(obj, origin, units, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    try:
        if not mesh or not mesh.polygons:
            raise ValueError(f"{obj.name} : le mesh de collision est vide.")
        transform = Matrix.Scale(units, 4) @ Matrix.Translation(-origin) @ obj.matrix_world
        if abs(transform.to_3x3().determinant()) < 1e-10:
            raise ValueError(f"{obj.name} : echelle de collision nulle.")
        normal_matrix = transform.to_3x3().inverted().transposed()
        walkable = [transform @ mesh.vertices[i].co for face in mesh.polygons
                    if (normal_matrix @ face.normal).normalized().z > .05 for i in face.vertices]
        entry_height = min((point.z for point in walkable), default=None)
        mesh.calc_loop_triangles()
        points = []
        for triangle in mesh.loop_triangles:
            order = list(triangle.vertices) if transform.to_3x3().determinant() < 0 else [triangle.vertices[0], triangle.vertices[2], triangle.vertices[1]]
            vertices = [transform @ mesh.vertices[i].co for i in order]
            if (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).length_squared > 1e-16:
                points.extend(vertices)
        if not points:
            raise ValueError(f"{obj.name} : la collision ne contient aucun triangle utilisable.")
        return points, entry_height
    finally:
        evaluated.to_mesh_clear()


def build_payload(context, folder, asset_type, asset_name, origin_mode="AUTO", collision="BOX", two_sided=False, collision_object=None):
    if asset_type == "animated":
        from . import animated_export
        return animated_export.build_payload(context, folder, asset_name)
    if asset_type not in {row[0] for row in TYPES}:
        raise ValueError("Type de modele inconnu.")
    if context.mode != "OBJECT":
        raise ValueError("Passer en mode Objet avant d'exporter.")
    objects = selected_meshes(context)
    active = context.view_layer.objects.active or objects[0]
    if asset_type == "stairs":
        collision = "CUSTOM"
    collider = None
    if collision == "CUSTOM" and asset_type in {"prop", "stairs"}:
        collider = resolve_collision(context, asset_type, active, collision_object)
        if collider is None or collider.type != "MESH":
            raise ValueError("Choisir un mesh de collision ; pour l'escalier, stairs_collision est reconnu automatiquement.")
        if collider == active:
            raise ValueError("Rendre actif le modele visible, pas son mesh de collision.")
        objects = [obj for obj in objects if obj != collider]
        if not objects:
            raise ValueError("Selectionner le modele visible de l'escalier.")
    name = slug(asset_name or active.name) if asset_type in {"prop", "stairs"} else asset_type
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    pages = Pages(folder, asset_type)
    origin = active.matrix_world.translation.copy()
    units = context.scene.unit_settings.scale_length
    depsgraph = context.evaluated_depsgraph_get()
    stored = []
    notes = []
    descriptions = {}
    collision_points, entry_height = collision_geometry(collider, origin, units, depsgraph) if collider else ([], None)
    try:
        for obj in objects:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
            if not mesh or not mesh.polygons:
                evaluated.to_mesh_clear()
                continue
            transform = Matrix.Scale(units, 4) @ Matrix.Translation(-origin) @ obj.matrix_world
            if abs(transform.to_3x3().determinant()) < 1e-10:
                evaluated.to_mesh_clear()
                raise ValueError(f"{obj.name} : echelle nulle.")
            points = [transform @ vertex.co for vertex in mesh.vertices]
            stored.append((evaluated, mesh, transform, points))
        if not stored:
            raise ValueError("Le modele ne contient aucune face.")
        points = [point for _, _, _, rows in stored for point in rows]
        low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
        high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
        if origin_mode == "AUTO":
            offset = Vector((0, 0, 0))
            if asset_type in {"door_01", "door_glass"}:
                offset.x, offset.z = -low.x, -low.z
            elif asset_type in WALLS:
                offset.x, offset.z = -(low.x + high.x) / 2, -low.z
            elif asset_type in {"floor", "ceiling"}:
                offset.x, offset.y = -(low.x + high.x) / 2, -(low.y + high.y) / 2
                offset.z = -high.z if asset_type == "floor" else -low.z
            elif asset_type == "stairs":
                if entry_height is None:
                    raise ValueError("La rampe ne contient aucune face orientee vers le haut. Verifier ses normales.")
                offset.z = -entry_height
                notes.append("Entree de la rampe calee au sol ; alignement relatif modele/collision conserve.")
            for point in points:
                point += offset
            for point in collision_points:
                point += offset
            if asset_type in {"wall_door", "wall_door_double"}:
                half = 1 if asset_type == "wall_door" else 2
                if abs((high.x - low.x) - (half * 2 + .2)) < .005:
                    for point in points:
                        if abs(point.x) >= half - 1e-5:
                            point.x -= math.copysign(.1, point.x)
                    notes.append("Retours de l'ancien cadre raccourcis de 10 cm, ouverture conservee.")
        size = Vector(tuple(max(p[i] for p in points) - min(p[i] for p in points) for i in range(3)))
        expected = None
        if asset_type in WALLS:
            expected = (4.0 if asset_type == "wall_door_double" else 2.0, 3.0)
        elif asset_type in {"door_01", "door_glass"}:
            expected = (1.0, 2.2)
        if expected and (abs(size.x - expected[0]) > .015 or abs(size.z - expected[1]) > .015):
            raise ValueError(f"Gabarit attendu : {expected[0]:g} m de large x {expected[1]:g} m de haut. Modele : {size.x:.3f} x {size.z:.3f} m. Aucune mise a l'echelle automatique.")
        if asset_type in {"floor", "ceiling"} and (abs(size.x - 2) > .015 or abs(size.y - 2) > .015):
            raise ValueError("Le sol ou plafond doit couvrir exactement 2 x 2 metres.")
        surfaces = {}
        for evaluated, mesh, transform, coordinates in stored:
            mesh.calc_loop_triangles()
            normal_matrix = transform.to_3x3().inverted().transposed()
            normals = [(normal_matrix @ corner.vector).normalized() for corner in mesh.corner_normals]
            signatures = {}
            face_normals = {}
            for face in mesh.polygons:
                signature = tuple(sorted(tuple(round(value, 5) for value in coordinates[i]) for i in face.vertices))
                normal = (normal_matrix @ face.normal).normalized()
                signatures.setdefault(signature, []).append(normal)
                face_normals[face.index] = (signature, normal)
            faces = {}
            for face in mesh.polygons:
                material = evaluated.material_slots[face.material_index].material if face.material_index < len(evaluated.material_slots) else None
                key = material.as_pointer() if material else 0
                if key not in descriptions:
                    descriptions[key] = material_description(material)
                description = descriptions[key]
                uv_layer = mesh.uv_layers.get(description["uv_map"]) if description["uv_map"] else mesh.uv_layers.active
                if description["image"] and not uv_layer:
                    raise ValueError(f"{evaluated.name} : creer des UV pour la texture {description['image'].name}.")
                uv = [tuple(uv_layer.data[i].uv) if uv_layer else (0.0, 0.0) for i in face.loop_indices]
                uv, index = pages.material(description, uv)
                face_points = np.asarray([list(coordinates[mesh.loops[i].vertex_index]) for i in face.loop_indices])
                coords = np.asarray(uv)
                gradient = np.linalg.pinv(face_points - face_points.mean(axis=0)) @ (coords - coords.mean(axis=0))
                signature, normal = face_normals[face.index]
                thin_wall = asset_type in WALLS and all(abs(coordinates[i].y) < 1e-5 for i in face.vertices) and abs(normal.y) > .99
                double = (two_sided or description["two_sided"] or description["glass"] or thin_wall) and not any(n.dot(normal) < -.99 for n in signatures[signature])
                faces[face.index] = (dict(zip(face.loop_indices, uv)), index, (float(gradient[0, 0]), float(-gradient[0, 1])), double)
            for triangle in mesh.loop_triangles:
                uv, index, gradient, double = faces[triangle.polygon_index]
                order = list(triangle.loops) if transform.to_3x3().determinant() < 0 else [triangle.loops[0], triangle.loops[2], triangle.loops[1]]
                rows = []
                for i in order:
                    p, n = coordinates[mesh.loops[i].vertex_index], normals[i]
                    rows.append((Vector((p.x, p.z, -p.y)), Vector((n.x, n.z, -n.y)), (uv[i][0], 1 - uv[i][1])))
                pieces = split_seam(rows) if asset_type in WALLS else [rows]
                for piece in pieces:
                    if (piece[1][0] - piece[0][0]).cross(piece[2][0] - piece[0][0]).length_squared < 1e-16:
                        continue
                    variants = [piece, [(p, -n, uv) for p, n, uv in reversed(piece)]] if double else [piece]
                    surface = surfaces.setdefault(index, {"material": index, "vertices": [], "normals": [], "uv": [], "uv_dx": []})
                    for variant in variants:
                        for p, n, texcoord in variant:
                            surface["vertices"].append([float(value) for value in p])
                            surface["normals"].append([float(value) for value in n])
                            surface["uv"].append([float(value) for value in texcoord])
                            surface["uv_dx"].append(list(gradient))
        rows = list(surfaces.values())
        if not rows:
            raise ValueError("Le modele ne contient aucun triangle utilisable.")
        collision_faces = [[float(point.x), float(point.z), float(-point.y)] for point in collision_points]
        digest = hashlib.sha256(json.dumps([rows, collision_faces], separators=(",", ":")).encode()).hexdigest()
        payload = {"format_version": 1, "asset_type": asset_type, "asset_name": name, "source_blend": bpy.data.filepath,
                   "source_objects": [obj.name for obj in objects], "origin_mode": origin_mode, "collision": collision,
                   "collision_source": collider.name if collider else "", "collision_faces": collision_faces,
                   "geometry_sha256": digest, "materials": pages.materials, "surfaces": rows, "notes": notes}
        path = folder / "request.json"
        path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
        return path, payload
    finally:
        for evaluated, _, _, _ in stored:
            evaluated.to_mesh_clear()
