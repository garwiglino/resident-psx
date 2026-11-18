"""One-time, text-only migration; keep every painted cell, lamp and map override."""
from pathlib import Path
import re, json, hashlib
root=Path(__file__).resolve().parents[1]
settings_script='res://scripts/levels/psx_level_settings.gd'
main_path=root/'scenes/main.tscn'
main=main_path.read_text(encoding='utf-8')
def blocks(text): return list(re.finditer(r'^\[node [^\n]+\]\n.*?(?=^\[node |^\[editable |\Z)',text,re.M|re.S))
def named(text,name): return next(b for b in blocks(text) if b.group().startswith(f'[node name="{name}" '))
def ext(text,id): return re.search(r'^\[ext_resource [^\n]* id="'+re.escape(id)+r'"\]\n',text,re.M).group()
def properties(block):
    return dict(re.findall(r'^(\w+) = (.+)$',block,re.M))
original_hash=hashlib.sha256(main.encode()).hexdigest()
player=named(main,'Player').group(); renderer=named(main,'PSXRenderer').group()
fog_fields={'fog_enabled','fog_start','fog_end','fog_color','draw_distance','ambient_light_color','color_tint','saturation','brightness'}
baseline={k:v for k,v in properties(renderer).items() if k in fog_fields}
# Keep the exact original Player instance overrides, rather than serializing
# all properties currently inherited from player.tscn as frozen overrides.
shared='[gd_scene format=3]\n\n'+ext(main,'1')+ext(main,'3')+ext(main,'4')
shared+='\n[node name="SessionJeu" type="Node3D"]\nscript = ExtResource("1")\n\n'+player+renderer
(root/'scenes/systemes_jeu.tscn').write_text(shared,encoding='utf8')
for b in [named(main,'Player'),named(main,'PSXRenderer')]: main=main.replace(b.group(),'')
for id in ['1','3','4']: main=main.replace(ext(main,id),'')
main=main.replace('[sub_resource ', '[sub_resource ',1)
first_node=next(iter(blocks(main)))
old_root=first_node.group()
new_root=re.sub(r' type="Node3D"','',old_root.splitlines()[0])
new_root=new_root[:-1]+' instance=ExtResource("100_session")]\nlegacy_couloir_content = true\n\n'
main=main.replace(old_root,new_root)
insert='[ext_resource type="PackedScene" path="res://scenes/systemes_jeu.tscn" id="100_session"]\n\n'
index=main.index('[sub_resource') if '[sub_resource' in main else main.index('[node')
main=main[:index]+insert+main[index:]
assert hashlib.sha256(main_path.read_text(encoding='utf8').encode()).hexdigest()==original_hash
main_path.write_text(main,encoding='utf8')
report={}
for relative in ['scenes/couloir_pieces.tscn','scenes/maps/modular_example.tscn']:
    path=root/relative; text=path.read_text(encoding='utf8'); previous=text
    audio=named(text,'AudioNiveau').group()
    source_id=properties(audio)['script'].split('"')[1]
    source_ext=ext(text,source_id)
    updated=re.sub(r' uid="[^"]+"','',source_ext)
    updated=re.sub(r'path="[^"]+"',f'path="{settings_script}"',updated)
    text=text.replace(source_ext,updated)
    overrides=baseline.copy()
    own_renderer=next((b.group() for b in blocks(text) if b.group().startswith('[node name="PSXRenderer" ')),None)
    if own_renderer:
        overrides.update({k:v for k,v in properties(own_renderer).items() if k in fog_fields})
        text=text.replace(own_renderer,'')
    updated_audio=audio.replace('name="AudioNiveau"','name="ReglagesNiveau"',1).rstrip()+'\n'
    for key,value in overrides.items():
        if key not in properties(updated_audio): updated_audio+=f'{key} = {value}\n'
    text=text.replace(audio,updated_audio+'\n')
    if 'modular_example' in relative:
        # Its profile was shared with the original couloir: copy the profile,
        # retaining external WAV references and independently owned layers.
        profile_id=properties(audio)['profile'].split('"')[1]
        profile_ext=ext(text,profile_id)
        old_path=re.search(r'path="([^"]+)"',profile_ext).group(1)
        new_path='res://assets/audio/levels/modular_example.tres'
        profile_text=(root/old_path.removeprefix('res://')).read_text(encoding='utf8')
        profile_text=re.sub(r' uid="[^"]+"','',profile_text,count=1)
        destination=root/new_path.removeprefix('res://')
        if not destination.exists(): destination.write_text(profile_text,encoding='utf8')
        new_ext=re.sub(r' uid="[^"]+"','',profile_ext).replace(old_path,new_path)
        text=text.replace(profile_ext,new_ext)
    assert path.read_text(encoding='utf8')==previous
    path.write_text(text,encoding='utf8')
    report[relative]={'lamps_before':previous.count('script = ExtResource("4_0bewc")'),
                      'lamps_after':text.count('script = ExtResource("4_0bewc")'), 'fog_overrides':overrides}
(root/'docs/level-settings-migration.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('LEVEL_SETTINGS_MIGRATED',json.dumps(report))
