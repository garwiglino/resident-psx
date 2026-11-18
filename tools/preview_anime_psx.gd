extends SceneTree
## Review-only experiment. Nothing here is loaded by the game or its editor plugins.
const Grade=preload("res://scripts/levels/palette_grade.gd")
var game: Node3D
var viewport: SubViewport
var report: Dictionary={}
var output_prefix := "anime-preview"
var method_description := "three-tone vertex-light palette, cool shadows/warm lights, existing native raster path"
var use_production_anime := false
var protected := ["res://scenes/level_1.tscn","res://scenes/player.tscn","res://scripts/psx_renderer.gd","res://shaders/psx_raster_common.gdshaderinc"]
func _initialize() -> void:call_deferred("run")
func fingerprint() -> Dictionary:
	var result := {}
	for path in protected:result[path]=FileAccess.get_sha256(path)
	return result
func stylize_packets(renderer: Node,amount: float) -> void:
	# Alter only the vertex-light colours. Keep native geometry, UVs, depth,
	# texture pages, RGB555/dithering and fog; no screen-space colour filter.
	var fog: Color=Grade.color(renderer.fog_color,renderer.saturation)
	var fog_rgb := Vector3(fog.r,fog.g,fog.b)
	var changed := 0
	for packet: Dictionary in renderer.primitives:
		if int(packet.get("blend_mode",0))!=0:continue
		var colors: PackedColorArray=packet.colors
		var inverse: PackedFloat32Array=packet.inverse_depths
		var extended: bool=packet.get("extended_pages",false)
		for index in colors.size():
			var original := colors[index];var flags := roundi(original.a*255)
			if flags&32:continue
			var page: int=roundi(packet.depth_channels[index*4+2]) if extended else flags&31
			var scale := 128.0 if page else 255.0
			var depth := 1.0/maxf(inverse[index],.00000001)
			var fog_weight := clampf((depth-renderer.fog_start)/maxf(renderer.fog_end-renderer.fog_start,.001),0,.88) if renderer.fog_enabled else 0.0
			var light := (Vector3(original.r,original.g,original.b)*255.0/scale-fog_rgb*fog_weight)/(1-fog_weight)
			var luma := light.dot(Vector3(.299,.587,.114))
			if luma<=.012:continue
			var strength := amount if flags&64 else amount*.45
			var stepped := .23 if luma<.38 else (.63 if luma<.78 else 1.12)
			var shaded := light*lerpf(1.0,stepped/luma,strength)
			var warm := smoothstep(.25,1.0,luma)
			var tint := Vector3(.90,.94,1.08).lerp(Vector3(1.04,1.01,.95),warm)
			shaded*=Vector3.ONE.lerp(tint,strength)
			var encoded := (shaded*(1-fog_weight)+fog_rgb*fog_weight)*scale
			var next := Color(clampf(floorf(encoded.x),0,255)/255.0,clampf(floorf(encoded.y),0,255)/255.0,clampf(floorf(encoded.z),0,255)/255.0,original.a)
			if next!=original:changed+=1
			colors[index]=next
		packet.colors=colors
	renderer._prepare_perspective_meshes();renderer.queue_redraw();report["modified_vertices"]=changed
func capture(name: String,amount: float) -> Image:
	var renderer: Node=game.psx_renderer
	if not use_production_anime:renderer.anime_style=null
	renderer._process(0)
	if not use_production_anime:
		for packet: Dictionary in renderer.primitives:packet.erase("perspective_uvs")
	if amount>0:stylize_packets(renderer,amount)
	for frame in 4:await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image();picture.save_png("res://docs/"+output_prefix+"-"+name+".png");return picture
func pair(name: String,before: Image,after: Image) -> void:
	var joined := Image.create(640,240,false,Image.FORMAT_RGBA8);joined.blit_rect(before,Rect2i(0,0,320,240),Vector2i.ZERO);joined.blit_rect(after,Rect2i(0,0,320,240),Vector2i(320,0));joined.resize(1280,480,Image.INTERPOLATE_NEAREST);joined.save_png("res://docs/"+output_prefix+"-"+name+"-comparison.png")
	var changed := 0
	for y in 240:
		for x in 320:
			if before.get_pixel(x,y)!=after.get_pixel(x,y):changed+=1
	report[name+"_changed_pixels"]=changed
