extends SceneTree
var files: Array[Dictionary]=[]
func _initialize() -> void:call_deferred("run")
func scan(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		if file.get_extension().to_lower() not in ["wav","ogg","mp3"]:continue
		var source := path.path_join(file)
		var stream: AudioStream=load(source)
		var settings := ConfigFile.new();settings.load(source+".import")
		var row := {"path":source,"class":stream.get_class() if stream else "missing","importer":settings.get_value("remap","importer",""),"sample_rate_option":settings.get_value("params","sample_rate",-1)}
		if stream:
			row["seconds"]=stream.get_length()
			if stream.is_class("AudioStreamPSX"):
				row["rate"]=stream.get("mix_rate");row["channels"]=1 if stream.get("adpcm_right").is_empty() else 2
				row["adpcm_bytes"]=stream.get("adpcm_left").size()+stream.get("adpcm_right").size()
			elif stream is AudioStreamWAV:
				row["rate"]=stream.mix_rate;row["channels"]=2 if stream.stereo else 1
				# Verify the actual runtime wrapper on representative short legacy files.
				if stream.get_length()<2:
					var prepared: AudioStream=root.get_node("PSXAudio").prepare(stream)
					row["runtime_class"]=prepared.get_class();row["runtime_rate"]=prepared.get("mix_rate")
		files.append(row)
	for directory in DirAccess.get_directories_at(path):scan(path.path_join(directory))
func run() -> void:
	scan("res://assets/audio")
	var classes := {};var rates := {};var buses: Array[Dictionary]=[]
	for row in files:
		classes[row["class"]]=classes.get(row["class"],0)+1
		var key := str(row.get("rate",0));rates[key]=rates.get(key,0)+1
	for index in AudioServer.get_bus_count():
		var effects: Array[Dictionary]=[]
		for slot in AudioServer.get_bus_effect_count(index):
			var effect := AudioServer.get_bus_effect(index,slot)
			effects.append({"class":effect.get_class(),"wet":effect.get("wet") if effect.is_class("AudioEffectPSXReverb") else null,"enabled":AudioServer.is_bus_effect_enabled(index,slot)})
		buses.append({"name":AudioServer.get_bus_name(index),"send":AudioServer.get_bus_send(index),"effects":effects})
	var report := {"mixer_hz":AudioServer.get_mix_rate(),"file_count":files.size(),"classes":classes,"rates":rates,"buses":buses,"files":files}
	FileAccess.open("res://docs/psx-audio-audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PSX_AUDIO_AUDIT: ",JSON.stringify({"mixer_hz":report.mixer_hz,"file_count":report.file_count,"classes":classes,"rates":rates}))
	quit()
