extends SceneTree
func _initialize() -> void:
	var paths: Array[String]=["res://assets/character/cop_player.glb","res://assets/weapons/pistol.glb"]
	for directory in ["res://assets/character/animations","res://assets/weapons/animations"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".glb"):paths.append(directory+"/"+file)
	for path in paths:
		var config := ConfigFile.new()
		if config.load(path+".import")!=OK:
			config.set_value("remap","importer","scene")
			config.set_value("remap","importer_version",1)
			config.set_value("remap","type","PackedScene")
		var data: Dictionary=config.get_value("params","_subresources",{})
		var nodes: Dictionary=data.get("nodes",{})
		var settings: Dictionary=nodes.get("PATH:AnimationPlayer",{})
		settings["optimizer/enabled"]=false
		nodes["PATH:AnimationPlayer"]=settings
		data["nodes"]=nodes
		config.set_value("params","_subresources",data)
		config.set_value("params","animation/remove_immutable_tracks",false)
		config.set_value("params","meshes/generate_lods",false)
		config.set_value("params","meshes/create_shadow_meshes",false)
		config.set_value("params","meshes/force_disable_compression",true)
		assert(config.save(path+".import")==OK)
	print("ANIMATION_IMPORT_SETTINGS_OK")
	quit()
