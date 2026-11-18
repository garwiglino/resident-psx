extends SceneTree
var failures: Array[String]=[]
var observations := {}
var renderer: Node
var viewport: SubViewport
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(count := 4) -> void:
	for frame in count:await process_frame
func texture(color: Color,size: int) -> ImageTexture:
	var image := Image.create(size,size,false,Image.FORMAT_RGBA8);image.fill(color);return ImageTexture.create_from_image(image)
func quad(parent: Node3D,at: Vector3,size: Vector2,tex: Texture2D) -> MeshInstance3D:
	var node := MeshInstance3D.new();var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-size.x,-size.y,0)*.5,Vector3(size.x,-size.y,0)*.5,Vector3(-size.x,size.y,0)*.5,Vector3(size.x,size.y,0)*.5])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2.ZERO,Vector2(1,0)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1,1,2,3])
	node.mesh=ArrayMesh.new();node.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new();material.albedo_texture=tex;node.material_override=material
	parent.add_child(node);node.position=at;return node
func capture() -> Image:
	for frame in 4:renderer.render_editor();await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func near_color(actual: Color,expected: Color,message: String) -> void:
	check(Vector3(actual.r-expected.r,actual.g-expected.g,actual.b-expected.b).length()<.015,message+": "+str(actual)+" vs "+str(expected))
