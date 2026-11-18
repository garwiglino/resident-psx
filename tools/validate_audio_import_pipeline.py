"""Fresh-project test for new recordings; no artist assets or imports are written."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import re

ROOT=Path(__file__).resolve().parents[1]
fixture=Path(tempfile.mkdtemp(prefix="psx-audio-import-"))
library=re.search(r'windows\.x86_64\s*=\s*"res://([^"]+)"',(ROOT/"bin/psx_geometry.gdextension").read_text()).group(1)
for relative in ["scripts/audio/audio_preparation.gd","scripts/audio/audio_categories.gd","tools/prepare_audio_mix.py","bin/psx_geometry.gdextension",library]:
    destination=fixture/relative;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/relative,destination)
sources=["assets/audio/dialogs/1/1_Chapter_1.wav","assets/audio/dialogs/locked_doors_key/1_locked_doors.wav"]
for i,source in enumerate(sources):
    destination=fixture/f"assets/audio/dialogs/new_{i}.wav";destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/source,destination)
outside=fixture/"sounds/free_effect.wav";outside.parent.mkdir(parents=True);shutil.copy2(ROOT/"assets/audio/weapons/d_eagle/deagle_dry_01.wav",outside)
(fixture/"project.godot").write_text('config_version=5\n[application]\nconfig/name="PSX Audio Import Test"\n[audio]\ndriver/mix_rate=22050\n',encoding="utf-8")
(fixture/".godot").mkdir();(fixture/".godot/extension_list.cfg").write_text('res://bin/psx_geometry.gdextension\n')
(fixture/"validate.gd").write_text('''extends SceneTree
const Preparation=preload("res://scripts/audio/audio_preparation.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
    for i in 2:
        var path := "res://assets/audio/dialogs/new_%d.wav" % i
        var original := FileAccess.get_sha256(path)
        var stream := Preparation.import_stream(path,{"sample_rate":22050})
        assert(stream!=null and stream.get("mix_rate")==22050)
        assert(stream.get_meta("psx_category")==&"Voices")
        assert(stream.has_meta("psx_intercom_stream"))
        var radio: AudioStream=stream.get_meta("psx_intercom_stream")
        assert(radio.get("mix_rate")==22050 and absf(radio.get_length()-stream.get_length())<.0001)
        assert(FileAccess.get_sha256(path)==original)
    var generic := Preparation.import_stream("res://sounds/free_effect.wav",{})
    assert(generic!=null and generic.get("mix_rate")==22050 and generic.get_meta("psx_category")==&"SFX")
    print("NEW_AUDIO_IMPORT_OK");quit()
''',encoding="utf-8")
godot=r"C:\Users\sheensaw\MyApps\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
result=subprocess.run([godot,"--headless","--path",str(fixture),"--script","res://validate.gd"],capture_output=True,text=True,timeout=120)
print(result.stdout);print(result.stderr)
assert result.returncode==0 and "NEW_AUDIO_IMPORT_OK" in result.stdout
data=json.loads((fixture/"assets/audio/generated/mix/manifest.json").read_text(encoding="utf-8"))
for row in data["sources"].values():
    if row["category"]=="Voices":assert abs(row["after"]["lufs"]+18)<.2 and abs(row["radio_after"]["lufs"]+18)<.2
(ROOT/"docs/audio-new-import-validation.json").write_text(json.dumps({"ok":True,"fixture":str(fixture),"voices":2,"generic_sfx":1},indent=2))
print("NEW_AUDIO_PIPELINE_OK",fixture)
