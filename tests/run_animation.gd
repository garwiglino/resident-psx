extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func horizontal(vector: Vector3) -> Vector3:return Vector3(vector.x,0,vector.z)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.free_orbit_enabled=false
	await create_timer(.1).timeout
	var m=p.motion
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/animations/player_run_pistol.json"))
	check(metadata.source=="C:\\Users\\sheensaw\\Downloads\\cop_anims_walk.blend","Run uses the requested Blender source")
	check(metadata.start_frame==1 and metadata.end_frame==121 and metadata.fps==30,"Run preserves its source frame range and 30 fps timing")
	check(m.mixer.has_animation("player_run_pistol") and m.clip_metadata.run.clip=="player_run_pistol","Shift's run alias loads the new source clip")
	check(m.current_clip_has_root_motion()==false,"Idle remains stationary before running")
	check(m.mixer.get_animation("run").loop_mode==Animation.LOOP_LINEAR,"Run loops continuously")
	var binding := false
	for event in InputMap.action_get_events("sprint"):
		if event is InputEventKey and event.keycode==KEY_SHIFT:binding=true
	check(binding,"Sprint is bound to Shift")
	m.current="";m.blend_time=0;m.set_aiming(false,0);m.play("run");m.advance_motion(0)
	var total := Vector3.ZERO;var largest := 0.0
	for tick in 480:
		var delta: Vector3=m.advance_motion(1.0/60)
		total+=delta;largest=maxf(largest,delta.length())
	var expected := Vector3(float(metadata.root_motion_vector[0]),0,float(metadata.root_motion_vector[2]))*2
	check(horizontal(total).distance_to(expected)<.005,"Two running loops retain the exact authored root displacement")
	check(largest<metadata.average_speed/60*2,"Run loop boundaries never teleport the player")
	var root_bone: int=m.body_skeleton.find_bone("RootMotion")
	check(m.body_skeleton.get_bone_pose_position(root_bone).length()<.0001,"Root travel is extracted from the visible skeleton")
	report.two_loop_distance_m=horizontal(total).length();report.largest_step_m=largest
	# Drive the same controller path as the real input, in a clear corridor.
	p.position=Vector3(0,.05,6.2);p.velocity=Vector3.ZERO;p.rotation=Vector3.ZERO;p.reset_camera_follow()
	m.current="";m.blend_time=0;m.play("idle");m.advance_motion(0)
	Input.action_press("forward");Input.action_press("sprint")
	var before: Vector3=p.position
	for tick in 60:
		await physics_frame;p._physics_process(1.0/60)
		check(m.current=="run" and m.current_clip_has_root_motion(),"Shift + forward selects the exported root-motion run")
	var travel := horizontal(p.position-before)
	var source_time: float=p.run_animation_speed*p.root_motion_playback_speed
	var run_clip: Animation=m.mixer.get_animation("run")
	var root_track := run_clip.find_track(m.mixer.root_motion_track,Animation.TYPE_POSITION_3D)
	var authored_travel: Vector3=horizontal(run_clip.position_track_interpolate(root_track,source_time)-run_clip.position_track_interpolate(root_track,0))*p.root_motion_scale
	check(absf(travel.length()-authored_travel.length())<.015,"Accelerated jog moves the capsule by the matching authored root displacement")
	check(absf(m.mixer.current_animation_position-source_time)<.0001 and absf(m.root_sampler.current_animation_position-source_time)<.0001,"Pose and extracted root motion advance at the same jog cadence")
	check(travel.normalized().dot(Vector3.FORWARD)>.999,"Run follows the forward camera direction")
	report.controller_one_second_distance_m=travel.length()
	report.run_animation_speed=p.run_animation_speed;report.expected_source_time=source_time
	Input.action_release("sprint")
	await physics_frame;p._physics_process(1.0/60)
	check(m.current=="walk","Releasing Shift returns to the authored forward walk")
	check(is_equal_approx(m.mixer.speed_scale,p.root_motion_playback_speed),"The jog speed multiplier does not accelerate walking")
	check(is_equal_approx(m.blend_time,p.animation_blend_time),"Walk/run uses the existing transition duration")
	Input.action_press("sprint");Input.action_press("aim")
	await physics_frame;p._physics_process(1.0/60)
	check(p.aiming and m.current=="walk","Aiming keeps the directional walk even while Shift is held")
	Input.action_release("forward");Input.action_release("aim")
	await physics_frame;p._physics_process(1.0/60)
	check(m.current=="idle","Shift alone does not start the run")
	Input.action_press("left")
	await physics_frame;p._physics_process(1.0/60)
	check(m.current=="strafe_left","Shift does not replace a sideways-only strafe with a forward run")
	Input.action_release("left");Input.action_press("back")
	await physics_frame;p._physics_process(1.0/60)
	check(m.current=="backward","Shift does not run backward with a forward-only clip")
	Input.action_release("back");Input.action_release("sprint")
	report.failures=failures;report.source_sha256=metadata.source_sha256
	FileAccess.open("res://docs/run-animation-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.08).timeout
	print("RUN_ANIMATION_OK: source timing, two root-motion loops, real Shift controller, authored speed, walk return, aim and directional guards" if failures.is_empty() else "RUN_ANIMATION_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
