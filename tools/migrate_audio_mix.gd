extends SceneTree
const Preparation=preload("res://scripts/audio/audio_preparation.gd")
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var count := 0
	var args := OS.get_cmdline_user_args();var only := ""
	var selection := args.find("--source")
	if selection>=0 and selection+1<args.size():only=args[selection+1]
	for path: String in Preparation.entries():
		if not only.is_empty() and path!=only:continue
		var config := ConfigFile.new()
		if config.load(path+".import")!=OK:failures.append(path+": no import config");continue
		var destination: String=config.get_value("remap","path","")
		if destination.is_empty():failures.append(path+": no destination");continue
		var changed := int(config.get_value("params","sample_rate",0))!=22050
		config.set_value("params","sample_rate",22050)
		var options: Dictionary={}
		for key in config.get_section_keys("params"):options[key]=config.get_value("params",key)
		var converted := Preparation.import_stream(path,options)
		var result := ResourceSaver.save(converted,destination) if converted else ERR_INVALID_DATA
		if result!=OK:failures.append(path+": "+error_string(result));continue
		if changed:config.save(path+".import")
		count+=1
		var stream: AudioStream=ResourceLoader.load(destination,"AudioStream",ResourceLoader.CACHE_MODE_IGNORE)
		if not stream or not stream.is_class("AudioStreamPSX") or stream.get("mix_rate")!=22050:failures.append(path+": wrong sample format")
		if stream and stream.get_meta("psx_category",&"")!=StringName(Preparation.entries()[path].category):failures.append(path+": missing category metadata")
		if stream and stream.get_meta("psx_category",&"")==&"Voices" and not stream.has_meta("psx_intercom_stream"):failures.append(path+": missing leveled intercom sample")
	Routing.setup();root.get_node("PSXAudio").mix_profile.apply()
	if ResourceSaver.save(AudioServer.generate_bus_layout(),"res://default_bus_layout.tres")!=OK:failures.append("Could not save category buses")
	var layout_uid := String(ProjectSettings.get_setting("audio/buses/default_bus_layout",""))
	if layout_uid.begins_with("uid://"):
		var error := ResourceSaver.set_uid("res://default_bus_layout.tres",ResourceUID.text_to_id(layout_uid))
		if error!=OK:failures.append("Could not preserve the bus layout UID")
	var report := {"ok":failures.is_empty(),"errors":failures,"sources":count,"requested_rate":ProjectSettings.get_setting("audio/driver/mix_rate"),"host_rate":AudioServer.get_mix_rate(),"buses":AudioServer.bus_count}
	FileAccess.open("res://docs/audio-mix-migration.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("AUDIO_MIX_MIGRATION_OK " if failures.is_empty() else "AUDIO_MIX_MIGRATION_FAILED ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
