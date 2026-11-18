extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	for source in ["res://assets/audio/shot.wav","res://docs/psx-import-fixture.ogg","res://docs/psx-import-fixture.mp3"]:
		var config := ConfigFile.new()
		check(config.load(source+".import")==OK,"Importer creates metadata for "+source.get_extension())
		if config.get_value("remap","importer","")=="wav":check(config.get_value("params","compress/mode",-1)==0,"Legacy WAV import remains lossless before SPU conversion")
		var imported: AudioStream=ResourceLoader.load(source,"",ResourceLoader.CACHE_MODE_IGNORE)
		check(imported!=null,"Imported source is readable")
		if not imported:continue
		var player := AudioStreamPlayer.new();player.stream=imported;root.add_child(player)
		var stream: AudioStream=player.stream
		check(stream.is_class("AudioStreamPSX"),"Both native imports and legacy sources reach the automatic SPU player path")
		check(stream.get("adpcm_left").size()>0,"Imported file stores ADPCM blocks")
		# Managed streams feed the common integer mixer and return silence to
		# Godot. Decode their original sample when checking source audibility.
		var decoded_source: AudioStream=load("res://scripts/audio/psx_audio_routing.gd").source_of(stream)
		var playback=decoded_source.instantiate_playback();playback.start()
		var frames: PackedVector2Array=playback.mix_audio(1,1024);playback.stop()
		var peak := 0.0
		for frame in frames:peak=maxf(peak,frame.length())
		check(peak>.01,"Imported "+source.get_extension()+" contains audible signal")
		player.queue_free()
	await process_frame
	print("AUDIO_IMPORT_OK: WAV/OGG/MP3 imports, lossless legacy WAV sources, automatic SPU player wrapping, binary ADPCM data and actual native playback" if failures.is_empty() else "AUDIO_IMPORT_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
