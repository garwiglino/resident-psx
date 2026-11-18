extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view := SubViewport.new()
	view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.set_process_input(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player
	p.set_physics_process(false)
	p.set_process(false)
	p.position=Vector3(0,.02,4.5)
	p.rotation=Vector3.ZERO
	p.pitch=0
	p.reset_camera_follow()
	var overview := Camera3D.new()
	game.add_child(overview)
	overview.fov=45
	overview.current=true
	var pelvis := "--pelvis" in OS.get_cmdline_user_args()
	var locomotion := pelvis or "--locomotion" in OS.get_cmdline_user_args()
	var settings := [["run",0.0,0.0],["aim",0.0,0.0],["strafe_right",0.0,0.0],["forward_right",0.0,0.0]] if locomotion else [["twist",40.0,20.0],["follow",80.0,0.0],["down",20.0,-35.0]]
	if pelvis:settings=[["idle",0.0,0.0],["walk",0.0,0.0],["strafe_left",0.0,0.0],["strafe_right",0.0,0.0],["forward_left",0.0,0.0],["backward_right",0.0,0.0]]
	for setting in settings:
		if locomotion:
			p.motion.current=""
			p.motion.blend_time=0.0
			p.motion.play(setting[0])
			p.motion.advance_motion(0)
			p.motion.advance_motion(.5)
		if setting[0]=="down":
			p.rotation=Vector3.ZERO
			p.pitch=0
			p.reset_camera_follow()
		p.look_yaw=deg_to_rad(setting[1])
		p.pitch=deg_to_rad(setting[2])
		for frame in 35:
			await physics_frame
			if not locomotion:p._physics_process(1.0/60)
			p._process(1.0/60)
		game.psx_renderer.camera=overview
		overview.global_position=p.global_position+Vector3(2.7,1.5,3.2)
		overview.look_at(p.global_position+Vector3.UP*.9)
		for frame in 2:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/body-look-%s.png" % setting[0])
		game.psx_renderer.camera=p.camera
		for frame in 2:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/body-look-camera-%s.png" % setting[0])
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.08).timeout
	view.queue_free()
	await process_frame
	print("BODY_LOOK_REVIEW_OK")
	quit()
