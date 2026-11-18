@tool
extends RefCounted
const Categories=preload("res://scripts/audio/audio_categories.gd")
const MANIFEST := "res://assets/audio/generated/mix/manifest.json"
const SAMPLE_RATE := 22050
const STATE_KEY := &"psx_audio_preparation_cache"

static func entries(refresh := false) -> Dictionary:
	var stamp := FileAccess.get_modified_time(MANIFEST) if FileAccess.file_exists(MANIFEST) else 0
	var state: Dictionary=Engine.get_meta(STATE_KEY,{})
	if refresh or state.get("stamp",-1)!=stamp:
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if stamp else {}
		state={"stamp":stamp,"sources":data.get("sources",{}) if data is Dictionary else {}};Engine.set_meta(STATE_KEY,state)
	return state.get("sources",{})

static func ensure_prepared(source_file: String) -> bool:
	if source_file.contains("/generated/"):return true
	var row: Dictionary=entries().get(source_file,{})
	if row.get("sha256","")==FileAccess.get_sha256(source_file) and FileAccess.file_exists(row.get("pcm","")):return true
	# Authoring-time analysis only. The exported game needs no external tools.
	var python := String(ProjectSettings.get_setting("psx_audio/tools/python","C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"))
	if not FileAccess.file_exists(python):python="python"
	var output: Array=[]
	var result := OS.execute(python,PackedStringArray([ProjectSettings.globalize_path("res://tools/prepare_audio_mix.py"),"--source",ProjectSettings.globalize_path(source_file)]),output,true)
	entries(true)
	if result!=0:push_error("Preparation audio impossible pour "+source_file+": "+"".join(output));return false
	return true

static func pcm_for(source_file: String,radio := false) -> AudioStream:
	var row: Dictionary=entries().get(source_file,{})
	var path := String(row.get("radio_pcm" if radio else "pcm",source_file if not radio else ""))
	if path.is_empty():return null
	match path.get_extension().to_lower():
		"wav":return AudioStreamWAV.load_from_file(path,{"compress/mode":0})
		"ogg":return AudioStreamOggVorbis.load_from_file(path)
		"mp3":return AudioStreamMP3.load_from_file(path)
	return null

static func import_stream(source_file: String,options: Dictionary) -> AudioStream:
	source_file=ProjectSettings.localize_path(source_file)
	if not ClassDB.class_exists("AudioStreamPSX"):return null
	if not ensure_prepared(source_file):return null
	var source: AudioStream=pcm_for(source_file)
	if not source:return null
	var converted=ClassDB.instantiate("AudioStreamPSX")
	var requested := int(options.get("sample_rate",22050))
	var rate := mini(requested,22050) if requested>0 else 22050
	if not converted.configure_source(source,rate):return null
	# The prepared PCM has no RIFF sampler chunk. Recover original loop markers
	# in sample coordinates rather than silently losing them during preparation.
	if source_file.get_extension().to_lower()=="wav":
		var original := AudioStreamWAV.load_from_file(source_file,{"compress/mode":0})
		if original and original.loop_mode!=AudioStreamWAV.LOOP_DISABLED:
			converted.loop=true;converted.loop_begin=roundi(original.loop_begin*rate/float(original.mix_rate));converted.loop_end=roundi(original.loop_end*rate/float(original.mix_rate))
	var row: Dictionary=entries().get(source_file,{})
	converted.set_meta("psx_source_path",source_file);converted.set_meta("psx_category",StringName(row.get("category",Categories.for_path(source_file))))
	converted.set_meta("psx_mix_signature",row.get("signature",""))
	var radio: AudioStream=pcm_for(source_file,true)
	if radio:
		var encoded: AudioStream=ClassDB.instantiate("AudioStreamPSX")
		if not encoded.configure_source(radio,rate):return null
		encoded.adsr1=int(options.get("spu/adsr1",255));encoded.adsr2=int(options.get("spu/adsr2",8128))
		encoded.set_meta("psx_source_path",source_file);encoded.set_meta("psx_category",&"Voices");encoded.set_meta("psx_mix_signature",row.get("signature",""))
		encoded.resource_name="Intercom - "+source_file.get_file();converted.set_meta("psx_intercom_stream",encoded)
	if converted.has_method("set_adsr1"):
		converted.adsr1=int(options.get("spu/adsr1",255));converted.adsr2=int(options.get("spu/adsr2",8128))
	# Preserve embedded WAV loop markers unless the explicit loop option adds one.
	converted.loop=converted.loop or bool(options.get("loop",false))
	converted.resource_name=source_file.get_file()
	return converted
