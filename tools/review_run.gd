extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view := SubViewport.new();view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate();view.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	game.hud.visible=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.position=Vector3(0,.05,6.2);p.rotation=Vector3.ZERO;p.velocity=Vector3.ZERO;p.reset_camera_follow()
	Input.action_press("forward")
	for tick in 121:
		if tick==30:Input.action_press("sprint")
		if tick==90:Input.action_release("sprint")
		await physics_frame;p._physics_process(1.0/60);p._process(1.0/60)
		if tick not in [29,30,36,60,84,90,120]:continue
		var shoulder: Transform3D=p.camera.global_transform
		var fov: float=p.camera.fov
		for angle in ["shoulder","body"]:
			if angle=="body":
				p.camera.global_position=p.position+Vector3(2.5,1.3,-2.6)
				p.camera.look_at(p.position+Vector3.UP*.95);p.camera.fov=42
			else:p.camera.global_transform=shoulder;p.camera.fov=fov
			game.psx_renderer._process(0)
			for render in 2:await process_frame
			RenderingServer.force_draw(false)
			view.get_texture().get_image().save_png("res://docs/run-%s-%03d.png" % [angle,tick])
		p.camera.global_transform=shoulder;p.camera.fov=fov
	Input.action_release("forward");Input.action_release("sprint")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;view.queue_free();await process_frame;await create_timer(.08).timeout
	print("RUN_REVIEW_OK: real Shift walk/run/walk, shoulder framing and source running poses")
	quit()
