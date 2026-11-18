extends SceneTree
var updated := 0
func _initialize() -> void:
	configure("res://assets/audio")
	print("PSX_AUDIO_LOSSLESS_WAV_IMPORTS_CONFIGURED ",updated);quit()
func configure(directory: String) -> void:
	for child in DirAccess.get_directories_at(directory):configure(directory.path_join(child))
	for file in DirAccess.get_files_at(directory):
		if file.get_extension().to_lower()!="wav":continue
		var path := directory.path_join(file)
		var config := ConfigFile.new()
		if config.load(path+".import")!=OK:continue
		if config.get_value("remap","importer","")!="wav":continue
		if int(config.get_value("params","compress/mode",0))==0:continue
		# Older editor sessions may keep Godot's WAV importer. Preserve PCM until
		# the runtime's cached SPU conversion, instead of adding QOA/IMA loss first.
		config.set_value("params","compress/mode",0)
		assert(config.save(path+".import")==OK)
		updated+=1
