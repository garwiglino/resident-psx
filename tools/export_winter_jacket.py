"""Export the original skinned garment directly; no rebinding or weight remap."""
import bpy, hashlib, json, pathlib, shutil, struct
from mathutils import Matrix
import math
ROOT=pathlib.Path(__file__).resolve().parents[1]
source=pathlib.Path(bpy.data.filepath);digest=hashlib.sha256(source.read_bytes()).hexdigest()
scene=bpy.context.scene;rig=bpy.data.objects['rig'];jacket=bpy.data.objects['winter_jacket']
assert any(m.type=='ARMATURE' and m.object==rig for m in jacket.modifiers),'The original jacket must already be skinned to rig'
scene.frame_set(1);bpy.context.view_layer.update()
C=Matrix.Rotation(-math.pi/2,4,'X')
evaluated=jacket.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
samples=[list(C @ v.co) for v in mesh.vertices]
evaluated.to_mesh_clear()
original_groups=[[(jacket.vertex_groups[g.group].name,g.weight) for g in v.groups if g.weight>0] for v in jacket.data.vertices]
if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
for ob in [rig,jacket]:ob.hide_set(False);ob.select_set(True)
bpy.context.view_layer.objects.active=rig
path=ROOT/'assets/character/clothing/winter_jacket.glb'
path.parent.mkdir(parents=True,exist_ok=True)
staged=ROOT/'exports/modular_player_stage/winter_jacket_direct.glb';staged.parent.mkdir(parents=True,exist_ok=True)
options=dict(filepath=str(staged),export_format='GLB',use_selection=True,export_animations=False,
             export_def_bones=True,export_rest_position_armature=True,export_all_influences=True,
             export_apply=False,export_yup=True,export_extras=True)
supported=bpy.ops.export_scene.gltf.get_rna_type().properties
bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in supported})
raw=staged.read_bytes();count=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+count])
# Godot's Mesh import keeps at most eight influences. Retain every exported
# influence for the native PSX skinning path, using the GLB's mesh-local vertices.
binary=raw[28+count:]
def accessor(index):
    data=gltf['accessors'][index];view=gltf['bufferViews'][data['bufferView']]
    assert not data.get('sparse'),'Unexpected sparse garment accessor'
    code={5121:'B',5123:'H',5125:'I',5126:'f'}[data['componentType']]
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[data['type']]
    offset=view.get('byteOffset',0)+data.get('byteOffset',0)
    stride=view.get('byteStride',struct.calcsize('<'+code)*width)
    assert not data.get('normalized',False),'Unexpected normalized garment accessor'
    return [struct.unpack_from('<'+code*width,binary,offset+i*stride) for i in range(data['count'])]
joint_names=[gltf['nodes'][n]['name'] for n in gltf['skins'][0]['joints']]
overflow=[];seen=set();max_influences=0
for exported_mesh in gltf['meshes']:
    for primitive in exported_mesh['primitives']:
        attributes=primitive['attributes'];positions=accessor(attributes['POSITION'])
        sets=sorted(int(key[7:]) for key in attributes if key.startswith('JOINTS_'))
        joints=[accessor(attributes['JOINTS_'+str(s)]) for s in sets]
        weights=[accessor(attributes['WEIGHTS_'+str(s)]) for s in sets]
        for vertex,position in enumerate(positions):
            row=[(joint_names[j],w) for js,ws in zip(joints,weights) for j,w in zip(js[vertex],ws[vertex]) if w>0]
            max_influences=max(max_influences,len(row))
            if len(row)<=8:continue
            key=(position,tuple(row))
            if key in seen:continue
            seen.add(key);overflow.append({'position':position,'weights':row})
meta={'source':str(source),'source_sha256':digest,'vertices':len(jacket.data.vertices),'polygons':len(jacket.data.polygons),
      'direct_blender_skin':True,'weights_redistributed':False,'alignment_mode':'source','alignment_blender_m':[0,0,0],
      'source_sample':samples,'source_weights':original_groups,'skin_meshes':['winter_jacket'],
      'joint_count':len(gltf['skins'][0]['joints']),'joint_names':joint_names,
      'overflow_skin':overflow,'max_influences':max_influences,'shared_skeleton':True,'segment_weight_remap':{},'texture_size':[256,256]}
meta['bind_space']='rig_local'
meta['source_object_matrix']=[list(row) for row in jacket.matrix_world]
# The garment is attached to the game's rig directly. Its existing rig-space
# vertices must not receive the old object-origin translation a second time.
meta['bind_vertex_transform']=[list(row) for row in (C @ (rig.matrix_world.inverted_safe() @ jacket.matrix_world).inverted_safe() @ C.inverted_safe())]
assert hashlib.sha256(source.read_bytes()).hexdigest()==digest,'Source changed during export; rerun'
shutil.copy2(staged,path);path.with_suffix('.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
print('WINTER_JACKET_DIRECT_EXPORTED',json.dumps({'sha256':digest,'joints':meta['joint_count'],'weights_redistributed':False,'max_influences':max_influences,'overflow_vertices':len(overflow),'bounds_y':[min(v[1] for v in samples),max(v[1] for v in samples)]}))
