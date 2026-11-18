"""Non-destructive body/outerwear export on the existing game skeleton."""
import argparse, bmesh, bpy, hashlib, json, math, pathlib, shutil, struct, sys
from mathutils import Matrix, Vector

ROOT=pathlib.Path(__file__).resolve().parents[1]
SOURCE=pathlib.Path(bpy.data.filepath)
parser=argparse.ArgumentParser()
parser.add_argument('--component',choices=['player'],default='player')
parser.add_argument('--jacket-alignment',choices=['source'],default='source')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
digest=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
scene=bpy.context.scene;scene.frame_set(1)
exec((ROOT/'tools/game_rig_bake.py').read_text())
rig=bpy.data.objects['rig'];jacket=bpy.data.objects.get('winter_jacket')
body_candidates=[ob for ob in bpy.data.objects if ob.type=='MESH'
    and any(mod.type=='ARMATURE' and mod.object==rig for mod in ob.modifiers)
    and any(mat and 'M_face_top' in mat.name for mat in ob.data.materials)]
assert len(body_candidates)==1,'Expected one skinned player mesh with facial materials'
body=body_candidates[0];source_mesh_name=body.name;body.name='cop_char'
C=Matrix.Rotation(-math.pi/2,4,'X')
body_path=ROOT/'assets/character/cop_player.glb'
jacket_path=ROOT/'assets/character/clothing/winter_jacket.glb'
original_hash=hashlib.sha256(body_path.read_bytes()).hexdigest()
backup=ROOT/'exports/backups'/('player_modular_before_'+original_hash[:10]);backup.mkdir(parents=True,exist_ok=True)
for path in [body_path,body_path.with_suffix('.json'),jacket_path,jacket_path.with_suffix('.json')]:
    if path.exists() and not (backup/path.name).exists():shutil.copy2(path,backup/path.name)
preserved={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
    for folder in ['assets/character/animations','assets/character/legacy_animations','assets/weapons']
    for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ['.glb','.json','.res','.tres']}
(backup/'preserved-assets.json').write_text(json.dumps(preserved,indent=2),encoding='utf8')
normalize=lambda name: ''.join(c for c in name.lower() if c.isalnum())
mask_slots=[i for i,m in enumerate(body.data.materials) if m and normalize(m.name).split('00')[0]=='mcoatmask']
# Blender currently uses the SAME datablock in old body slot 0 and the new,
# painted slot 3. Keep slot 0 as the body; the last slot is the explicit mask.
if len(mask_slots)>1:mask_slots=mask_slots[-1:]
mask_indices=[p.index for p in body.data.polygons if p.material_index in mask_slots]
mask_source='material_slots'
if mask_slots==[0] and len(mask_indices)>len(body.data.polygons)*.6:
    exec((ROOT/'tools/player_mask_reference.py').read_text(encoding='utf8'))
    mask_indices=recover_mask(body,C @ rig.matrix_world.inverted_safe() @ body.matrix_world,ROOT/'tools/reference/coat_mask_geometry.json')
    mask_source='geometry_reference';mask_slots=[]
mask_polygons=[body.data.polygons[i] for i in mask_indices]
assert mask_polygons,'Assign M_Coat_Mask to the covered body faces before export'
alignment=Vector((0,0,0))
bpy.context.view_layer.update()
bake=GameRigBake(rig,[body],1)
source_samples={}
def sample_mesh(ob):
    evaluated=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
    result=[list(C @ (rig.matrix_world.inverted_safe() @ evaluated.matrix_world @ v.co)) for v in mesh.vertices]
    evaluated.to_mesh_clear();return result
source_samples['cop_char']=sample_mesh(body)
overflow={body.name:[]}
def expand_overflow(target,mesh):
    for index,row in enumerate(target.weights[mesh.name]):
        if len(row)==1 and row[0][0] in target.vertex_bones:
            point,weights=target.vertex_bones[row[0][0]]
            target.weights[mesh.name][index]=weights
            overflow.setdefault(mesh.name,[]).append({'position':list(C @ point),'weights':weights})
    target.vertex_bones.clear()
expand_overflow(bake,body)
bake.sample(1,bpy.context.evaluated_depsgraph_get());game_rig,created=bake.build('base_reference')
body_export=created[0]
body_material=body.data.materials[0]
body_images=[node.image for node in body_material.node_tree.nodes if node.type=='TEX_IMAGE' and node.image]
body_image=body_images[0] if len(body_images)==1 else bpy.data.images.get('Cop_Body_Reference_256')
assert body_image and tuple(body_image.size)==(256,256)
materials={}
def material(name,image):
    if name not in materials:
        mat=bpy.data.materials.new(name);mat.use_nodes=True
        bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(1,1,1,1)
        bsdf.inputs['Roughness'].default_value=1;bsdf.inputs['Metallic'].default_value=0
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest'
        mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color']);materials[name]=mat
    return materials[name]
