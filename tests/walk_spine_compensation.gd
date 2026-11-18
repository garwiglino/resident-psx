extends SceneTree
var failures: Array[String]=[]
var checks := 0
var players: Array[Node3D]=[]
var max_root_error := 0.0
var max_leg_error := 0.0
var greatest_before := 0.0
var greatest_after := 0.0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func compare(delta: float) -> void:
	var root_steps: Array[Vector3]=[]
	for p in players:root_steps.append(p.motion.advance_motion(delta));p._apply_upper_body_look()
	var a: Skeleton3D=players[0].motion.body_skeleton;var b: Skeleton3D=players[1].motion.body_skeleton
	max_root_error=maxf(max_root_error,root_steps[0].distance_to(root_steps[1]));check(root_steps[0].is_equal_approx(root_steps[1]),"Compensation preserves extracted root displacement")
	check(players[0].motion.root_motion_rotation().is_equal_approx(players[1].motion.root_motion_rotation()),"Compensation preserves extracted root rotation")
	for bone in a.get_bone_count():
		var name := String(a.get_bone_name(bone)).trim_prefix("SEG-")
		var lower := name=="DEF-spine" or name.begins_with("DEF-spine-")
		for prefix in ["DEF-pelvis.","DEF-thigh.","DEF-shin.","DEF-foot.","DEF-toe."]:lower=lower or name.begins_with(prefix)
		if not lower:continue
		var original := a.get_bone_global_pose(bone);var actual := b.get_bone_global_pose(bone)
		max_leg_error=maxf(max_leg_error,original.origin.distance_to(actual.origin));check(original.is_equal_approx(actual),"Authored pelvis/leg transform stays intact: "+name)
	for name in ["DEF-spine.003","DEF-hand.R","DEF-hand.L","DEF-spine.006"]:
		check(a.get_bone_global_pose(a.find_bone(name)).is_equal_approx(b.get_bone_global_pose(b.find_bone(name))),"Chest, head and grip keep the authored look pose: "+name)
	check(is_equal_approx(players[0].motion.mixer.current_animation_position,players[1].motion.mixer.current_animation_position),"Compensation never retimes or restarts the locomotion clip")
func sample(clip: String,time: float) -> void:
	for p in players:
		var m: Node3D=p.motion;m._restore_pose_layers();m.walk_spine.reset();m.current="";m.blend_time=0;m.play(clip);m.walk_spine.response=0
	compare(time)
func kink(p: Node3D) -> float:
	var layer: RefCounted=p.motion.walk_spine;var s: Skeleton3D=p.motion.body_skeleton
	var low := s.find_bone("DEF-spine.001");var mid := s.find_bone("DEF-spine.002")
	return absf(wrapf(layer._heading(mid,s.get_bone_global_pose(mid))-layer._heading(low,s.get_bone_global_pose(low)),-PI,PI))
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	for action in ["forward","back","left","right","sprint","aim","fire","reload","flashlight","shoulder","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	for index in 2:
		var p: Node3D=load("res://scenes/player.tscn").instantiate();root.add_child(p);p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false);p.camera_collision_enabled=false;p.pitch=0;p.reset_camera_follow();p.motion.walk_spine.enabled=index==1;players.append(p)
	for clip in ["forward_left","forward_right","backward_left","backward_right"]:
		for time in [0.0,.3,.8,1.6,2.8,3.9]:
			sample(clip,time);var before := kink(players[0]);var after := kink(players[1]);greatest_before=maxf(greatest_before,before);greatest_after=maxf(greatest_after,after)
			check(after<before*.7,"Diagonal waist counter-twist is spread across the back: "+clip+" "+str(time))
			var s: Skeleton3D=players[1].motion.body_skeleton;var waist := s.get_bone_global_pose(s.find_bone("DEF-spine.001"));var grip := s.get_bone_global_pose(s.find_bone("DEF-hand.R"))
			for frame in 30:players[1]._apply_upper_body_look()
			check(s.get_bone_global_pose(s.find_bone("DEF-spine.001")).is_equal_approx(waist) and s.get_bone_global_pose(s.find_bone("DEF-hand.R")).is_equal_approx(grip),"Repeated render updates never accumulate spine correction")
	for clip in ["idle","walk","strafe_left","strafe_right","backward","run"]:
		sample(clip,.6)
		check(is_zero_approx(players[1].motion.walk_spine.weight),"Other authored clips remain unmodified: "+clip)
	# Exercise actual interruptible crossfades, not frozen representative poses.
	for p in players:p.motion.blend_time=.22;p.motion.walk_spine.response=.10
	for clip in ["forward_left","forward_right","backward_left","backward_right","walk","idle","forward_left","run"]:
		for p in players:p.motion.play(clip)
		for frame in 20:compare(1.0/60)
	for p in players:p.motion.set_aiming(true,.18);p.motion.play("forward_left")
	for frame in 30:compare(1.0/60)
	for p in players:p.motion.reload_weapon()
	for frame in 45:compare(1.0/30)
	for p in players:
		p.motion.cancel_reload();p.motion.set_aiming(false,0);p.motion.blend_time=0;p.motion.play("idle");p.motion.advance_motion(.3);p.motion.turn_in_place.weight=0;p.motion.turn_in_place.active=false;p.motion.turn_in_place.start()
	for frame in 10:compare(1.0/60)
	for p in players:
		for audio in p.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.15).timeout
	for p in players:p.queue_free()
	await process_frame;await create_timer(.15).timeout
	var report := {"ok":failures.is_empty(),"checks":checks,"errors":failures,"maximum_root_error_m":max_root_error,"maximum_leg_error_m":max_leg_error,"largest_waist_step_before_degrees":rad_to_deg(greatest_before),"largest_waist_step_after_degrees":rad_to_deg(greatest_after)}
	FileAccess.open("res://docs/walk-spine-compensation-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("WALK_SPINE_COMPENSATION_OK " if failures.is_empty() else "WALK_SPINE_COMPENSATION_FAILED ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
