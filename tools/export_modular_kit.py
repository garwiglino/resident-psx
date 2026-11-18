"""Export New_Modular from Blender in background mode, without saving the source.

Pass -- --output <folder> to stage the kit. The old window surround is reused
when the source catalogue contains only replacement window panels.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/blender_addons"))
from resident_psx_exporter.exporter import material_description, split_seam

BASE = ROOT / "assets/environment/modular_2m"
SOURCE = Path(bpy.data.filepath)
EPSILON = 1e-5
SOURCE_NAMES = {
    "floor": "floor",
    "ceiling": "ceiling",
    "wall_loop": "wall__loop",
    "wall_corner_in": "wall_corner_in",
    "wall_corner_out": "wall_corner_in.001",
    "wall_door": "wall_simple_door_frame",
    "wall_door_double": "wall_double_door_frame",
    "stairs_01": "stairs_01",
    "stairs_collision": "stairs_collision",
}
ALIASES = {"wall_loop_simple": "wall_loop", "door_glass": "door_02", "stairs": "stairs_01"}
JOINED_WALLS = {"wall_loop", "wall_door", "wall_door_double", "wall_loop_window"}
DOOR_PREFIXES = ("door_", "double_door_")


def godot(vector):
    return Vector((vector.x, vector.z, -vector.y))


def face_bounds(coords, image):
    w, h = image.size
    return (min(uv[0] for uv in coords) * w, min(uv[1] for uv in coords) * h,
            max(uv[0] for uv in coords) * w, max(uv[1] for uv in coords) * h)


def power_of_two(value):
    return 1 << max(0, math.ceil(math.log2(max(1.0, value - 1e-4))))


def page_rect(bounds):
    def axis(low, high):
        aligned = math.floor((low + 1e-4) / 64) * 64
        start = aligned if high - aligned <= 256 else math.floor(low + 1e-4)
        return start, power_of_two(high - start)

    x, w = axis(bounds[0], bounds[2])
    y, h = axis(bounds[1], bounds[3])
    if max(w, h) > 256:
        raise ValueError(f"UVs cover more than 256 texels on one axis: {bounds}")
    return x, y, w, h


def contains(rect, bounds):
    x, y, w, h = rect
    return (bounds[0] >= x - 1e-4 and bounds[1] >= y - 1e-4
            and bounds[2] <= x + w + 1e-4 and bounds[3] <= y + h + 1e-4)


def edges(rect):
    x, y, w, h = rect
    return x, y, x + w, y + h


def compact_rects(rects):
    rects = sorted(set(rects), key=lambda rect: (-rect[2] * rect[3], rect))
    pages = []
    for rect in rects:
        if not any(contains(page, edges(rect)) for page in pages):
            pages.append(rect)
    # Merge only when the union uses no more texels than the separate pages.
    while True:
        best = None
        for i, a in enumerate(pages):
            for j in range(i + 1, len(pages)):
                b = pages[j]
                ax, ay, ar, at = edges(a)
                bx, by, br, bt = edges(b)
                x, y = min(ax, bx), min(ay, by)
                w, h = power_of_two(max(ar, br) - x), power_of_two(max(at, bt) - y)
                saving = a[2] * a[3] + b[2] * b[3] - w * h
                if max(w, h) <= 256 and saving >= 0 and (best is None or saving > best[0]):
                    best = (saving, i, j, (x, y, w, h))
        if best is None:
            return sorted(pages)
        _, i, j, rect = best
        pages[i] = rect
        del pages[j]


def fix_shell_winding(mesh, axis):
    """Orient disconnected solid shells while leaving recessed jambs and ramps intact."""
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        bm.normal_update()
        remaining = set(bm.faces)
        while remaining:
            faces = [remaining.pop()]
            for face in faces:
                for edge in face.edges:
                    for other in edge.link_faces:
                        if other in remaining:
                            remaining.remove(other)
                            faces.append(other)
            vertices = {vertex for face in faces for vertex in face.verts}
            lower = min(vertex.co[axis] for vertex in vertices)
            upper = max(vertex.co[axis] for vertex in vertices)
            if upper - lower < EPSILON:
                continue
            exterior = [face for face in faces if abs(face.normal[axis]) > .99 and
                        min(abs(face.calc_center_median()[axis] - lower), abs(face.calc_center_median()[axis] - upper)) < EPSILON]
            if not exterior:
                continue
            middle = (lower + upper) / 2
            if sum(face.calc_area() * math.copysign(1, face.calc_center_median()[axis] - middle)
                   * face.normal[axis] for face in exterior) < 0:
                bmesh.ops.reverse_faces(bm, faces=faces)
        bm.to_mesh(mesh)
        mesh.update()
    finally:
        bm.free()


def read_module(name, obj, descriptions):
    if not name.startswith(DOOR_PREFIXES) and name != "stairs_01":
        return read_triangles(name, obj, obj.data, descriptions)
    mesh = obj.data.copy()
    try:
        fix_shell_winding(mesh, 2 if name == "stairs_01" else 1)
        return read_triangles(name, obj, mesh, descriptions)
    finally:
        bpy.data.meshes.remove(mesh)


def read_triangles(name, obj, mesh, descriptions):
    basis = obj.matrix_world.to_3x3()
    normal_matrix = basis.inverted().transposed()
    points = [basis @ vertex.co for vertex in mesh.vertices]
    if name.startswith(DOOR_PREFIXES):
        ground = min(point.z for point in points)
        for point in points:
            point.z -= ground
    elif name in {"stairs_01", "stairs_collision"}:
        # The slope is the datum. Both origins retain their authored relative position.
        origin = bpy.data.objects["stairs_collision"].matrix_world.translation
        offset = obj.matrix_world.translation - origin
        for point in points:
            point += offset
    normals = []
    faces = []
    signatures = {}
    for face in mesh.polygons:
        normal = (normal_matrix @ face.normal).normalized()
        if name == "ceiling" and normal.z > 0:
            normal.negate()
        signature = tuple(sorted(tuple(round(v, 5) for v in points[i]) for i in face.vertices))
        signatures.setdefault(signature, []).append(normal)
        normals.append((normal, signature))
    for face, (normal, signature) in zip(mesh.polygons, normals):
        material = obj.material_slots[face.material_index].material if face.material_index < len(obj.material_slots) else None
        key = material.as_pointer() if material else 0
        if key not in descriptions:
            descriptions[key] = material_description(material)
        desc = descriptions[key]
        uv_layer = mesh.uv_layers.get(desc["uv_map"]) if desc["uv_map"] else mesh.uv_layers.active
        if desc["image"] and not uv_layer:
            raise ValueError(f"{obj.name}: {desc['name']} needs a UV map")
        uv = {i: tuple(uv_layer.data[i].uv) if uv_layer else (0.0, 0.0) for i in face.loop_indices}
        coords = np.asarray(list(uv.values()))
        vertices = np.asarray([list(points[mesh.loops[i].vertex_index]) for i in uv])
        gradient = np.linalg.pinv(vertices - vertices.mean(axis=0)) @ (coords - coords.mean(axis=0))
        thin = name in JOINED_WALLS and abs(normal.y) > .99 and all(abs(points[i].y) < EPSILON for i in face.vertices)
        if name in {"wall_corner_in", "wall_corner_out"}:
            thin = any(abs(normal[axis]) > .99 and all(abs(abs(points[i][axis]) - 1) < EPSILON
                       for i in face.vertices) for axis in (0, 1))
        two_sided = (thin or desc["glass"]) and not any(other.dot(normal) < -.99 for other in signatures[signature])
        bounds = None
        if desc["image"]:
            # Include the UVs reached by the existing Godot miter at a T or corner.
            samples = list(uv.values())
            if name in JOINED_WALLS:
                half = 2.0 if name == "wall_door_double" else 1.0
                for index, coord in uv.items():
                    point = points[mesh.loops[index].vertex_index]
                    if abs(point.x) >= half - .11001:
                        for sign in (-1, 0, 1):
                            target = math.copysign(half - sign * abs(point.y), point.x)
                            samples.append(tuple(np.asarray(coord) + gradient[0] * (target - point.x)))
            bounds = face_bounds(samples, desc["image"])
        faces.append((desc, normal, uv, gradient[0], two_sided, bounds))

    triangles = []
    mesh.calc_loop_triangles()
    mirrored = basis.determinant() < 0
    for tri in mesh.loop_triangles:
        desc, normal, uv, gradient, two_sided, bounds = faces[tri.polygon_index]
        flip_ceiling = name == "ceiling" and (normal_matrix @ tri.normal).z > 0
        order = list(tri.loops) if mirrored != flip_ceiling else [tri.loops[0], tri.loops[2], tri.loops[1]]
        rows = [(godot(points[mesh.loops[i].vertex_index]), godot(normal), uv[i]) for i in order]
        pieces = split_seam(rows) if name in JOINED_WALLS else [rows]
        for piece in pieces:
            if (piece[1][0] - piece[0][0]).cross(piece[2][0] - piece[0][0]).length_squared < 1e-16:
                continue
            triangles.append((desc, gradient, bounds, piece))
            if two_sided:
                triangles.append((desc, gradient, bounds, [(p, -n, uv) for p, n, uv in reversed(piece)]))
    return triangles


def save_page(image, rect, name, folder, pixels):
    width, height = image.size
    x, y, w, h = rect
    crop = pixels[np.ix_(np.arange(y, y + h) % height, np.arange(x, x + w) % width)].copy()
    page = bpy.data.images.new(name, width=w, height=h, alpha=True)
    try:
        page.colorspace_settings.name = image.colorspace_settings.name
        page.pixels.foreach_set(crop.ravel())
        page.update()
        page.filepath_raw = str(folder / (name + ".png"))
        page.file_format = "PNG"
        page.save()
    finally:
        bpy.data.images.remove(page)


def surface_row():
    return {key: [] for key in ("vertices", "normals", "uv", "uv_dx", "source_uv", "source_materials")}


def retain_window_frame(report, previous, folder):
    old = json.loads((previous / "kit_source.json").read_text(encoding="utf-8-sig"))
    module = old["modules"]["wall_loop_window"]
    surfaces = {}
    for old_index, surface in module["surfaces"].items():
        old_material = old.get("materials", [])
        page_index = old_material[int(old_index)]["page"] if old_material else int(old_index)
        old_page = dict(old["pages"][page_index])
        old_page.setdefault("atlas", "download (54).png")
        old_page.setdefault("atlas_size", [1024, 1024])
        old_page.setdefault("atlas_file", "source_atlas.png")
        page = next((i for i, existing in enumerate(report["pages"]) if existing["file"] == old_page["file"]), None)
        if page is None:
            page = len(report["pages"])
            report["pages"].append(old_page)
            if previous.resolve() != folder.resolve():
                (folder / old_page["file"]).write_bytes((previous / old_page["file"]).read_bytes())
        material = len(report["materials"])
        description = dict(old_material[int(old_index)]) if old_material else {"name": old_page["name"], "color": [1, 1, 1, 1]}
        report["materials"].append({**description, "page": page})
        surfaces[str(material)] = surface
    report["modules"]["wall_loop_window"] = {**module, "surfaces": surfaces}
    report["retained_modules"].append("wall_loop_window")


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--output", type=Path, default=BASE)
    args.add_argument("--previous", type=Path, default=BASE)
    options = args.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    folder = options.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    collection = next(c for c in bpy.data.collections if c.name.casefold().replace("_", " ") == "new modular")
    source_objects = {obj.name: obj for obj in collection.all_objects if obj.type == "MESH"}
    names = dict(SOURCE_NAMES)
    for i in ("01", "02", "03"):
        for prefix in ("door_", "double_door_left_", "double_door_right_"):
            names[prefix + i] = prefix + i
    objects = {module: source_objects[name] for module, name in names.items()}
    for name, source in {"window_glass": "window_glass.001", "window_condemned": "window_condemned"}.items():
        objects[name] = bpy.data.objects[source]
    if "wall_loop_window" in source_objects:
        objects["wall_loop_window"] = source_objects["wall_loop_window"]

    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    report = {"source": str(SOURCE), "collection": collection.name, "sha256": digest,
              "cell_size": 2, "wall_height": 3, "modules": {}, "pages": [], "materials": [],
              "retained_modules": []}
    descriptions = {}
    modules = {name: read_module(name, obj, descriptions) for name, obj in objects.items()}
    regions = {}
    page_bounds = {}
    for name, triangles in modules.items():
        for desc, _, bounds, _ in triangles:
            if bounds is not None:
                image = desc["image"]
                try:
                    regions.setdefault(image, set()).add(page_rect(bounds))
                    page_bounds.setdefault(image, set()).add(bounds)
                except ValueError as exc:
                    raise ValueError(f"{name}, {image.name}: {exc}") from exc

    page_indices = {}
    for image, rects in sorted(regions.items(), key=lambda entry: entry[0].name):
        width, height = image.size
        pixels = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        pixels = pixels.reshape(height, width, 4)
        if not image.packed_file:
            raise ValueError(f"{image.name} is not packed")
        (folder / image.name).write_bytes(image.packed_file.data)
        page_indices[image] = []
        compact = compact_rects(rects)
        used = {min((rect for rect in compact if contains(rect, bounds)), key=lambda rect: rect[2] * rect[3])
                for bounds in page_bounds[image]}
        for rect in sorted(used):
            name = f"new_{Path(image.name).stem}_{'_'.join(map(str, rect))}"
            save_page(image, rect, name, folder, pixels)
            page_indices[image].append((rect, len(report["pages"])))
            report["pages"].append({"name": name, "file": name + ".png", "rect": rect, "texel_scale": 1,
                                    "atlas": image.name, "atlas_size": [width, height], "atlas_file": image.name})

    materials = {}
    for name, triangles in modules.items():
        surfaces = {}
        low = [math.inf] * 3
        high = [-math.inf] * 3
        for desc, gradient, bounds, triangle in triangles:
            image = desc["image"]
            page = -1
            color = tuple(desc["color"])
            if image:
                rect, page = min(((rect, i) for rect, i in page_indices[image] if contains(rect, bounds)),
                                 key=lambda row: row[0][2] * row[0][3])
                x, y, w, h = rect
                width, height = image.size
                dx = [float(gradient[0] * width / w), float(-gradient[1] * height / h)]
            else:
                dx = [0.0, 0.0]
            transparent = desc["glass"] or color[3] < .999
            key = (page, color, transparent)
            if key not in materials:
                materials[key] = len(report["materials"])
                label = report["pages"][page]["name"] if page >= 0 else ("modular_glass" if transparent else "modular_plain")
                if page >= 0 and transparent:
                    label += "_glass"
                report["materials"].append({"name": label, "page": page, "color": color, "transparent": transparent})
            surface = surfaces.setdefault(str(materials[key]), surface_row())
            surface["source_materials"].append(desc["name"])
            for point, normal, (u, v) in triangle:
                surface["vertices"].append([round(float(value), 8) for value in point])
                surface["normals"].append(list(normal))
                surface["uv"].append([(u * width - x) / w, 1 - (v * height - y) / h] if image else [u, 1 - v])
                surface["source_uv"].append([u, v])
                surface["uv_dx"].append(dx)
                for axis in range(3):
                    low[axis] = min(low[axis], point[axis])
                    high[axis] = max(high[axis], point[axis])
        if not surfaces:
            raise ValueError(f"{name} contains no usable triangle")
        report["modules"][name] = {"source_object": objects[name].name, "min": low, "max": high, "surfaces": surfaces}
    report["aliases"] = ALIASES
    if "wall_loop_window" not in objects:
        retain_window_frame(report, options.previous.resolve(), folder)
    report["source_unchanged_on_export"] = hashlib.sha256(SOURCE.read_bytes()).hexdigest() == digest
    (folder / "kit_source.json").write_text(json.dumps(report, separators=(",", ":")), encoding="utf-8")
    print(f"MODULAR_EXPORT_OK {len(modules)} modules, {len(report['pages'])} native pages")


if __name__ == "__main__":
    main()

