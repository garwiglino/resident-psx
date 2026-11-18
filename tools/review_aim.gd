extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view := SubViewport.new()
	view.size=Vector2i(320,240);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game);game.set_process_input(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player
	p.set_process(false);p.set_physics_process(false)
	p.position=Vector3(0,.02,4.5);p.rotation=Vector3.ZERO;p.reset_camera_follow()
	var overview := Camera3D.new()
	game.add_child(overview);overview.fov=45
	overview.global_position=p.position+Vector3(2.7,1.5,3.2)
	overview.look_at(p.position+Vector3.UP*.9)
	var m=p.motion
	for clip in ["idle","walk","strafe_left","backward_right"]:
		m.set_aiming(false,0);m.current="";m.blend_time=0;m.play(clip);m.advance_motion(.7)
		for aiming in [false,true]:
			p.aiming=aiming;m.set_aiming(aiming,.18)
			for frame in 30:m.advance_motion(1.0/60);p._process(1.0/60)
			for camera in [p.camera,overview]:
				game.psx_renderer.camera=camera
				for frame in 3:await process_frame
				RenderingServer.force_draw(false)
				view.get_texture().get_image().save_png("res://docs/aim-%s-%s-%s.png" % [clip,"aim" if aiming else "hip","shoulder" if camera==p.camera else "body"])
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout
	view.queue_free();await process_frame
	print("AIM_REVIEW_OK: normal/aim shoulder framing and full body across four locomotion poses")
	quit()
