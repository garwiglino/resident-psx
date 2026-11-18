"""Read-only comparison of source Rigify poses and the older harmonized copies."""
import bpy, pathlib, json, math
ROOT = pathlib.Path(__file__).resolve().parents[1]
sources = [pathlib.Path(r'C:\Users\sheensaw\Downloads\cop_anims_walk.blend'),
           ROOT/'exports/blender/cop_anims_walk_harmonized.blend',
           pathlib.Path(r'C:\Users\sheensaw\Downloads\cop_idle.blend'),
           ROOT/'exports/blender/cop_idle_harmonized.blend']
report = []
for source in sources:
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    rig = bpy.data.objects['rig']
    ad = rig.animation_data
    ad.action = None
    ad.use_nla = True
    choices = [(track, strip) for track in ad.nla_tracks for strip in track.strips
               if strip.name.startswith('player_')]
    clips = []
    for selected, strip in choices:
        for track in ad.nla_tracks:
            track.mute = track != selected
            track.is_solo = False
        for other in selected.strips:
            other.mute = other != strip
        rows = []
        first, last = round(strip.frame_start), round(strip.frame_end)
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            ev = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            world = ev.matrix_world
            row = {'frame': frame, 'pelvis_m': (world @ ev.pose.bones['DEF-spine'].matrix).translation.z,
                   'knees_degrees': [], 'deform_knees_degrees': [], 'leg_length_ratios': []}
            for side in ['L', 'R']:
                thigh, shin = ev.pose.bones['ORG-thigh.'+side], ev.pose.bones['ORG-shin.'+side]
                hip, knee, ankle = world @ thigh.head, world @ shin.head, world @ shin.tail
                row['knees_degrees'].append(180-math.degrees((hip-knee).angle(ankle-knee)))
                # Game bones retain the DEF/B-bone anchors, not Rigify's ORG
                # control-chain endpoints. Compare the same anchors in Godot.
                dh, dk, da = [world @ ev.pose.bones[prefix+side].head for prefix in ['DEF-thigh.','DEF-shin.','DEF-foot.']]
                row['deform_knees_degrees'].append(180-math.degrees((dh-dk).angle(da-dk)))
                row['leg_length_ratios'].extend([(knee-hip).length/thigh.bone.length, (ankle-knee).length/shin.bone.length])
            rows.append(row)
        heights = [r['pelvis_m'] for r in rows]
        knees = [value for r in rows for value in r['knees_degrees']]
        lengths = [value for r in rows for value in r['leg_length_ratios']]
        deform_knees = [value for r in rows for value in r['deform_knees_degrees']]
        clips.append({'clip': strip.name, 'frames': [first,last], 'pelvis_mean_m': sum(heights)/len(heights),
                      'pelvis_first_m': heights[0], 'pelvis_last_m': heights[-1], 'pelvis_min_m': min(heights),
                      'pelvis_max_m': max(heights), 'knee_mean_degrees': sum(knees)/len(knees),
                      'knee_min_degrees': min(knees), 'knee_max_degrees': max(knees),
                      'deform_knee_mean_degrees': sum(deform_knees)/len(deform_knees),
                      'leg_length_ratio_min': min(lengths), 'leg_length_ratio_max': max(lengths)})
        print('POSE_AUDIT', source.name, json.dumps(clips[-1]), flush=True)
    report.append({'source': str(source), 'clips': clips})
(ROOT/'docs/locomotion-blender-audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('LOCOMOTION_BLENDER_AUDIT_OK: read-only, no Blender files saved',flush=True)
