extends SceneTree
func _initialize() -> void:
	var paths: Array[String]=[]
	for file in DirAccess.get_files_at("res://assets/character/face"):
		if file.ends_with(".png"):paths.append("res://assets/character/face/"+file)
	for file in DirAccess.get_files_at("res://assets/character"):
		if file.begins_with("cop_player_") and file.ends_with(".png"):paths.append("res://assets/character/"+file)
	for file in DirAccess.get_files_at("res://assets/character/clothing"):
		if file.ends_with(".png"):paths.append("res://assets/character/clothing/"+file)
	for path in paths:
		var config := ConfigFile.new()
		if config.load(path+".import")!=OK:continue
		config.set_value("params","compress/mode",0)
		config.set_value("params","mipmaps/generate",false)
		config.set_value("params","detect_3d/compress_to",0)
		config.set_value("params","process/fix_alpha_border",false)
		assert(config.save(path+".import")==OK)
	print("FACE_IMPORTS_OK: lossless, no mipmaps, no automatic 3D compression")
	quit()
