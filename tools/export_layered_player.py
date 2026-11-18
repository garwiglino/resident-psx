"""Stage the player or a separate skinned garment for the shared game rig."""
import argparse
import hashlib
import json
import math
import pathlib
import struct
import sys

import bpy
from mathutils import Matrix
from mathutils.bvhtree import BVHTree

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from game_rig_bake import GameRigBake

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=pathlib.Path)
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--garment', help='Export just this Blender mesh, using its exact object name')
mode.add_argument('--include-garment', action='append', default=[],
                  help='Export a garment alongside the player and include its skin joints in the shared rig')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
source = pathlib.Path(bpy.data.filepath)
digest = hashlib.sha256(source.read_bytes()).hexdigest()
conversion = Matrix.Rotation(-math.pi / 2, 4, 'X')
scene = bpy.context.scene
rig = bpy.data.objects['rig']


def read_glb(path):
    raw = path.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    return json.loads(raw[20:20 + size]), raw[28 + size:]


def accessor(document, binary, index):
    desc = document['accessors'][index]
    view = document['bufferViews'][desc['bufferView']]
    fmt = '<' + {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}[desc['componentType']] * {'SCALAR': 1, 'VEC3': 3}[desc['type']]
    offset = view.get('byteOffset', 0) + desc.get('byteOffset', 0)
    stride = view.get('byteStride', struct.calcsize(fmt))
    return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(desc['count'])]


def face_reference():
    # A merged Blender material can still contain the same two facial regions.
    # Recover their assignment from the current game mesh by position.
    doc, binary = read_glb(ROOT / 'assets/character/cop_player.glb')
    result = {}
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            name = doc['materials'][primitive['material']]['name']
            for part in ('top', 'bottom'):
                if not name.startswith('M_face_' + part):
                    continue
                points = accessor(doc, binary, primitive['attributes']['POSITION'])
                indices = [row[0] for row in accessor(doc, binary, primitive['indices'])]
                faces = [indices[i:i + 3] for i in range(0, len(indices), 3)]
                result[part] = BVHTree.FromPolygons(points, faces, all_triangles=True)
    return result


def base_image(material):
    shader = next(node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
    pending = [link.from_node for link in shader.inputs['Base Color'].links]
    visited = set()
    while pending:
        node = pending.pop(0)
        if node in visited:
            continue
        visited.add(node)
        if node.type == 'TEX_IMAGE' and node.image:
            return node.image
        pending.extend(link.from_node for socket in node.inputs for link in socket.links)
    raise ValueError(f'No base colour image on {material.name}')


def material(name, image):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = 1
    texture = result.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = image
    texture.interpolation = 'Closest'
    result.node_tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    return result


def bake_meshes(meshes, preserve_existing_garments=False):
    for obj in meshes:
        assert all(vertex.groups for vertex in obj.data.vertices), f'{obj.name} has unweighted vertices'
        if not any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers):
            # Detached pieces already carry their Blender weights.
            obj.modifiers.new('ExportSkin', 'ARMATURE').object = rig

    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    samples = {}
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        geometry = evaluated.to_mesh()
        transform = conversion @ rig.matrix_world.inverted_safe() @ evaluated.matrix_world
        samples[obj.name] = [list(transform @ vertex.co) for vertex in geometry.vertices]
        evaluated.to_mesh_clear()

    bake = GameRigBake(rig, meshes, 1)
    if preserve_existing_garments:
        # Reexporting the base must retain joints needed by already exported clothes.
        existing = set()
        for metadata_path in (ROOT / 'assets/character/clothing').rglob('*.json'):
            if metadata_path.stem not in args.include_garment:
                existing.update(json.loads(metadata_path.read_text(encoding='utf8')).get('joint_names', []))
        evaluated_rig = rig.evaluated_get(depsgraph)
        for name in existing:
            if not name.startswith('SEG-') or name in bake.segments:
                continue
            bone_name, number = name[4:].rsplit('-', 1)
            bone = evaluated_rig.pose.bones.get(bone_name)
            segment = int(number)
            if bone and bone.bone.use_deform and segment <= bone.bone.bbone_segments:
                bake.segments[name] = (bone_name, segment,
                    bone.bone.matrix_local @ bone.bbone_segment_matrix(segment, rest=True))
    overflow = {obj.name: [] for obj in meshes}
    for obj in meshes:
        for index, row in enumerate(bake.weights[obj.name]):
            if len(row) != 1 or row[0][0] not in bake.vertex_bones:
                continue
            point, weights = bake.vertex_bones[row[0][0]]
            bake.weights[obj.name][index] = weights
            overflow[obj.name].append({'position': list(conversion @ point), 'weights': weights})
    maximum_weights = {obj.name: max(map(len, bake.weights[obj.name])) for obj in meshes}
    bake.vertex_bones.clear()
    bake.sample(1, depsgraph)
    game_rig, exports = bake.build('base_reference')
    return game_rig, exports, samples, overflow, maximum_weights



