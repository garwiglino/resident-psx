extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var file := FileAccess.get_file_as_string("res://default_bus_layout.tres")
	check(not file.contains('type="AudioEffect"'),"Default layout never instantiates the generic AudioEffect base")
	check(file.count('type="AudioEffectPSXReverb"')==2,"Both stored PS1 effects retain their native class")
	var layout: AudioBusLayout=load("res://default_bus_layout.tres")
	AudioServer.set_bus_layout(layout)
	var wet := AudioServer.get_bus_index(&"PSX Reverb")
	check(wet>0 and AudioServer.get_bus_index(&"PSX Dry")>0,"Saved send buses load successfully")
	check(AudioServer.get_bus_effect(0,0).is_class("AudioEffectPSXReverb") and is_zero_approx(AudioServer.get_bus_effect(0,0).get("wet")),"Master keeps native 16-bit output with zero reverb")
	check(AudioServer.get_bus_effect(wet,0).is_class("AudioEffectPSXReverb") and AudioServer.get_bus_effect(wet,0).get("wet")>.2,"Reverb send keeps its real native effect")
	var saved := "user://audio-bus-persistence.tres"
	check(ResourceSaver.save(AudioServer.generate_bus_layout(),saved)==OK,"Bus layout can be saved")
	var stored := FileAccess.get_file_as_string(saved)
	check(stored.count('type="AudioEffectPSXReverb"')==2 and not stored.contains('type="AudioEffect"'),"Saving preserves native classes rather than generic base resources")
	var restored: AudioBusLayout=ResourceLoader.load(saved,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE)
	AudioServer.set_bus_layout(restored)
	check(load("res://scripts/audio/psx_audio_routing.gd").setup(),"Replacing the bus layout reconnects the SPU backend")
	check(AudioServer.get_bus_effect(0,0).get("native_mixer"),"Reloaded master resumes integer voice mixing")
	await create_timer(.25).timeout
	check(AudioServer.get_bus_effect(0,0).has_method("set_wet"),"Serialized effects reload and instantiate on the audio server")
	FileAccess.open("res://docs/crash-2026-11-06/audio-bus-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"buses":AudioServer.bus_count},"\t"))
	print("AUDIO_BUS_PERSISTENCE_OK: startup layout, native effect classes, dry/wet sends, serialization and audio-server reload" if failures.is_empty() else "AUDIO_BUS_PERSISTENCE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
