extends SceneTree
var game: Node3D
var failures: Array[String]=[]
var results: Array[Dictionary]=[]
var sheet: Image
var captured := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func summary(samples: Array[float]) -> Dictionary:
	samples.sort();var sum := 0.0
	for value in samples:sum+=value
	return {"mean_ms":sum/samples.size(),"p95_ms":samples[mini(floori(samples.size()*.95),samples.size()-1)],"max_ms":samples[-1]}
func sample(label: String,correct: bool) -> void:
	var raster=game.psx_renderer
	var input: Array[Dictionary]=[]
	for entry in raster.entries:
		var copy: Dictionary=entry.duplicate();copy.depth_correct=entry.depth_correct and correct;input.append(copy)
	raster.native_geometry.configure(input)
	raster.general_depth_correction=correct; raster.apply_render_settings()
	for frame in 10:await process_frame
	var cpu: Array[float]=[];var total: Array[float]=[];var previous := Time.get_ticks_usec()
	for frame in 90:
		await process_frame
		var at := Time.get_ticks_usec();total.append((at-previous)/1000.0);previous=at
		cpu.append(raster.last_process_us/1000.0)
	var stats: Dictionary=raster.native_geometry.get_statistics()
	check(stats.batches==1,label+": one native batch")
	check(stats.general_depth==correct and (stats.player_depth_pixels>0)==correct,label+": global correction follows the requested mode")
	results.append({"view":label,"correction":correct,"geometry":summary(cpu),"frame":summary(total),"stats":stats})
	if correct:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image();sheet.blit_rect(image,Rect2i(0,0,320,240),Vector2i(captured*320,0));captured+=1
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);root.size=Vector2i(320,240)
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.start_game();game.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;var r=game.psx_renderer
	r.target_fps=0
	p.set_process_unhandled_input(false);p.set_process(false);p.set_physics_process(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;Engine.max_fps=0
	p.position=Vector3(0,.05,6.2);p.velocity=Vector3.ZERO;p.rotation=Vector3.ZERO;p.look_yaw=0;p.pitch=0
	p.reset_camera_follow();p.update_camera_follow(1)
	var player_surfaces := 0;var weapon_surfaces := 0
	for entry in r.entries:
		if p.is_ancestor_of(entry.node):
			check(entry.depth_correct,"All player descendants, including modular garments and the pistol, use corrected visibility")
			player_surfaces+=1
			if p.motion.weapon.is_ancestor_of(entry.node):weapon_surfaces+=1
	check(player_surfaces>5 and weapon_surfaces>0,"Player body and held gun are both registered")
	r.ambient_light_color=Color(.35,.35,.35);r.set_active_camera(p.camera)
	sheet=Image.create(960,240,false,Image.FORMAT_RGBA8)
	await sample("shoulder",false);await sample("shoulder",true)
	Input.action_press("aim")
	for frame in 20:await physics_frame;p._physics_process(1.0/60)
	Input.action_release("aim")
	await sample("aim",false);await sample("aim",true)
	var close := Camera3D.new();game.add_child(close);close.global_position=p.global_position+Vector3(-.65,1.45,-.8);close.look_at(p.global_position+Vector3(0,1.25,0));close.fov=55
	r.set_active_camera(close)
	await sample("close_body_weapon",false);await sample("close_body_weapon",true)
	sheet.save_png("res://docs/player-depth-map.png")
	FileAccess.open("res://docs/player-depth-map-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"player_surfaces":player_surfaces,"weapon_surfaces":weapon_surfaces,"results":results},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free();await process_frame
	print("PLAYER_DEPTH_MAP_OK: player, modular clothing and held gun, shoulder/aim/close views, local performance comparison and one native batch" if failures.is_empty() else "PLAYER_DEPTH_MAP_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