def export(path, game_rig, selected, animations):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [game_rig, *selected]:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = game_rig
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        export_animations=animations, export_animation_mode='SCENE', export_frame_range=True,
        export_force_sampling=True, export_optimize_animation_size=False, export_def_bones=True,
        export_rest_position_armature=True, export_all_influences=True, export_apply=False, export_yup=True)
    document, _ = read_glb(path)
    return [document['nodes'][index]['name'] for index in document['skins'][0]['joints']]


def garment_metadata(mesh, source_name, name, joints, samples, overflow, maximum_weights):
    return dict(common, source_mesh_name=source_name, vertices=len(mesh.data.vertices),
                polygons=len(mesh.data.polygons), direct_blender_skin=True, alignment_mode='source',
                alignment_blender_m=[0, 0, 0], shared_skeleton=True, joint_count=len(joints), joint_names=joints,
                skin_meshes=[name], source_sample=samples[name], overflow_skin=overflow[name],
                max_influences=maximum_weights[name])


def write_metadata(name, data):
    assert digest == hashlib.sha256(source.read_bytes()).hexdigest(), 'Blender source changed during export'
    (args.output / (name + '.json')).write_text(json.dumps(data, indent=2), encoding='utf8')


def get_garment(name):
    assert pathlib.Path(name).name == name and name not in ('.', '..'), 'Use the exact Blender object name'
    obj = bpy.data.objects.get(name)
    assert obj and obj.type == 'MESH' and obj.data.polygons, f'No garment mesh named {name}'
    return obj


def export_garment(name):
    obj = get_garment(name)
    game_rig, meshes, samples, overflow, maximum_weights = bake_meshes([obj])
    joints = export(args.output / (name + '.glb'), game_rig, meshes, False)
    body_meta = json.loads((ROOT / 'assets/character/cop_player.json').read_text(encoding='utf8'))
    missing = set(joints) - set(body_meta['joint_names'])
    assert not missing, f'Garment needs joints absent from the exported player: {sorted(missing)}'
    metadata = garment_metadata(obj, name, name, joints, samples, overflow, maximum_weights)
    write_metadata(name, metadata)
    print('GARMENT_EXPORTED', json.dumps({'name': name, 'faces': metadata['polygons'],
        'joints': len(joints), 'maximum_weights': maximum_weights[name], 'source': digest}))