func run() -> void:
	viewport=SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var scene := Node3D.new();viewport.add_child(scene)
	var camera := Camera3D.new();camera.fov=55;viewport.add_child(camera);camera.make_current()
	var grid := Node3D.new();scene.add_child(grid)
	var originals: Array[Texture2D]=[];var colors: Array[Color]=[];var nodes: Array[MeshInstance3D]=[]
	for i in 96:
		var color := Color8((i&31)*8,((i>>5)&31)*8,((i*7)%32)*8)
		var source := texture(color,128 if i<72 else 8);originals.append(source)
		colors.append(Color(float((i&31))/31,float((i>>5)&31)/31,float((i*7)%32)/31))
		nodes.append(quad(grid,Vector3((i%12-5.5)*.28,(i/12-3.5)*.28,-3),Vector2(.22,.22),source))
	var duplicate: Texture2D=ImageTexture.create_from_image(originals[0].get_image())
	var duplicate_node := quad(grid,Vector3(0,0,-6),Vector2(.1,.1),duplicate);duplicate_node.visible=false
	var cutout := Image.create(4,4,false,Image.FORMAT_RGBA8);cutout.fill(Color(0,0,0,0))
	for x in range(2,4):
		for y in 4:cutout.set_pixel(x,y,Color8(248,248,0))
	var foreground := quad(scene,Vector3(0,0,-2),Vector2(.8,.8),ImageTexture.create_from_image(cutout));foreground.visible=false
	var background := quad(scene,Vector3(0,0,-2.2),Vector2(1,1),texture(Color8(0,0,248),16));background.visible=false
	var source_bytes: PackedByteArray=originals[0].get_image().get_data()
	renderer=load("res://scripts/psx_renderer.gd").new();viewport.add_child(renderer);renderer.ambient_light_color=Color.WHITE;renderer.fog_enabled=false;renderer.dithering=false
	renderer.anime_style=null
	renderer.setup_editor(scene,camera)
	check(renderer.native_geometry!=null and renderer.native_geometry.get_statistics().version>=16,"Native renderer supports the full logical page address")
	check(renderer.texture_page_count==99 and renderer.extended_texture_pages,"More than 32 pages are registered without truncation and identical images share a page")
	check(renderer.atlas_texture.get_width()*renderer.atlas_texture.get_height()>1024*1024,"Internal atlas grows beyond the former fixed 1024 square capacity")
	var pages_by_node := {}
	for entry in renderer.entries:
		pages_by_node[entry.node]=entry.page_index
		check(entry.logical_texture_size.x<=256 and entry.logical_texture_size.y<=256,"Logical PSX texture dimensions stay at most 256")
	check(pages_by_node[nodes[0]]==pages_by_node[duplicate_node],"Separate texture resources with identical texels reuse one page")
	var image := await capture();image.save_png("res://docs/texture-pages-stress.png")
	for i in nodes.size():
		var at := Vector2i(camera.unproject_position(nodes[i].global_position))
		near_color(image.get_pixelv(at),colors[i],"Correct GPU texels for page "+str(pages_by_node[nodes[i]]))
	check(renderer.batch_count==1,"More than 32 textures retain the native ordering table and one atlas batch")
	# Facial animation selects complete page addresses too, without an atlas upload.
	var dynamic_entries: Array=[];var face_node: MeshInstance3D;var alternate: MeshInstance3D
	for candidate in nodes:
		if int(pages_by_node[candidate])>31:
			if not face_node:face_node=candidate
			else:alternate=candidate;break
	for entry in renderer.entries:
		var copy: Dictionary=entry.duplicate()
		if entry.node==face_node:copy.face_part=1;copy.face_pages=PackedInt32Array([pages_by_node[face_node],pages_by_node[alternate]])
		dynamic_entries.append(copy)
	var atlas_before: int=renderer.atlas_texture.get_instance_id();renderer.native_geometry.configure(dynamic_entries);face_node.set_meta("psx_face_top_frame",4)
	image=await capture()
	near_color(image.get_pixelv(Vector2i(camera.unproject_position(face_node.global_position))),colors[nodes.find(alternate)],"Animated face chooses the complete page address beyond 31")
	check(renderer.atlas_texture.get_instance_id()==atlas_before,"High-index expression change does not rebuild the atlas")
	face_node.remove_meta("psx_face_top_frame");renderer.native_geometry.configure(renderer.entries)
	var native: RefCounted=renderer.native_geometry;renderer.native_geometry=null
	image=await capture()
	for i in nodes.size():
		var at := Vector2i(camera.unproject_position(nodes[i].global_position))
		near_color(image.get_pixelv(at),colors[i],"Script fallback preserves full page "+str(pages_by_node[nodes[i]]))
	renderer.native_geometry=native
	grid.visible=false;foreground.visible=true;background.visible=true
	image=await capture();image.save_png("res://docs/texture-pages-cutout.png")
	check(pages_by_node[foreground]>31,"Cutout fixture uses a page beyond the legacy flag bits")
	near_color(image.get_pixelv(Vector2i(camera.unproject_position(Vector3(-.2,0,-2)))),Color.BLUE,"High-index cutout preserves the geometry behind it")
	near_color(image.get_pixelv(Vector2i(camera.unproject_position(Vector3(.2,0,-2)))),Color.YELLOW,"High-index opaque texel keeps its correct depth")
	foreground.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;renderer.refresh_materials(foreground)
	image=await capture()
	for entry in renderer.entries:
		if entry.node==foreground:check(entry.page_index>31 and (int(entry.texture_page)&32)!=0,"Page address and translucency flag remain independent")
	near_color(image.get_pixelv(Vector2i(camera.unproject_position(Vector3(.2,0,-2)))),Color(.5,.5,.5),"High-index translucent page blends over the ordered background")
	check(originals[0].get_image().get_data()==source_bytes,"Packing never modifies the imported source image")
	observations.stress_pages=renderer.texture_page_count;observations.atlas_size=str(renderer.atlas_texture.get_size())
	viewport.queue_free();await settle()
	# Launch the artist's actual current map through the same F6 session path.
	var map_path := "res://scenes/examples/inventory_demo.tscn";var map_hash := FileAccess.get_sha256(map_path)
	root.get_node("InventoryState").persist_collection=false
	var map: Node3D=load(map_path).instantiate();root.add_child(map);current_scene=map;await settle(20)
	var game := current_scene
	check(game!=map and game.has_method("play_cinematic"),"Actual inventory map starts through LevelRuntime")
	if game!=map:
		check(game.psx_renderer.native_geometry!=null and game.psx_renderer.native_geometry.get_statistics().version>=16 and game.psx_renderer.triangle_count>0,"Actual map launches and renders with the new native page addressing")
		observations.map_pages=game.psx_renderer.texture_page_count
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/texture-pages-map.png")
		game.level_audio.stop_level()
	check(FileAccess.get_sha256(map_path)==map_hash,"F6 validation preserves the artist's map")
	current_scene=null;game.queue_free();await settle(8)
	observations.ok=failures.is_empty();observations.errors=failures
	FileAccess.open("res://docs/texture-pages-validation.json",FileAccess.WRITE).store_string(JSON.stringify(observations,"\t"))
	print("TEXTURE_PAGES_OK " if failures.is_empty() else "TEXTURE_PAGES_FAILED ",JSON.stringify(observations));quit(0 if failures.is_empty() else 1)
