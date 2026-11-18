extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var level: Node3D=load("res://scenes/examples/inventory_demo.tscn").instantiate();root.add_child(level)
	var player: Node3D=load("res://scenes/player.tscn").instantiate();root.add_child(player)
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();root.add_child(renderer)
	renderer.editor_preview=true;renderer._geometry_root=level;renderer._prepare_canvas();renderer.cache_branch(level);renderer.cache_branch(player)
	var seen := {};var images := {};var groups := {}
	for entry in renderer.entries:
		var textures: Array=renderer.TexturePages.FaceTextures.pages(entry.face_part) if entry.face_part else [entry.texture]
		for texture: Texture2D in textures:
			if texture==renderer.blank or seen.has(texture.get_rid()):continue
			seen[texture.get_rid()]=true
			var image: Image=texture.get_image();if image.is_compressed():image.decompress()
			image.convert(Image.FORMAT_RGBA8);image.clear_mipmaps()
			var hash := str(image.get_size())+":"+str(hash(image.get_data()))
			images[hash]=true
			if not groups.has(hash):groups[hash]=[]
			groups[hash].append({"path":texture.resource_path,"node":str(entry.node.get_path()),"size":str(image.get_size())})
	var result := {"resources":seen.size(),"unique_images":images.size(),"groups":groups.values()}
	FileAccess.open("res://docs/texture-pages-diagnosis.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("TEXTURE_PAGES_DIAGNOSIS ",seen.size()," resources / ",images.size()," unique images")
	level.free();player.free();renderer.free();quit()
