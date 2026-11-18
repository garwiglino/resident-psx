extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func stats(values: Array[float]) -> Dictionary:
	values.sort()
	var total := 0.0
	for v in values:
		total+=v
	return {"mean":total/values.size(),"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"max":values[-1]}
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process_input(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.psx_renderer.target_fps=60
	if "--perspective" in OS.get_cmdline_user_args():game.psx_renderer.affine_texture_strength=0.0
	game.psx_renderer.apply_render_settings()
	game.player.health=100000
	var manual_lights := "--manual-lights" in OS.get_cmdline_user_args()
	if manual_lights:
		for position in [Vector3(0,2.4,5),Vector3(-6,2.4,-5),Vector3(6,2.4,-14),Vector3(0,2.4,-13),Vector3(0,2.4,-24),Vector3(0,2.4,-28)]:
			var lamp=load("res://scripts/psx_light_3d.gd").new()
			game.level.get_node("Lumieres").add_child(lamp);lamp.global_position=position
			lamp.light_energy=2;lamp.light_range=7
	var aimed := "--aim" in OS.get_cmdline_user_args()
	var reloading := "--reload" in OS.get_cmdline_user_args()
	var shooting := "--shoot" in OS.get_cmdline_user_args() or reloading
	if aimed or shooting:Input.action_press("aim")
	if shooting:
		# Only the benchmark copy fires continuously; the authored gun stays semi-auto.
		game.player.weapon_definition().automatic=true
		game.player.magazine_capacity=2 if reloading else 10000
		game.player.ammo=game.player.magazine_capacity;game.player.reserve=10000
		Input.action_press("fire")
	var warmup := 3.0 if reloading else 1.0
	await create_timer(warmup).timeout
	var intervals: Array[float]=[]
	var hitches: Array=[]
	var work: Array[float]=[]
	var geometry: Array[float]=[]
	var previous := Time.get_ticks_usec()
	var started := previous
	var starting_shots: int=game.player.motion.weapon.shot_serial
	var starting_drops: int=game.player.motion.weapon.magazines.drop_count
	var starting_insertions: int=game.player.motion.weapon.magazines.insert_count
	var positions := [Vector3(0,.05,6.2),Vector3(-5,.05,-5),Vector3(5,.05,-13),Vector3(0,.05,-25),Vector3(0,.05,-13)]
	var directions := [["forward"],["forward","right"],["right"],["back","right"],["back"],
		["back","left"],["left"],["forward","left"],["forward","sprint"],["forward","right"]]
	var played: Array[String]=[]
	var change_interval := 6 if "--rapid-directions" in OS.get_cmdline_user_args() else 60
	for i in 600:
		# Exercise accepted shots independently of focus-related mouse events.
		if shooting:game.player.shoot()
		# Le banc simule la commande R ; le jeu ne recharge jamais automatiquement.
		if reloading and game.player.ammo==0 and game.player.weapon_inventory.action==game.player.WeaponInventory.Action.READY:
			game.player.reload_weapon()
		if i%change_interval==0:
			for action in ["forward","back","left","right","sprint"]:Input.action_release(action)
			for action in directions[(i/change_interval)%directions.size()]:Input.action_press(action)
		if i%60==0:
			game.player.position=positions[(i/60)%positions.size()]
			game.player.velocity=Vector3.ZERO
		game.player.look_yaw=wrapf(TAU*i/180.0,-PI,PI)
		await process_frame
		var now := Time.get_ticks_usec()
		var interval := (now-previous)/1000.0
		intervals.append(interval)
		if interval>25:hitches.append({"frame":i,"ms":interval,"reload_time":game.player.motion.weapon.reload_time,
		 "shot_time":game.player.motion.weapon.shot_time,"geometry_ms":game.psx_renderer.last_process_us/1000.0})
		previous=now
		if not game.player.motion.current in played:played.append(game.player.motion.current)
		work.append((game.psx_renderer.last_process_us+game.psx_renderer.last_draw_us)/1000.0)
		geometry.append(game.psx_renderer.last_process_us/1000.0)
	for action in ["forward","back","left","right"]:Input.action_release(action)
	Input.action_release("sprint")
	Input.action_release("aim")
	Input.action_release("fire")
	var elapsed := (Time.get_ticks_usec()-started)/1000000.0
	var report := {"frames":600,"elapsed_seconds":elapsed,"warmup_seconds":warmup,"average_fps":600/elapsed,"frame_ms":stats(intervals),"frames_over_25ms":hitches,
		"manual_world_lights":game.psx_renderer.world_lights.size(),
		"affine_texture_strength":game.psx_renderer.affine_texture_strength,
		"locomotion_clips":played,"texture_pages":game.psx_renderer.texture_page_count,"direction_change_interval_frames":change_interval,
		"cpu_geometry_and_submission_ms":stats(work),"native_geometry_ms":stats(geometry),
		"monitor_hz":DisplayServer.screen_get_refresh_rate(),"vsync":DisplayServer.window_get_vsync_mode(),
		"camera_fov":game.player.camera_fov,"camera_offset":str(game.player.camera_offset),"aiming":game.player.aiming,
		"actual_camera_fov":game.player.camera.fov,"actual_camera_distance":game.player.arm.spring_length,"viewport_size":str(root.get_visible_rect().size),
		"shots":game.player.motion.weapon.shot_serial-starting_shots,"casing_pool":game.player.motion.weapon.casings.size(),
		"magazine_drops":game.player.motion.weapon.magazines.drop_count-starting_drops,"magazine_insertions":game.player.motion.weapon.magazines.insert_count-starting_insertions,
		"magazine_pool":game.player.motion.weapon.magazines.drops.size(),"native_version":game.psx_renderer.native_geometry.get_statistics().version,"batches":game.psx_renderer.batch_count}
	var report_path := "res://docs/verified-60fps-reload.json" if reloading else ("res://docs/verified-60fps-shoot.json" if shooting else ("res://docs/verified-60fps-aim.json" if aimed else "res://docs/verified-60fps.json"))
	if manual_lights:report_path="res://docs/verified-60fps-manual-lights.json"
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FRAME_PACING ",JSON.stringify(report))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):
		audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	quit()
