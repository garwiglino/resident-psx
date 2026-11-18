extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var view := SubViewport.new();view.size=Vector2i(320,240);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	view.add_child(game);game.set_process(false);game.psx_renderer.set_process(false);game.set_process_input(false);game.hud.visible=false
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.position=Vector3(0,.05,6);p.rotation=Vector3.ZERO
	var m=p.motion;var sk: Skeleton3D=m.body_skeleton
	var source=load("res://assets/character/cop_player.glb").instantiate();var original: Skeleton3D=source.get_node("rig/Skeleton3D")
	var bone := sk.find_bone("DEF-forearm.R.001");var corrected := sk.get_bone_rest(bone)
	var overview := Camera3D.new();game.add_child(overview);overview.fov=35;game.psx_renderer.camera=overview
	game.psx_renderer.ambient_light_color=Color(.8,.8,.8);game.psx_renderer.fog_enabled=false;game.psx_renderer.target_fps=0;p.flashlight=false
	for mode in ["before","after"]:
		sk.set_bone_rest(bone,original.get_bone_rest(bone) if mode=="before" else corrected);m.mixer.clear_caches()
		m.current="";m.blend_time=0;m.play("run",p.run_animation_speed);m.advance_motion(.333333/p.run_animation_speed)
		m.blend_time=p.animation_blend_time;m.play("walk");m.advance_motion(p.animation_blend_time*.5)
		var centre: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("DEF-forearm.R.001")).origin
		overview.global_position=centre+Vector3(.8,.35,-1.15);overview.look_at(centre+Vector3(0,-.05,0))
		game.psx_renderer._process(0)
		for frame in 2:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/forearm-transition-%s.png" % mode)
	source.free()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	view.queue_free();await process_frame;await create_timer(.1).timeout
	print("FOREARM_TRANSITION_REVIEW_OK");quit()