def export_player():
    body = bpy.data.objects['body_base']
    hair = bpy.data.objects['hairs']
    jackets = [obj for obj in scene.objects if obj.type == 'MESH' and len(obj.data.polygons)
               and any(mat and mat.name.startswith('M_WinterJacket') for mat in obj.data.materials)]
    assert len(jackets) == 1, 'Expected a single M_WinterJacket mesh in the source scene'
    jacket = jackets[0]
    reference = face_reference()
    body_image = base_image(body.data.materials['M_Body'])
    hair_image = base_image(hair.data.materials[hair.data.polygons[0].material_index])
    jacket_image = base_image(jacket.data.materials[jacket.data.polygons[0].material_index])
    original_names = [obj.name for obj in (body, hair, jacket)]
    meshes = [body, hair, jacket]
    for obj, name in zip(meshes, ('cop_char', 'cop_hair', 'winter_jacket')):
        obj.name = name
    garment_names = list(dict.fromkeys(args.include_garment))
    additional = [get_garment(name) for name in garment_names]
    assert not set(meshes).intersection(additional), 'Choose a garment separate from the base player and jacket'
    game_rig, exports, samples, overflow, maximum_weights = bake_meshes(meshes + additional, preserve_existing_garments=True)
    body_export, hair_export, jacket_export, *garment_exports = exports

    body_export.data.materials.clear()
    body_export.data.materials.append(material('M_body', body_image))
    for part in ('top', 'bottom'):
        image = bpy.data.images.load(str(ROOT / f'assets/character/face/face_{part}_neutral.png'), check_existing=True)
        body_export.data.materials.append(material(f'M_face_{part}', image))
    uv = body_export.data.uv_layers.active.data
    face_counts = {'top': 0, 'bottom': 0}
    for face in body_export.data.polygons:
        original = body.data.polygons[face.index]
        source_material = body.data.materials[original.material_index]
        face.material_index = 0
        if not source_material or 'M_face_' not in source_material.name:
            continue
        if all(uv[loop].uv.x < 1 - .00001 for loop in face.loop_indices):
            continue
        part = 'bottom' if 'M_face_bottom' in source_material.name else 'top'
        if part == 'top' and len(reference) == 2 and not any(
                'M_face_bottom' in body.data.materials[p.material_index].name
                for p in body.data.polygons if body.data.materials[p.material_index]):
            point = conversion @ face.center
            distances = {name: tree.find_nearest(point)[3] for name, tree in reference.items()}
            nearest = min(distances, key=distances.get)
            if distances[nearest] < .012:
                part = nearest
        face.material_index = 1 if part == 'top' else 2
        face_counts[part] += 1
        for loop in face.loop_indices:
            uv[loop].uv.x -= 1

    for obj, name, image in [(hair_export, 'M_hair', hair_image), (jacket_export, 'M_Winter_Jacket', jacket_image)]:
        obj.data.materials.clear()
        obj.data.materials.append(material(name, image))
        for face in obj.data.polygons:
            face.material_index = 0

    body_joints = export(args.output / 'cop_player.glb', game_rig, [body_export, hair_export], True)
    jacket_joints = export(args.output / 'winter_jacket.glb', game_rig, [jacket_export], False)
    assert set(jacket_joints) <= set(body_joints), 'Jacket needs joints absent from the game body'
    body_meta = dict(common, base_mesh_only=True, source_mesh_name=original_names[0],
                     vertices=len(body.data.vertices), polygons=len(body.data.polygons),
                     joint_count=len(body_joints), joint_names=body_joints,
                     skin_meshes=['cop_char', 'cop_hair'], source_sample=samples['cop_char'] + samples['cop_hair'],
                     overflow_skin=overflow['cop_char'] + overflow['cop_hair'],
                     face_top_polygons=face_counts['top'], face_bottom_polygons=face_counts['bottom'],
                     coat_mask_polygons=0, mask_mode='godot', body_texture=body_image.name, hair_texture=hair_image.name)
    jacket_meta = garment_metadata(jacket, original_names[2], 'winter_jacket', jacket_joints, samples, overflow, maximum_weights)
    jacket_meta['texture'] = jacket_image.name
    write_metadata('cop_player', body_meta)
    write_metadata('winter_jacket', jacket_meta)
    for name, source_mesh, garment in zip(garment_names, additional, garment_exports):
        joints = export(args.output / (name + '.glb'), game_rig, [garment], False)
        assert set(joints) <= set(body_joints), f'{name} needs joints absent from the game body'
        write_metadata(name, garment_metadata(source_mesh, name, name, joints, samples, overflow, maximum_weights))
    print('LAYERED_PLAYER_EXPORTED', json.dumps({'body_faces': body_meta['polygons'], 'face': face_counts,
        'jacket_faces': jacket_meta['polygons'], 'joints': len(body_joints), 'jacket_weights': jacket_meta['max_influences'],
        'source': digest, 'textures': [body_image.name, hair_image.name, jacket_image.name]}))


for name in ([args.garment] if args.garment else args.include_garment):
    # A modular piece uses its saved fit. Assembly animations may move its
    # object away from the player at the rig's reference frame.
    garment = get_garment(name)
    fitted_transform = garment.matrix_world.copy()
    garment.animation_data_clear()
    garment.matrix_world = fitted_transform
scene.frame_set(1)
scene.frame_start = scene.frame_end = 1
args.output.mkdir(parents=True, exist_ok=True)
common = {'source': str(source), 'source_sha256': digest, 'bind_space': 'rig_local',
          'weights_redistributed': False, 'split_normals_preserved': True}
if args.garment:
    export_garment(args.garment)
else:
    export_player()
