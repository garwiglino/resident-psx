extends SceneTree
var failures: Array[String]=[]
var observations: Dictionary={}
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: failures.append(message); push_error(message)
func settle(count := 8) -> void:
	for frame in count: await process_frame
func run() -> void:
	var path := "res://scenes/maps/modular_example.tscn"
	var before := FileAccess.get_sha256(path)
	var level: Node3D=load(path).instantiate(); root.add_child(level); current_scene=level
	await settle(20)
	var game := current_scene
	check(game!=level and game.has_method("play_cinematic"),"F6 on a bare map starts the shared game session")
	if game==level or not game.has_method("play_cinematic"): quit(1); return
	var renderer: Node=game.psx_renderer
	check(game.level==level and level.get_parent()==game,"Original painted map is used directly")
	check(game.player.enabled and game.player.camera==renderer.camera,"Player and camera initialized")
	check(not game.legacy_couloir_content and game.interactables.is_empty(),"New level contains no old couloir items/objectives")
	check(renderer.native_geometry!=null and renderer.triangle_count>0,"Native PSX rendering runs in the F6 session")
	check(renderer.world_lights.size()==2,"Both artist-placed lights illuminate the level")
	var module: Node=level.get_node("ReglagesNiveau")
	var saved_saturation: float=module.saturation; var saved_tint: Color=module.color_tint
	check(game.level_audio==module and module._running,"One settings module manages the level audio")
	check(module.profile.exploration_music!=null and module._music[0].playing,"Assigned exploration music starts")
	check(module._music[0].stream.is_class("AudioStreamPSX"),"Level music retains the native SPU route")
	check(game.player.global_position.distance_to(level.get_node("Gameplay/PlayerSpawn").global_position)<.35,"Authored spawn is used")
	observations.triangles=renderer.triangle_count; observations.lights=renderer.world_lights.size()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image(); image.save_png("res://docs/level-f6-playable.png")
		var visible := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x,y).get_luminance()>.08: visible+=1
		check(visible>image.get_width()*image.get_height()*.03,"F6 image contains visible lit geometry")
		observations.visible_pixels=visible
	var atlas_before: PackedByteArray=renderer.atlas_texture.get_image().get_data()
	module.color_tint=Color.WHITE; module.saturation=0.0; module.fog_enabled=false
	await settle(6)
	var image: Image=renderer.atlas_texture.get_image(); var grey := true
	for y in range(0,image.get_height(),3):
		for x in range(0,image.get_width(),3):
			var color := image.get_pixel(x,y)
			if not is_equal_approx(color.r,color.g) or not is_equal_approx(color.g,color.b): grey=false
	check(grey and image.get_data()!=atlas_before,"Saturation changes PSX palettes, not a screen overlay")
	module.color_tint=Color(.6,.8,1); module.brightness=1.2; module.fog_enabled=true
	module.fog_start=2; module.fog_end=8; module.fog_color=Color(.1,.3,.4)
	await settle(6)
	check(renderer.color_tint==module.color_tint and renderer.fog_end==8 and renderer.saturation==0,"Live per-level atmosphere reaches the common renderer")
	check(renderer.native_geometry.get_statistics().world_lights==2,"Grading retains native vertex lighting")
	check(FileAccess.get_sha256(path)==before,"Runtime never rewrites the artist's scene")
	game.restart(); await settle(24)
	var restarted := current_scene
	check(restarted.has_method("play_cinematic") and restarted!=game,"Restart launches the same map through the common session")
	check(restarted.level.get_node("ReglagesNiveau").saturation==saved_saturation and restarted.level.get_node("ReglagesNiveau").color_tint==saved_tint,"Reload restores the artist's saved level settings")
	check(restarted.level_audio._music[0].playing,"Level music restarts without duplicate managers")
	check(restarted.level.find_children("ReglagesNiveau","Node",true,false).size()==1,"A single level module survives restart")
	restarted.level_audio.stop_level(); current_scene=null; restarted.queue_free(); await settle(8)
	get_tree_paused_safe()
	var result := {"ok":failures.is_empty(),"errors":failures,"observations":observations}
	var file := FileAccess.open("res://docs/level-runtime-validation.json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	print("LEVEL_RUNTIME_OK " if failures.is_empty() else "LEVEL_RUNTIME_FAILED ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
func get_tree_paused_safe() -> void: paused=false
