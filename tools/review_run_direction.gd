extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var view := SubViewport.new();view.size=Vector2i(320,240);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	view.add_child(game);game.set_process(false);game.set_process_input(false);game.hud.visible=false;game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.position=Vector3(0,.05,6);p.rotation=Vector3.ZERO;p.pitch=.12;p.reset_camera_follow()
	var camera := Camera3D.new();game.add_child(camera);camera.fov=40;game.psx_renderer.camera=camera
	game.psx_renderer.ambient_light_color=Color(.65,.65,.65);game.psx_renderer.fog_enabled=false;game.psx_renderer.target_fps=0;p.flashlight=false
	var m=p.motion
	for heading in [-45,0,45]:
		m.run_heading.advance(deg_to_rad(heading),0,0)
		m.current="";m.blend_time=0;m.play("run",p.run_animation_speed);m.advance_motion(.45/p.run_animation_speed);p._apply_upper_body_look()
		camera.global_position=p.global_position+Vector3(1.8,1.6,3.0);camera.look_at(p.global_position+Vector3.UP*.9)
		game.psx_renderer._process(0)
		for frame in 2:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/run-direction-%d.png" % heading)
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout;view.queue_free();await process_frame;await create_timer(.1).timeout
	print("RUN_DIRECTION_REVIEW_OK");quit()
