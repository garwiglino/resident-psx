"""Author coherent Rigify pelvis/leg poses in copies of the artist's Blender files.

Root curves, foot goals, pole-control curves, clip timing and source files stay intact.
Only torso location, limb stretch switches and thigh IK scale keys are authored.
All reach calculations run here, offline; no leg solver is added to the game.
"""
import bpy, math, json, pathlib, hashlib, argparse, sys
from mathutils import Vector

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--height',type=float,default=.905)
parser.add_argument('--dry-run',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT=ROOT/'exports'/'blender';OUT.mkdir(parents=True,exist_ok=True)
SOURCES=[pathlib.Path(r'C:\Users\sheensaw\Downloads\cop_idle.blend'),pathlib.Path(r'C:\Users\sheensaw\Downloads\cop_anims_walk.blend')]
MIN_KNEE=12.0
MAX_SWAY=.08
BOB=.012
report={'target_mean_height':args.height,'minimum_knee_degrees':MIN_KNEE,'max_step_follow_m':MAX_SWAY,'files':[]}

def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:yield from bag.fcurves

def root_signature(action):
    rows=[]
    for c in curves(action):
        if c.data_path.startswith('pose.bones["root"]'):
            rows.append((c.data_path,c.array_index,[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in c.keyframe_points]))
    return hashlib.sha256(json.dumps(rows,sort_keys=True).encode()).hexdigest()

def closest_in_discs(point,discs):
    def inside(p):return all((p-c).length<=r+1e-6 for c,r in discs)
    if inside(point):return point.copy()
    candidates=[]
    for center,radius in discs:
        delta=point-center
        candidate=center+delta.normalized()*radius if delta.length>1e-10 else center.copy()
        if inside(candidate):candidates.append(candidate)
    (a,ra),(b,rb)=discs
    delta=b-a;distance=delta.length
    if distance>1e-9 and abs(ra-rb)<=distance<=ra+rb:
        along=(ra*ra-rb*rb+distance*distance)/(2*distance)
        across=math.sqrt(max(0,ra*ra-along*along))
        direction=delta/distance;normal=Vector((-direction.y,direction.x))
        candidates.extend([a+direction*along+normal*across,a+direction*along-normal*across])
    if not candidates:return None
    return min(candidates,key=lambda p:(p-point).length_squared)

def solve_xy(sample,height,preferred=None):
    pelvis=Vector(sample['pelvis'])
    point=pelvis.xy
    discs=[]
    for leg in sample['legs'].values():
        hip=Vector(leg['hip']);ankle=Vector(leg['ankle'])
        offset=hip-pelvis
        a,b=leg['rest_thigh'],leg['rest_shin']
        reach=math.sqrt(a*a+b*b+2*a*b*math.cos(math.radians(MIN_KNEE)))-.001
        dz=height+offset.z-ankle.z
        if abs(dz)>=reach:return None
        radius=math.sqrt(reach*reach-dz*dz)
        discs.append((ankle.xy-offset.xy,radius))
    result=closest_in_discs(preferred if preferred is not None else point,discs)
    if result is None or (result-point).length>MAX_SWAY+1e-6:return None
    return result

def height_cap(sample):
    low,high=sample['pelvis'][2]-.3,sample['pelvis'][2]+.15
    assert solve_xy(sample,low) is not None,'Foot goals are incompatible with the anatomical leg lengths'
    for _ in range(32):
        mid=(low+high)*.5
        if solve_xy(sample,mid) is None:high=mid
        else:low=mid
    return low-.001

def conservative_smooth(values,radius=2):
    # Every value entering the average has an erosion window containing i.
    # The smoothed cap therefore remains below the original reach limit.
    n=len(values)
    eroded=[min(values[(i+j)%n] for j in range(-radius,radius+1)) for i in range(n)]
    weights=[1,4,6,4,1]
    return [sum(eroded[(i+j)%n]*w for j,w in zip(range(-radius,radius+1),weights))/16 for i in range(n)]

def soft_min(a,b,width=.003):
    return min(a,b)-max(width-abs(a-b),0)**2/(4*width)

def plan(samples):
    # The last frame repeats the cycle endpoint; omit it when filtering.
    unique=samples[:-1]
    mean=sum(s['pelvis'][2] for s in unique)/len(unique)
    amplitude=max(abs(s['pelvis'][2]-mean) for s in unique)
    scale=min(1,BOB/max(amplitude,1e-9))
    shape=[(s['pelvis'][2]-mean)*scale for s in unique]
    caps=conservative_smooth([height_cap(s) for s in unique])
    assert sum(caps)/len(caps)>args.height+.001,('Mean height not feasible',sum(caps)/len(caps))
    low,high=args.height-.15,args.height+.15
    for _ in range(45):
        base=(low+high)*.5
        heights=[soft_min(base+bob,cap) for bob,cap in zip(shape,caps)]
        if sum(heights)/len(heights)<args.height:low=base
        else:high=base
    heights=[soft_min((low+high)*.5+bob,cap) for bob,cap in zip(shape,caps)]
    # Smooth the small fore/aft step-follow movement, then project into reach.
    positions=[solve_xy(s,h) for s,h in zip(unique,heights)]
    assert all(p is not None for p in positions),[(s['frame'],h,cap) for s,h,cap,p in zip(unique,heights,caps,positions) if p is None]
    smoothed=[sum(((positions[(i+j)%len(positions)]-Vector(unique[(i+j)%len(positions)]['pelvis']).xy)*w for j,w in [(-1,.25),(0,.5),(1,.25)]),Vector((0,0))) for i in range(len(positions))]
    positions=[solve_xy(s,h,Vector(s['pelvis']).xy+delta) for s,h,delta in zip(unique,heights,smoothed)]
    assert all(p is not None for p in positions)
    # Preserve the authored final-frame root and foot goals; solve its endpoint
    # separately so any source seam cannot make a leg unreachable.
    end_height=min(heights[0],height_cap(samples[-1])-.001)
    heights.append(end_height)
    positions.append(solve_xy(samples[-1],end_height))
    return [Vector((p.x,p.y,h)) for p,h in zip(positions,heights)]

def matrix_rows(matrix):return [list(row) for row in matrix]

def sample_rig(rig,frame):
    bpy.context.scene.frame_set(frame)
    ev=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
    world=ev.matrix_world
    torso=ev.pose.bones['torso']
    basis=world @ torso.matrix @ torso.matrix_basis.inverted()
    row={'frame':frame,'pelvis':list((world @ ev.pose.bones['DEF-spine'].matrix).translation),
        'root':matrix_rows(world @ ev.pose.bones['root'].matrix),'torso_local':list(torso.location),
        'torso_axes':matrix_rows(basis.to_4x4()),'feet':{},'legs':{}}
    for side in ['L','R']:
        thigh=ev.pose.bones['ORG-thigh.'+side];shin=ev.pose.bones['ORG-shin.'+side]
        hip=world @ thigh.head;knee=world @ shin.head;ankle=world @ shin.tail
        row['legs'][side]={'hip':list(hip),'knee':list(knee),'ankle':list(ankle),
            'rest_thigh':thigh.bone.length,'rest_shin':shin.bone.length,
            'bend_degrees':180-math.degrees((hip-knee).angle(ankle-knee)),
            'thigh_length':(knee-hip).length,'shin_length':(ankle-knee).length}
        for prefix in ['foot_ik.','thigh_ik_target.','DEF-foot.','DEF-toe.']:
            name=prefix+side
            row['feet'][name]=matrix_rows(world @ ev.pose.bones[name].matrix)
    return row

for source in SOURCES:
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene=bpy.context.scene;rig=bpy.data.objects['rig'];ad=rig.animation_data
    file_report={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'clips':[]}
    strips=[(t,s) for t in ad.nla_tracks for s in t.strips if s.name.startswith('player_')]
    assert strips,'Expected named player NLA strips'
    originals={}
    for chosen,strip in strips:
        for track in ad.nla_tracks:track.mute=track!=chosen;track.is_solo=False
        for other in chosen.strips:other.mute=other!=strip
        ad.action=None
        first,last=round(strip.frame_start),round(strip.frame_end)
        assert first==1 and last==121 and strip.scale==1,'Preserve source frame/strip timing'
        samples=[sample_rig(rig,f) for f in range(first,last+1)]
        print('PLAN_PELVIS',strip.name,flush=True)
        originals[strip.name]={'samples':samples,'planned':plan(samples),'root_signature':root_signature(strip.action)}
    # Disable both the Rigify auto stretch and the underlying IK chain stretch.
    # Baked retargets also animate thigh_ik.scale; those keys must be unit scale.
    for side in ['L','R']:
        rig.pose.bones['thigh_parent.'+side]['IK_Stretch']=0.0
        for name in ['thigh_ik.','MCH-shin_ik.']:
            bone=rig.pose.bones[name+side];bone.ik_stretch=0.0
            for constraint in bone.constraints:
                if constraint.type=='IK':constraint.use_stretch=False
    from mathutils import Matrix
    for chosen,strip in strips:
        data=originals[strip.name];values=[]
        for sample,point in zip(data['samples'],data['planned']):
            delta=point-Vector(sample['pelvis'])
            axes=Matrix(sample['torso_axes']).to_3x3()
            values.append(Vector(sample['torso_local'])+axes.inverted() @ delta)
        action=strip.action
        changed=[]
        for curve in curves(action):
            is_torso=curve.data_path=='pose.bones["torso"].location'
            is_scale=curve.data_path in ['pose.bones["thigh_ik.%s"].scale'%s for s in ['L','R']]
            is_switch=curve.data_path in ['pose.bones["thigh_parent.%s"]["IK_Stretch"]'%s for s in ['L','R']]
            if not (is_torso or is_scale or is_switch):continue
            if is_torso:
                curve.keyframe_points.clear()
                curve.keyframe_points.add(len(values))
                for index,(key,value) in enumerate(zip(curve.keyframe_points,values)):
                    key.co=(index+1,value[curve.array_index]);key.interpolation='BEZIER'
                    key.handle_left_type='AUTO_CLAMPED';key.handle_right_type='AUTO_CLAMPED'
            else:
                value=1.0 if is_scale else 0.0
                for key in curve.keyframe_points:
                    key.co.y=value;key.handle_left.y=value;key.handle_right.y=value
            curve.update();changed.append((curve.data_path,curve.array_index))
        assert len(changed)==11,(strip.name,changed)
        assert root_signature(action)==data['root_signature'],'Root-motion curves changed'
        action['pelvis_mean_m']=args.height
        action['leg_stretch_disabled']=True
        action['height_harmonization_source']=source.name
        for track in ad.nla_tracks:track.mute=track!=chosen
        rig.update_tag();action.update_tag()
        actual=[sample_rig(rig,f) for f in range(1,122)]
        mean=sum(s['pelvis'][2] for s in actual[:-1])/120
        max_foot=0.0;max_foot_position=0.0;max_root=0.0;min_knee=180.0;min_scale=2.0;max_scale=0.0;max_sway=0.0;foot_errors={}
        for before,after in zip(data['samples'],actual):
            max_sway=max(max_sway,(Vector(before['pelvis']).xy-Vector(after['pelvis']).xy).length)
            max_root=max(max_root,max(abs(before['root'][i][j]-after['root'][i][j]) for i in range(4) for j in range(4)))
            for name in before['feet']:
                error=max(abs(before['feet'][name][i][j]-after['feet'][name][i][j]) for i in range(4) for j in range(4))
                foot_errors[name]=max(foot_errors.get(name,0),error)
                if name.startswith('foot_ik.'):max_foot=max(max_foot,error)
                if name.startswith(('DEF-foot.','DEF-toe.')):
                    max_foot_position=max(max_foot_position,math.sqrt(sum((before['feet'][name][i][3]-after['feet'][name][i][3])**2 for i in range(3))))
            for leg in after['legs'].values():
                min_knee=min(min_knee,leg['bend_degrees'])
                for bone in ['thigh','shin']:
                    ratio=leg[bone+'_length']/leg['rest_'+bone]
                    min_scale=min(min_scale,ratio);max_scale=max(max_scale,ratio)
        result={'clip':strip.name,'mean_before':sum(s['pelvis'][2] for s in data['samples'][:-1])/120,
            'mean_after':mean,'height_min':min(s['pelvis'][2] for s in actual),'height_max':max(s['pelvis'][2] for s in actual),
            'minimum_knee_degrees':min_knee,'leg_length_ratio_min':min_scale,'leg_length_ratio_max':max_scale,
            'foot_goal_max_matrix_error':max_foot,'foot_position_max_error_m':max_foot_position,'root_max_matrix_error':max_root,'max_step_follow_m':max_sway,
            'root_curves_sha256':data['root_signature'],'foot_matrix_errors':foot_errors}
        file_report['clips'].append(result)
        print('HARMONIZED_CLIP',json.dumps(result),flush=True)
        assert abs(mean-args.height)<.0001,(strip.name,'mean',mean)
        assert max_root<.000001,(strip.name,'root',max_root)
        assert max_foot<.000001,(strip.name,'foot goal',max_foot)
        assert max_foot_position<.001,(strip.name,'foot position',max_foot_position)
        assert min_knee>MIN_KNEE-.5,(strip.name,'knee',min_knee)
        assert .999<min_scale and max_scale<1.001,(strip.name,'stretch',min_scale,max_scale)
    first_track,first_strip=strips[0]
    for track in ad.nla_tracks:track.mute=track!=first_track
    scene.frame_set(1)
    output=OUT/(source.stem+'_harmonized.blend')
    file_report['output']=str(output)
    if not args.dry_run:
        assert hashlib.sha256(source.read_bytes()).hexdigest()==file_report['source_sha256'],'Source changed during authoring; inspect before exporting'
        bpy.ops.wm.save_as_mainfile(filepath=str(output),copy=True,check_existing=False)
        file_report['output_sha256']=hashlib.sha256(output.read_bytes()).hexdigest()
    report['files'].append(file_report)
(ROOT/'docs'/'pelvis-harmonization.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('PELVIS_HARMONIZATION_OK',json.dumps({'height':args.height,'files':[f['output'] for f in report['files']]}),flush=True)
