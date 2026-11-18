extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view := SubViewport.new()
	view.size=Vector2i(320,240);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate();view.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	game.hud.visible=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.position=Vector3(0,.02,4.5);p.rotation=Vector3.ZERO;p.reset_camera_follow()
	p.aiming=true;p.motion.set_aiming(true,0);p.motion.advance_motion(0)
	for tick in 60:p._process(1.0/60)
	p.ammo=2;p.reserve=20;p.reload_weapon()
	var report: Array=[]
	for tick in 92:
		if tick>0:
			await physics_frame
			p.weapon_inventory.advance(1.0/60);p.motion.advance_motion(1.0/60);p._process(1.0/60)
		if tick not in [0,10,13,23,39,40,59,85,91]:continue
		var shoulder: Transform3D=p.camera.global_transform
		var fov: float=p.camera.fov
		for angle in ["shoulder","side","grip"]:
			if angle=="grip":
				p.camera.global_position=p.position+Vector3(.85,1.45,-1.0)
				p.camera.look_at(p.position+Vector3(0,1.35,-.2));p.camera.fov=30
			elif angle=="side":
				p.camera.global_position=p.position+Vector3(1.65,1.45,-2.0)
				p.camera.look_at(p.position+Vector3(0,1.1,-.2));p.camera.fov=42
			else:p.camera.global_transform=shoulder;p.camera.fov=fov
			game.psx_renderer._process(0)
			for render in 2:await process_frame
			RenderingServer.force_draw(false)
			view.get_texture().get_image().save_png("res://docs/reload-%s-%02d.png" % [angle,tick])
		p.camera.global_transform=shoulder;p.camera.fov=fov
		report.append({"tick_60hz":tick,"player_source_frame":1+tick*.4,"body_time":p.motion.aim_pose.reload_time,
		 "gun_time":p.motion.weapon.reload_time,"phase":p.motion.weapon.magazines.phase,"ammo":p.ammo})
	# Keep the flash clock frozen while moving the player to show world detachment.
	p.motion.weapon.deactivate();p.weapon_inventory.advance(1);p.ammo=2;p.shoot()
	p.motion.advance_motion(0,1.0/24);p._process(0)
	var origin: Vector3=p.motion.weapon.flash_position
	for moved in [false,true]:
		if moved:p.position.x+=.2;p._process(0)
		game.psx_renderer._process(0)
		for render in 2:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/flash-detached-%s.png" % str(moved))
		assert(p.motion.weapon.flash_mesh.global_position.is_equal_approx(origin))
	FileAccess.open("res://docs/reload-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;view.queue_free();await process_frame
	print("RELOAD_REVIEW_OK: shoulder/side frames, real magazine physics and detached half-opacity flash")
	quit()
