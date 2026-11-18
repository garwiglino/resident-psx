extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func read_png(path: String) -> Image:
	var image := Image.new()
	assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK)
	return image
func run() -> void:
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/scene_kit.json"))
	var source := read_png("res://assets/environment/surfaces.png")
	var crops: Dictionary={}
	for page in metadata.texture_pages:
		var crop := read_png("res://assets/environment/"+page.file)
		var rect: Array=page.atlas_rect_bottom_left
		check(crop.get_width()==rect[2] and crop.get_height()==rect[3],"Crop has native dimensions: "+page.file)
		check(crop.get_width()<=256 and crop.get_height()<=256,"Crop fits a PSX page: "+page.file)
		var same := true
		for y in crop.get_height():
			for x in crop.get_width():
				var sx: int=posmod(x+int(rect[0]),source.get_width())
				var sy: int=posmod(y+source.get_height()-int(rect[1])-int(rect[3]),source.get_height())
				if crop.get_pixel(x,y)!=source.get_pixel(sx,sy):same=false
		check(same,"Every cropped texel matches the original atlas exactly: "+page.file)
		crops[page.file.get_basename()]=rect
	var kit=load("res://assets/environment/scene_kit.glb").instantiate()
	for part in metadata.parts:
		var mesh: MeshInstance3D=kit.find_child(part,true,false)
		var uv_min := Vector2(INF,INF)
		var uv_max := Vector2(-INF,-INF)
		var triangles := 0
		for surface in mesh.mesh.get_surface_count():
			var mat: StandardMaterial3D=mesh.mesh.surface_get_material(surface)
			check(crops.has(mat.resource_name),"Imported surface uses a cropped page: "+mat.resource_name)
			if not crops.has(mat.resource_name):continue
			var rect: Array=crops[mat.resource_name]
			var arrays := mesh.mesh.surface_get_arrays(surface)
			triangles+=mesh.mesh.surface_get_array_index_len(surface)/3
			for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
				# glTF flips V; reconstruct the original Blender atlas coordinates.
				var original := Vector2((uv.x*rect[2]+rect[0])/source.get_width(),((1.0-uv.y)*rect[3]+rect[1])/source.get_height())
				uv_min=uv_min.min(original);uv_max=uv_max.max(original)
		var original: Dictionary=metadata.parts[part]
		check(uv_min.distance_to(Vector2(original.uv_min[0],original.uv_min[1]))<.0001,"Original UV minimum preserved: "+part)
		check(uv_max.distance_to(Vector2(original.uv_max[0],original.uv_max[1]))<.0001,"Original UV maximum preserved: "+part)
		check(triangles==int(original.triangles),"Original topology preserved: "+part)
	kit.free()
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.psx_renderer.set_process(false)
	await create_timer(.1).timeout
	var checked := 0
	for entry in game.psx_renderer.entries:
		if not game.level.is_ancestor_of(entry.node):continue
		check(Vector2(entry.texture.get_size())==entry.logical_texture_size,"Runtime keeps native texel resolution: "+String(entry.node.get_parent().name))
		checked+=1
	check(checked>100,"Actual map uses native-resolution pages")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free()
	await process_frame
	print("ENVIRONMENT_TEXTURES_OK: exact source texels, original UV layout/topology, native-resolution PSX pages in the actual map" if failures.is_empty() else "ENVIRONMENT_TEXTURES_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
