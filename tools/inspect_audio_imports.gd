extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for path in ["res://assets/audio/dialogs/1/1_Chapter_2.wav","res://assets/audio/dialogs/sequences/first_enemy_kill/1_Chapter_2.wav"]:
		var config := ConfigFile.new();config.load(path+".import")
		var source: AudioStream=load(path)
		var direct: AudioStream=ResourceLoader.load(config.get_value("remap","path"),"",ResourceLoader.CACHE_MODE_IGNORE)
		print("AUDIO_IMPORT_DIAG ",path," source=",source.resource_path," ",source.get_meta_list()," direct=",direct.get_meta_list()," rates=",source.get("mix_rate"),"/",direct.get("mix_rate"))
		var prepared: AudioStream=load("res://scripts/audio/audio_preparation.gd").import_stream(path,{})
		print("FRESH_PREPARED ",prepared.get_meta_list())
		ResourceSaver.save(prepared,"res://exports/audio_mix_test/metadata.res")
		var again: AudioStream=ResourceLoader.load("res://exports/audio_mix_test/metadata.res","",ResourceLoader.CACHE_MODE_IGNORE)
		print("FRESH_RESTORED ",again.get_meta_list())
	quit()
