"""Blender background exporter: sampled Rigify character + independent local weapon.
Never saves the artist's source file. Use Exporter-Animations.ps1.
"""
import bpy,sys,pathlib,argparse,json,struct,math,re,shutil,hashlib
from mathutils import Matrix,Vector,Quaternion

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--mode',choices=['both','player','weapon'],default='both')
parser.add_argument('--clip',default='')
parser.add_argument('--start',type=int)
parser.add_argument('--end',type=int)
parser.add_argument('--update-base',action='store_true')
parser.add_argument('--template',action='store_true')
parser.add_argument('--nla-strip',default='')
parser.add_argument('--pose-frame',type=int,help='Hold this source frame throughout the exported clip')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
scene=bpy.context.scene
source_path=bpy.data.filepath
source_digest=hashlib.sha256(pathlib.Path(source_path).read_bytes()).hexdigest()
rig=bpy.data.objects.get('rig')
gun=bpy.data.objects.get('gun_amature')
animation_owner=gun if args.mode=='weapon' or rig is None else rig
if args.nla_strip and animation_owner:
    matches=[(t,s) for t in animation_owner.animation_data.nla_tracks for s in t.strips if s.name==args.nla_strip]
    assert len(matches)==1,'NLA strip not found or ambiguous: '+args.nla_strip
    selected_track,selected_strip=matches[0]
    for track in animation_owner.animation_data.nla_tracks:
        track.mute=track!=selected_track
        track.is_solo=False
    for strip in selected_track.strips:strip.mute=strip!=selected_strip
    animation_owner.animation_data.action=None
    animation_owner.animation_data.use_nla=True
    if not args.clip:args.clip=selected_strip.name
    if args.start is None:args.start=round(selected_strip.frame_start)
    if args.end is None:args.end=round(selected_strip.frame_end)
if args.mode=='both' and rig is None:args.mode='weapon'
first=args.start if args.start is not None else scene.frame_start
last=args.end if args.end is not None else scene.frame_end
assert last>=first,'Invalid frame range'
if not args.nla_strip and animation_owner and animation_owner.animation_data:
    strips=[s for t in animation_owner.animation_data.nla_tracks if not t.mute for s in t.strips if not s.mute and s.frame_end>=first and s.frame_start<=last]
    assert len(strips)<=1,'Several active NLA strips: choose one with -NlaStrip to avoid mixing animations.'
fps=scene.render.fps/scene.render.fps_base
scene.frame_start=first;scene.frame_end=last
C=Matrix.Rotation(-math.pi/2,4,'X')

def matrix_rows(m):return [list(row) for row in m]
def active_name(obj):
    ad=obj.animation_data if obj else None
    if ad and ad.action:return ad.action.name
    if ad:
        strips=[s for t in ad.nla_tracks if not t.mute for s in t.strips if s.frame_end>=first and s.frame_start<=last]
        if len(strips)==1:return strips[0].name
    return pathlib.Path(source_path).stem
clip=re.sub(r'[^a-zA-Z0-9_\-]+','_',args.clip or active_name(rig if args.mode!='weapon' else gun)).strip('_')
loop=args.pose_frame is not None or any(word in clip.lower() for word in ['idle','walk','run','strafe','backward'])
report={'source':source_path,'clip':clip,'first':first,'last':last,'fps':fps,'duration':(last-first)/fps,'loop':loop,'samples':[],'files':[]}
samples=sorted(set([first,last]+[round(first+(last-first)*v) for v in [.25,.5,.75]]))
player_meshes=[o for o in scene.objects if o.type=='MESH' and any(m.type=='ARMATURE' and m.object==rig for m in o.modifiers)] if rig else []
weapon_meshes=[o for o in scene.objects if o.type=='MESH' and any(m.type=='ARMATURE' and m.object==gun for m in o.modifiers)] if gun else []
assert player_meshes or args.mode=='weapon','No meshes bound to rig'
hand_name='DEF-hand.R'
gun_samples=[]
grip_ref=None
mesh_bind={}
game_bake=None
if args.mode in ['both','player']:
    exec((ROOT/'tools'/'game_rig_bake.py').read_text())
    game_bake=GameRigBake(rig,player_meshes,first)

