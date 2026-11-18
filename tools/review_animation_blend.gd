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
	p.set_process(false);p.set_physics_process(false)
	p.position=Vector3(0,.02,4.5);p.rotation=Vector3.ZERO;p.reset_camera_follow()
	var overview := Camera3D.new()
	game.add_child(overview)
	overview.fov=45
	overview.global_position=p.position+Vector3(2.7,1.5,3.2)
	overview.look_at(p.position+Vector3.UP*.9)
	game.psx_renderer.camera=overview
	var m=p.motion
	var grip := "--grip" in OS.get_cmdline_user_args()
	var original := "--original-grip-reference" in OS.get_cmdline_user_args()
	if original:
		var source=load("res://assets/character/cop_player.glb").instantiate()
		var sk: Skeleton3D=source.get_node("rig/Skeleton3D")
		for bone in sk.get_bone_count():m.body_skeleton.set_bone_rest(bone,sk.get_bone_rest(bone))
		m.mixer.clear_caches()
		source.free()
	var pairs := [["strafe_left","idle"]] if grip else [["idle","walk"],["walk","strafe_left"],["strafe_right","backward_left"]]
	for pair in pairs:
		m.current="";m.blend_time=0;m.play(pair[0]);m.advance_motion(0);m.advance_motion(2.0 if grip else .7)
		if grip:
			var centre: Vector3=m.body_skeleton.global_transform*m.body_skeleton.get_bone_global_pose(m.body_skeleton.find_bone("DEF-hand.R")).origin
			overview.global_position=centre+Vector3(.9,.35,-1.3)
			overview.fov=35
			overview.look_at(centre)
		m.blend_time=.5;m.play(pair[1]);m.advance_motion(0)
		for frame in 31:
			if frame>0:m.advance_motion(1.0/60)
			if frame not in [0,6,15,30]:continue
			for render in 2:await process_frame
			RenderingServer.force_draw(false)
			var prefix := "grip-before" if original else "grip-after"
			var path := "res://docs/%s-%02d.png" % [prefix,frame] if grip else "res://docs/blend-%s-%s-%02d.png" % [pair[0],pair[1],frame]
			view.get_texture().get_image().save_png(path)
			if grip:
				game.psx_renderer.camera=p.camera
				for render in 2:await process_frame
				RenderingServer.force_draw(false)
				view.get_texture().get_image().save_png("res://docs/%s-shoulder-%02d.png" % [prefix,frame])
				game.psx_renderer.camera=overview
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout
	view.queue_free();await process_frame
	print("ANIMATION_BLEND_REVIEW_OK: 0, 0.1, 0.25 and 0.5 seconds of moving pose crossfades")
	quit()