func run() -> void:
	create_timer(70).timeout.connect(func():push_error("Anime preview timeout");quit(2));var source_hashes := fingerprint()
	root.get_node("InventoryState").persist_collection=false;root.get_node("WorldEvents").reset_run()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	viewport=SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	game=load("res://scenes/systemes_jeu.tscn").instantiate()
	var map: Node3D=load("res://scenes/level_1.tscn").instantiate();map.name="Map";game.add_child(map)
	for area in map.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	viewport.add_child(game);game.set_process(false);game.set_process_input(false);game.hud.hide();game.pickup_feedback.enabled=false;game.psx_renderer.set_process(false)
	var p: Node3D=game.player;p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false);p.motion.set_process(false);p.camera_collision_enabled=false
	for enemy in game.enemies:enemy.set_physics_process(false)
	for frame in 12:await process_frame
	for light in get_nodes_in_group("psx_world_lights"):
		var energy: float=light.get_render_energy();light.flicker=false;light.light_energy=energy
	map.process_mode=Node.PROCESS_MODE_DISABLED
	p.aiming=false;p.pitch=0;p.look_yaw=0;p.reset_camera_follow();p.motion.blend_time=0;p.motion.play("idle");p.motion.advance_motion(.5);p._apply_upper_body_look()
	game.psx_renderer.set_active_camera(p.camera)
	var gameplay_before := await capture("gameplay-before",0)
	var gameplay_after := await capture("gameplay-after",.55);pair("gameplay",gameplay_before,gameplay_after)
	var stronger := await capture("gameplay-stronger",.85);pair("stronger",gameplay_before,stronger)
	var camera := Camera3D.new();game.add_child(camera);camera.fov=38;camera.near=.05;camera.global_position=p.global_position+Vector3(.5,1.55,-1.5);camera.look_at(p.global_position+Vector3.UP*1.4)
	game.psx_renderer.set_active_camera(camera)
	var face_before := await capture("portrait-before",0)
	var face_after := await capture("portrait-after",.55);pair("portrait",face_before,face_after)
	var face_stronger := await capture("portrait-stronger",.85);pair("portrait-stronger",face_before,face_stronger)
	# A second, clearly labelled lighting test makes the face and shadow palette
	# readable. The two sides use exactly the same neutral PSX vertex lights.
	for light in get_nodes_in_group("psx_world_lights"):light.enabled=false
	game.psx_renderer.ambient_light_color=Color(.18,.19,.24)
	var key := PSXLight3D.new();key.name="ReviewOnlyKey";key.light_color=Color(1,.94,.84);key.light_energy=1.65;key.light_range=6;game.add_child(key);key.global_position=p.global_position+Vector3(-.8,2.2,-.9)
	var fill := PSXLight3D.new();fill.name="ReviewOnlyFill";fill.light_color=Color(.74,.82,1);fill.light_energy=.4;fill.light_range=5;game.add_child(fill);fill.global_position=p.global_position+Vector3(.8,1.8,-.5)
	camera.fov=32;camera.global_position=p.global_position+Vector3(.5,1.5,-1.1);camera.look_at(p.global_position+Vector3.UP*1.4)
	var lit_before := await capture("lit-before",0)
	var lit_after := await capture("lit-after",.55);pair("lit",lit_before,lit_after)
	var lit_stronger := await capture("lit-stronger",.85);pair("lit-stronger",lit_before,lit_stronger)
	report.merge({"production_unchanged":source_hashes==fingerprint(),"source_hashes":source_hashes,"scene":"res://scenes/level_1.tscn","native_version":game.psx_renderer.native_geometry.get_statistics().version,"resolution":[320,240],"method":method_description,"amount":.55,"same_camera_pose_lights":true,"lit_comparison":"separate neutral lighting test, identical before and after","enabled_in_game":false})
	FileAccess.open("res://docs/"+output_prefix+"-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;viewport.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	print("ANIME_PREVIEW_OK ",JSON.stringify(report));quit(0 if report.production_unchanged else 1)