for index,source_mat in enumerate(list(body_export.data.materials)):
    part='top' if 'M_face_top' in source_mat.name else 'bottom' if 'M_face_bottom' in source_mat.name else None
    name='M_face_'+part if part else 'M_body'
    image=bpy.data.images.load(str(ROOT/'assets/character/face'/('face_'+part+'_neutral.png')),check_existing=True) if part else body_image
    body_export.data.materials[index]=material(name,image)
    if part:
        for polygon in body_export.data.polygons:
            if polygon.material_index==index:
                coordinates=[body_export.data.uv_layers.active.data[loop].uv for loop in polygon.loop_indices]
                # Tile 1001 remains the body/hair texture even when that polygon
                # currently shares a facial material. Expressions live in 1002.
                if all(uv.x<1-.00001 for uv in coordinates):
                    if materials.get('M_body') not in list(body_export.data.materials):body_export.data.materials.append(material('M_body',body_image))
                    polygon.material_index=list(body_export.data.materials).index(materials['M_body'])
                else:
                    for loop in polygon.loop_indices:body_export.data.uv_layers.active.data[loop].uv.x-=1.0
mask_export=body_export.copy();mask_export.data=body_export.data.copy();mask_export.name='cop_coat_mask'
scene.collection.objects.link(mask_export)
mask_export.data.materials.append(material('M_coat_mask',body_image));mask_material_index=len(mask_export.data.materials)-1
for mesh,want_mask in [(body_export,False),(mask_export,True)]:
    normals=[normal.vector.copy() for normal in mesh.data.corner_normals]
    data=bmesh.new();data.from_mesh(mesh.data)
    loop_id=data.loops.layers.int.new('export_corner_id')
    for face in data.faces:
        for index,loop in enumerate(face.loops):loop[loop_id]=mesh.data.polygons[face.index].loop_start+index
    remove=[face for face in data.faces if (face.index in mask_indices)!=want_mask]
    bmesh.ops.delete(data,geom=remove,context='FACES');data.to_mesh(mesh.data);data.free();mesh.data.update()
    identifiers=mesh.data.attributes.get('export_corner_id')
    mesh.data.normals_split_custom_set([normals[value.value] for value in identifiers.data])
    mesh.data.attributes.remove(identifiers)
    if want_mask:
        for polygon in mesh.data.polygons:polygon.material_index=mask_material_index
assert len(body_export.data.polygons)+len(mask_export.data.polygons)==len(body.data.polygons)
scene.frame_start=scene.frame_end=1
def export(path,meshes):
    path.parent.mkdir(parents=True,exist_ok=True)
    if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [game_rig]+meshes:ob.hide_set(False);ob.hide_viewport=False;ob.select_set(True)
    bpy.context.view_layer.objects.active=game_rig
    options=dict(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,
        export_animation_mode='SCENE',export_frame_range=True,export_force_sampling=True,export_optimize_animation_size=False,
        export_def_bones=True,export_rest_position_armature=True,export_all_influences=True,export_apply=False,export_yup=True,export_extras=True)
    supported=bpy.ops.export_scene.gltf.get_rna_type().properties
    bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in supported})
    raw=path.read_bytes();count=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+count])
    return len(gltf['skins'][0]['joints'])
stage=ROOT/'exports/modular_player_stage';stage.mkdir(parents=True,exist_ok=True)
outputs=[]
if args.component in ['all','player']:
    staged=stage/body_path.name;joints=export(staged,[body_export,mask_export])
    meta={'source':str(SOURCE),'source_sha256':digest,'base_mesh_only':True,'animations_preserved':True,
        'vertices':len(body.data.vertices),'polygons':len(body.data.polygons),'joint_count':joints,'face_uv_origin_exported':[0,0],
        'source_mesh_name':source_mesh_name,'coat_mask_source':mask_source,'coat_mask_polygon_indices':mask_indices,
        'overflow_skin':overflow['cop_char'],'source_sample':source_samples['cop_char'],'skin_meshes':['cop_char','cop_coat_mask'],
        'split_normals_preserved':True,
        'coat_mask_source_slots':mask_slots,'coat_mask_polygons':len(mask_export.data.polygons),
        'face_top_polygons':sum(body_export.data.materials[p.material_index].name.startswith('M_face_top') for p in body_export.data.polygons),
        'face_bottom_polygons':sum(body_export.data.materials[p.material_index].name.startswith('M_face_bottom') for p in body_export.data.polygons),
        'face_expressions':'res://assets/character/face/expressions.json'}
    staged.with_suffix('.json').write_text(json.dumps(meta,indent=2),encoding='utf8');outputs.append((staged,body_path))
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==digest,'Artist saved the source during export; rerun to use that snapshot'
for relative,expected in preserved.items():assert hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()==expected,'Existing animation or gun asset changed: '+relative
for staged,destination in outputs:
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(staged,destination);shutil.copy2(staged.with_suffix('.json'),destination.with_suffix('.json'))
    print('MODULAR_CHARACTER_EXPORTED',json.dumps({'asset':str(destination),'source_sha256':digest,'joints':joints,'mask_faces':len(mask_export.data.polygons),'alignment':args.jacket_alignment}))
print('ARTIST_SOURCE_UNCHANGED',digest,'PRESERVED_ANIMATION_WEAPON_ASSETS',len(preserved))