# Evaluate BEFORE changing constraints or object transforms.
for f in range(first,last+1):
    scene.frame_set(args.pose_frame if args.pose_frame is not None else f);dep=bpy.context.evaluated_depsgraph_get()
    if game_bake:game_bake.sample(f,dep)
    if gun and args.mode!='player':
        ev=gun.evaluated_get(dep)
        gun_world=ev.matrix_world.copy()
        if rig:
            er=rig.evaluated_get(dep)
            hand_world=er.matrix_world @ er.pose.bones[hand_name].matrix
            relative=hand_world.inverted_safe() @ gun_world
            if grip_ref is None:grip_ref=relative.copy()
            root_delta=grip_ref.inverted_safe() @ relative
            if max(abs(root_delta[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<.00001:
                root_delta=Matrix.Identity(4)
        else:
            # Clean standalone weapon: object transform is already local to the grip.
            root_delta=gun_world.copy()
        if f==first:
            gun_world_ref=gun_world.copy()
            mesh_bind={ob.name:gun_world.inverted_safe() @ ob.matrix_world for ob in weapon_meshes}
        gun_samples.append((f,root_delta,{b.name:b.matrix.copy() for b in ev.pose.bones}))
    if f in samples:
        row={'frame':f,'time':(f-first)/fps,'meshes':{}}
        for ob in player_meshes+weapon_meshes:
            ev=ob.evaluated_get(dep);mesh=ev.to_mesh()
            row['meshes'][ob.name]=[list(C @ (ev.matrix_world @ v.co)) for v in mesh.vertices]
            ev.to_mesh_clear()
        report['samples'].append(row)

def read_glb(path):
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    data=json.loads(raw[20:20+length]);offset=20+length
    binary=raw[offset+8:]
    return data,binary

def save_glb(path,data,binary):
    encoded=json.dumps(data,separators=(',',':'),ensure_ascii=True).encode()
    encoded+=b' '*((-len(encoded))%4)
    binary+=b'\0'*((-len(binary))%4)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,12+8+len(encoded)+8+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)

def export_glb(path,selected,clip_name,deform_only):
    path.parent.mkdir(parents=True,exist_ok=True)
    # The artist may save the source while in Pose/Edit mode.
    if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for ob in selected:ob.hide_set(False);ob.hide_viewport=False;ob.select_set(True)
    bpy.context.view_layer.objects.active=selected[0]
    scene.frame_set(first)
    options=dict(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,
        export_animation_mode='SCENE',export_anim_scene_split_object=False,export_frame_range=True,
        export_force_sampling=True,export_bake_animation=True,export_def_bones=deform_only,
        export_rest_position_armature=True,export_optimize_animation_size=False,
        export_anim_slide_to_zero=True,export_frame_step=1,export_apply=False,export_yup=True)
    options['export_all_influences']=True
    supported=bpy.ops.export_scene.gltf.get_rna_type().properties
    bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in supported})
    data,binary=read_glb(path)
    for a in data.get('animations',[]):a['name']=clip_name
    save_glb(path,data,binary)
    meta=dict(clip=clip_name,loop=loop,fps=fps,start_frame=first,end_frame=last,duration=(last-first)/fps,source=source_path,source_sha256=source_digest)
    if args.pose_frame is not None:meta['pose_frame']=args.pose_frame
    if selected[0].name=='rig':
        meta.update(root_motion=game_bake.root_distance>.0001,root_motion_track='rig/Skeleton3D:RootMotion',
            root_motion_distance=game_bake.root_distance,average_speed=game_bake.root_distance/max((last-first)/fps,.001),
            root_motion_vector=list(C.to_3x3() @ (game_bake.samples[-1][1].translation-game_bake.samples[0][1].translation)))
    path.with_suffix('.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
    report['files'].append(str(path))
    return data,binary

def first_pose_node(data,binary,name):
    nodes=[dict(n) for n in data['nodes']]
    for a in data.get('animations',[]):
        for channel in a['channels']:
            sampler=a['samplers'][channel['sampler']];accessor=data['accessors'][sampler['output']]
            view=data['bufferViews'][accessor['bufferView']]
            count={'VEC3':3,'VEC4':4}.get(accessor['type'])
            if not count:continue
            offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
            if sampler.get('interpolation')=='CUBICSPLINE':offset+=count*4
            value=struct.unpack_from('<'+'f'*count,binary,offset)
            nodes[channel['target']['node']][channel['target']['path']]=value
    def walk(index,parent):
        node=nodes[index]
        if 'matrix' in node:m=Matrix([node['matrix'][i:i+4] for i in range(0,16,4)]).transposed()
        else:
            q=node.get('rotation',[0,0,0,1]);scale=node.get('scale',[1,1,1])
            m=Matrix.Translation(Vector(node.get('translation',[0,0,0]))) @ Quaternion((q[3],q[0],q[1],q[2])).to_matrix().to_4x4() @ Matrix.Diagonal((*scale,1))
        world=parent @ m
        if node.get('name')==name:return world
        for child in node.get('children',[]):
            found=walk(child,world)
            if found is not None:return found
        return None
    for index in data['scenes'][data.get('scene',0)]['nodes']:
        found=walk(index,Matrix.Identity(4))
        if found is not None:return found
    raise RuntimeError('Exported attachment bone not found: '+name)

if args.mode in ['both','player']:
    rig,player_meshes=game_bake.build(clip)
    report['bendy_segment_joints']=len(game_bake.segments)
    report['overflow_vertex_joints']=len(game_bake.vertex_bones)
    report['max_weight_trimmed_to_8']=game_bake.dropped_weight
    body_path=ROOT/'assets'/'character'/'animations'/(clip+'.glb')
    body_data,body_binary=export_glb(body_path,[rig]+player_meshes,clip,True)
    report['player_joint_count']=len(body_data['skins'][0]['joints'])
    if args.update_base:
        shutil.copy2(body_path,ROOT/'assets'/'character'/'cop_player.glb')
        shutil.copy2(body_path.with_suffix('.json'),ROOT/'assets'/'character'/'cop_player.json')

if args.mode in ['both','weapon']:
    assert gun and weapon_meshes,'No gun_amature and bound weapon meshes'
    # Normalize object transforms; keep all five existing weapon bones, including muzzle.
    for c in list(gun.constraints):gun.constraints.remove(c)
    gun.parent=None;gun.matrix_parent_inverse=Matrix.Identity(4);gun.animation_data_clear()
    gun.matrix_world=Matrix.Identity(4);gun.rotation_mode='QUATERNION'
    for ob in weapon_meshes:
        ob.data=ob.data.copy();ob.data.transform(mesh_bind[ob.name]);ob.data.update()
        ob.animation_data_clear();ob.parent=gun;ob.matrix_parent_inverse=Matrix.Identity(4);ob.matrix_basis=Matrix.Identity(4)
    for b in gun.pose.bones:
        b.rotation_mode='QUATERNION'
        for c in list(b.constraints):b.constraints.remove(c)
    for f,delta,poses in gun_samples:
        scene.frame_set(f)
        gun.location,gun.rotation_quaternion,gun.scale=delta.decompose()
        for prop in ['location','rotation_quaternion','scale']:gun.keyframe_insert(prop,frame=f)
        for b in gun.pose.bones:
            options={}
            if b.parent:options=dict(parent_matrix=poses[b.parent.name],parent_matrix_local=b.parent.bone.matrix_local)
            basis=b.bone.convert_local_to_pose(poses[b.name],b.bone.matrix_local,invert=True,**options)
            b.location,b.rotation_quaternion,b.scale=basis.decompose()
            for prop in ['location','rotation_quaternion','scale']:b.keyframe_insert(prop,frame=f)
    weapon_clip=('pistol_'+clip.removeprefix('player_pistol_')) if clip.startswith('player_pistol_') else clip
    if args.update_base and not gun.animation_data.action.name.startswith('pistol_'):weapon_clip='pistol_idle'
    gun.animation_data.action.name=weapon_clip
    weapon_path=ROOT/'assets'/'weapons'/'animations'/(weapon_clip+'.glb')
    weapon_data,weapon_binary=export_glb(weapon_path,[gun]+weapon_meshes,weapon_clip,False)
    report['weapon_joint_count']=len(weapon_data['skins'][0]['joints'])
    if args.update_base:
        shutil.copy2(weapon_path,ROOT/'assets'/'weapons'/'pistol.glb')
        shutil.copy2(weapon_path.with_suffix('.json'),ROOT/'assets'/'weapons'/'pistol.json')
        if rig and args.mode=='both':
            hand_exported=first_pose_node(body_data,body_binary,hand_name)
            socket=hand_exported.inverted_safe() @ (C @ gun_world_ref @ C.inverted())
            mount={'bone':hand_name,'transform_rows':matrix_rows(socket),'source':source_path,'reference_frame':first,
                'weapon_scene':'res://scenes/pistol.tscn','muzzle_bone':'b_muzzlespot','player_clip':clip,'weapon_clip':weapon_clip}
            (ROOT/'assets'/'weapons'/'pistol_mount.json').write_text(json.dumps(mount,indent=2),encoding='utf8')
            report['mount']=mount
    if args.template:
        for ob in list(bpy.data.objects):
            if ob not in [gun]+weapon_meshes:bpy.data.objects.remove(ob,do_unlink=True)
        scene.frame_set(first)
        template=ROOT/'exports'/'blender'/'pistol_animation_template.blend'
        template.parent.mkdir(parents=True,exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(template),copy=True,check_existing=False)
        report['files'].append(str(template))

(ROOT/'docs'/('split-export-'+clip+'.json')).write_text(json.dumps(report,indent=2),encoding='utf8')
print('SPLIT_EXPORT_OK',json.dumps({k:v for k,v in report.items() if k!='samples'}))
