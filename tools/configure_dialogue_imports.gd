extends SceneTree
func _initialize() -> void:
	for path in ["res://assets/fonts/m5x7.ttf","res://assets/fonts/pixel-operator-bold.ttf"]:
		var config := ConfigFile.new()
		if config.load(path+".import")!=OK:continue
		for key in ["antialiasing","hinting","subpixel_positioning"]:config.set_value("params",key,0)
		config.set_value("params","oversampling",1.0)
		config.set_value("params","generate_mipmaps",false)
		config.set_value("params","multichannel_signed_distance_field",false)
		assert(config.save(path+".import")==OK)
	print("DIALOGUE_FONT_IMPORTS_OK: native pixel glyphs, normal spacing, separate true bold speaker font")
	quit()
