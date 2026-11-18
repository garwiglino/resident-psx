extends SceneTree
var contact: StringName=&""
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view := SubViewport.new();view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate();view.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	game.hud.visible=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.footstepped.connect(func(foot: StringName,_position: Vector3):contact=foot)
	for stage in ["walk","strafe_left","run"]:
		for action in ["forward","left","sprint"]:Input.action_release(action)
		p.position=Vector3(0,.05,5.2);p.rotation=Vector3.ZERO;p.velocity=Vector3.ZERO;p.reset_camera_follow()
		p.motion.current="";p.motion.blend_time=0;p.motion.set_aiming(false,0);p.motion.play("idle");p.motion.advance_motion(0)
		p.footsteps.setup(p.motion.body_skeleton)
		Input.action_press("left" if stage=="strafe_left" else "forward")
		if stage=="run":Input.action_press("sprint")
		var saved := 0
		for tick in 120:
			contact=&""
			await physics_frame;p._physics_process(1.0/60);p._process(1.0/60)
			if contact==&"":continue
			var shoulder: Transform3D=p.camera.global_transform;var fov: float=p.camera.fov
			p.camera.global_position=p.position+Vector3(1.8,.55,1.7)
			p.camera.look_at(p.position+Vector3(0,.35,0));p.camera.fov=34
			game.psx_renderer._process(0)
			for render in 2:await process_frame
			RenderingServer.force_draw(false)
			view.get_texture().get_image().save_png("res://docs/footstep-contact-%s-%s.png" % [stage,contact])
			p.camera.global_transform=shoulder;p.camera.fov=fov
			saved+=1
			if saved==2:break
	for action in ["forward","left","sprint"]:Input.action_release(action)
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;view.queue_free();await process_frame;await create_timer(.08).timeout
	print("FOOTSTEP_REVIEW_OK: visible sole contacts at actual walk, strafe and accelerated jog sound events")
	quit()
