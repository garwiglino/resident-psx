extends SceneTree
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game: Node3D=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p: Node3D=game.player;p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false);p.camera_collision_enabled=false
	p.free_orbit_enabled=false
	p.camera_translation_lag=.2;p.camera_rotation_lag=.2;p.camera_max_translation_lag=.22;p.camera_teleport_snap_distance=3;p.body_turn_response=.3;p.body_turn_speed_degrees=30
	for action in ["sprint","forward","back","left","right","aim"]:Input.action_release(action)
	p.reset_camera_follow();Input.action_press("forward");Input.action_press("sprint")
	for angle in [60.0,-80.0,179.0,-179.0,20.0]:
		p.look_yaw=deg_to_rad(angle);p.pitch=.2;p._physics_process(1.0/60);p.update_camera_follow(1.0/60)
		check(absf(wrapf(p.global_rotation.y-p.look_yaw,-PI,PI))<.00001,"Running body follows mouse yaw immediately: "+str(angle))
		check(p.camera_pivot.global_position.distance_to(p.global_position+Vector3.UP*p._current_camera_offset().y)<.00001,"Running camera has no positional trail")
		check(p._camera_follow_rotation.angle_to(p._camera_target_rotation())<.00001,"Running camera has no yaw or pitch trail")
		check(not p.motion.turn_in_place.active and is_zero_approx(p.motion.turn_in_place.rotation_delta),"Running never waits on an idle turn")
	var animation_time: float=p.motion.mixer.current_animation_position
	p._apply_mouse_motion(Vector2(40,12));p.update_camera_follow(1.0/120)
	check(absf(wrapf(p.global_rotation.y-p.look_yaw,-PI,PI))<.00001,"Mouse motion between physics ticks also turns the running actor immediately")
	check(is_equal_approx(animation_time,p.motion.mixer.current_animation_position),"Render facing never advances or restarts root-motion animation")
	Input.action_press("left");p._physics_process(1.0/60);p.update_camera_follow(1.0/60)
	check(p.motion.run_heading.yaw>0 and p.motion.run_heading.yaw<deg_to_rad(45),"Diagonal pelvis steering keeps its separate smooth transition")
	Input.action_release("sprint");Input.action_release("left");p.look_yaw+=.8;p._physics_process(1.0/60);p.global_position.x+=.1;p.update_camera_follow(1.0/60)
	check(absf(wrapf(p.global_rotation.y-p.look_yaw,-PI,PI))>.1,"Walking retains its progressive body orientation")
	check(p._camera_follow_rotation.angle_to(p._camera_target_rotation())>.01,"Walking retains the configured camera rotation lag")
	check(p.camera_pivot.global_position.distance_to(p.global_position+Vector3.UP*p._current_camera_offset().y)>.01,"Walking retains the configured camera translation lag")
	for action in ["sprint","forward","back","left","right","aim"]:Input.action_release(action)
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/run-camera-follow-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("RUN_CAMERA_FOLLOW_OK " if failures.is_empty() else "RUN_CAMERA_FOLLOW_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
