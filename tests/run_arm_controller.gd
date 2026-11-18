extends SceneTree
var failures: Array[String]=[]
var peak_error := 0.0
var transitions := 0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	for action in ["forward","back","left","right","sprint","aim","fire","reload","flashlight","shoulder","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	var p=load("res://scenes/player.tscn").instantiate();root.add_child(p);p.set_process(false);p.set_physics_process(false)
	p.enabled=true;p.controls_blocked=false
	p.camera_collision_enabled=false;p.camera_translation_lag=0;p.camera_rotation_lag=0
	var m=p.motion;var sk: Skeleton3D=m.body_skeleton
	var bones: Array[int]=[]
	for bone in sk.get_bone_count():
		if String(sk.get_bone_name(bone)).begins_with("DEF-forearm.R"):bones.append(bone)
	for destination in ["walk","idle"]:
		for phase in 32:
			Input.action_press("forward");Input.action_press("sprint")
			p.position=Vector3.ZERO;p.velocity=Vector3.ZERO;p.pitch=.18;p.look_yaw=.15;p.reset_camera_follow(false)
			p._physics_process(1.0/60)
			m.current="";m.blend_time=0;m.play("run",p.run_animation_speed)
			var outgoing: Animation=m.mixer.get_animation("run");var incoming: Animation=m.mixer.get_animation(destination)
			var start: float=outgoing.length*phase/32.0
			m.advance_motion(start/p.run_animation_speed);p._apply_upper_body_look()
			Input.action_release("sprint")
			if destination=="idle":Input.action_release("forward")
			for frame in 20:
				p._physics_process(1.0/60);p._process(1.0/60)
				var elapsed := (frame+1)/60.0;var weight: float=clampf(elapsed/p.animation_blend_time,0,1)
				for bone in bones:
					var path := NodePath("rig/Skeleton3D:"+String(sk.get_bone_name(bone)))
					var a := outgoing.find_track(path,Animation.TYPE_ROTATION_3D);var b := incoming.find_track(path,Animation.TYPE_ROTATION_3D)
					var expected := outgoing.rotation_track_interpolate(a,fposmod(start+elapsed,outgoing.length)).slerp(incoming.rotation_track_interpolate(b,fposmod(elapsed,incoming.length)),weight)
					# Capture is the actual locomotion pose underneath the additive mouse look.
					var actual: Quaternion=m.upper_body.base_poses[bone].basis.get_rotation_quaternion()
					var error := rad_to_deg(expected.angle_to(actual));peak_error=maxf(peak_error,error)
					if error>2:failures.append("%s -> %s phase %d frame %d: %.2f" % [sk.get_bone_name(bone),destination,phase,frame,error])
			transitions+=1
	Input.action_release("forward");Input.action_release("sprint")
	p.queue_free();await process_frame
	FileAccess.open("res://docs/run-arm-controller-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"transitions":transitions,"peak_error_degrees":peak_error,"failures":failures},"\t"))
	print("RUN_ARM_CONTROLLER_OK " if failures.is_empty() else "RUN_ARM_CONTROLLER_FAILED ",str({"transitions":transitions,"peak_error_degrees":peak_error,"failures":failures.slice(0,8)}))
	quit(0 if failures.is_empty() else 1)
