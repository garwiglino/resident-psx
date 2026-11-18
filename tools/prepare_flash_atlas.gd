extends SceneTree
func _initialize() -> void:
	var image := Image.load_from_file("res://exports/art/muzzle_flash_atlas_generated.png")
	assert(image and image.detect_alpha()!=Image.ALPHA_NONE,"Generated atlas needs real transparency")
	image.convert(Image.FORMAT_RGBA8)
	image.resize(256,256,Image.INTERPOLATE_LANCZOS)
	# Encode the same binary transparency used by the PSX cutout rasterizer.
	# Keep the original generated RGBA artwork in exports/art.
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			color.a=1.0 if color.a>=.5 else 0.0
			image.set_pixel(x,y,color if color.a>0 else Color(0,0,0,0))
	DirAccess.make_dir_recursive_absolute("res://assets/effects")
	assert(image.save_png("res://assets/effects/muzzle_flash_atlas.png")==OK)
	print("FLASH_ATLAS_READY: one RGBA page, 16 cells of 64x64")
	quit()
