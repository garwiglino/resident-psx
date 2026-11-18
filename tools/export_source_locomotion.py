"""Restore the nine original idle/walk clips without modifying artist Blender files."""
import bpy, pathlib, runpy, sys, json, hashlib, shutil, datetime
ROOT=pathlib.Path(__file__).resolve().parents[1]
DOWNLOADS=pathlib.Path(r'C:\Users\sheensaw\Downloads')
jobs=[(DOWNLOADS/'cop_idle.blend','player_pistol_idle')]
jobs += [(DOWNLOADS/'cop_anims_walk.blend','player_walk_'+direction+'_pistol') for direction in
         ['forward','backward','strafe_left','strafe_right','forward_left','forward_right','backward_left','backward_right']]
backup=ROOT/'exports/backups'/('source_locomotion_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
backup.mkdir(parents=True)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
sources={str(path):digest(path) for path,_ in jobs}
protected=list((ROOT/'assets/character').glob('*.glb'))+list((ROOT/'assets/character/clothing').glob('*.glb'))+list((ROOT/'assets/weapons').glob('*.glb'))
before={str(path):digest(path) for path in protected}
report={'backup':str(backup),'source_hashes':sources,'protected_hashes_before':before,'clips':[]}
for source,clip in jobs:
    for suffix in ['.glb','.json']:
        path=ROOT/'assets/character/animations'/(clip+suffix)
        if path.exists():shutil.copy2(path,backup/path.name)
for index,(source,clip) in enumerate(jobs):
    print('SOURCE_EXPORT_BEGIN',index+1,len(jobs),clip,flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    sys.argv=['export_split_rig.py','--','--mode','player','--clip',clip,'--nla-strip',clip]
    runpy.run_path(str(ROOT/'tools/export_split_rig.py'),run_name='__main__')
    meta=json.loads((ROOT/'assets/character/animations'/(clip+'.json')).read_text())
    assert meta['source']==str(source)
    assert meta['source_sha256']==sources[str(source)]
    report['clips'].append(meta)
    print('SOURCE_EXPORT_DONE',index+1,len(jobs),clip,flush=True)
assert all(digest(pathlib.Path(path))==value for path,value in sources.items()),'Artist sources must remain intact'
after={str(path):digest(path) for path in protected}
assert after==before,'Player model, clothing and weapon must remain intact'
report['protected_hashes_after']=after
(ROOT/'docs/source-locomotion-export.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SOURCE_LOCOMOTION_EXPORT_OK: nine original clips; source, model, clothing and weapon unchanged',flush=True)
