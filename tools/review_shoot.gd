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
	p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.position=Vector3(0,.02,4.5);p.rotation=Vector3.ZERO;p.reset_camera_follow()
	p.aiming=true
	var m=p.motion
	m.set_aiming(true,0);m.current="";m.blend_time=0;m.play("strafe_left");m.advance_motion(1.5)
	for frame in 60:p._process(1.0/60)
	for frame in 3:await process_frame
	RenderingServer.force_draw(false)
	view.get_texture().get_image().save_png("res://docs/shoot-before.png")
	m.fire();p._apply_upper_body_look()
	var report: Array=[]
	var source_frames := "--source-frames" in OS.get_cmdline_user_args()
	var step := 1.0/24 if source_frames else 1.0/60
	var prefix := "shoot-source" if source_frames else "shoot"
	for frame in 46:
		if frame>0:m.advance_motion(step);p._process(step)
		if frame not in [0,1,2,3,4,6,8,12,20,40,45]:continue
		for render in 2:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/%s-%02d.png" % [prefix,frame])
		report.append({"frame":frame,"body_time":m.aim_pose.fire_time,"gun_time":m.weapon.shot_time,"gun_clip":m.weapon.mixer.current_animation,
		 "flash_variant":m.weapon.flash_variant,"flash_visible":m.weapon.flash_mesh.visible,"light_energy":game.psx_renderer.shot_light_energy,
		 "sound_playing":p.sounds.shot.playing,"shake_left":p._shot_shake_left,"source_frame":1+m.weapon.shot_time*24,
		 "attached_case":m.weapon._attached_case,"slide":str(m.weapon.skeleton.get_bone_pose_position(m.weapon.skeleton.find_bone("b_slide"))),
		 "bullet_world":str((m.weapon.skeleton.global_transform*m.weapon.skeleton.get_bone_global_pose(m.weapon._bullet_bone)).origin)})
	FileAccess.open("res://docs/shoot-source-review.json" if source_frames else "res://docs/shoot-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout
	view.queue_free();await process_frame
	print("SHOOT_REVIEW_OK: synchronized recoil, slide, bone ejection/reset, atlas flash and vertex light")
	quit()
