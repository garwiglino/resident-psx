extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func raw_position(animation: Animation,bone: String,time: float) -> Vector3:
	var track := animation.find_track(NodePath("rig/Skeleton3D:"+bone),Animation.TYPE_POSITION_3D)
	assert(track>=0)
	return animation.position_track_interpolate(track,fposmod(time,animation.length))
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.psx_renderer.set_process(false)
	var p=game.player
	p.set_process(false);p.set_physics_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	await create_timer(.1).timeout
	var m=p.motion
	var sk: Skeleton3D=m.model.get_node("rig/Skeleton3D")
	var duration := .5
	report.startup=[];report.pose_weights=[]
	for clip in ["walk","strafe_right","backward_left"]:
		for speed in [.5,1.0,2.0]:
			m.current="";m.blend_time=0;m.play("idle");m.advance_motion(0);m.advance_motion(.7)
			m.blend_time=duration;m.play(clip,speed);m.advance_motion(0)
			var animation: Animation=m.mixer.get_animation(clip)
			var track := animation.find_track(NodePath("rig/Skeleton3D:RootMotion"),Animation.TYPE_POSITION_3D)
			var expected: Vector3=animation.position_track_interpolate(track,speed/60.0)-animation.position_track_interpolate(track,0)
			var actual: Vector3=m.advance_motion(1.0/60)
			var ratio := actual.length()/expected.length()
			report.startup.append({"clip":clip,"speed":speed,"first_tick_root_ratio":ratio})
			check(actual.distance_to(expected)<.0001,"Authored root motion responds on the first tick, independent of a 0.5 s pose blend: "+clip)
	for pair in [["idle","walk"],["walk","strafe_left"],["strafe_right","backward_left"]]:
		m.current="";m.blend_time=0;m.play(pair[0]);m.advance_motion(0);m.advance_motion(.7)
		m.blend_time=duration;m.play(pair[1]);m.advance_motion(0)
		var outgoing: Animation=m.mixer.get_animation(pair[0])
		var incoming: Animation=m.mixer.get_animation(pair[1])
		for frame in 30:
			m.advance_motion(1.0/60)
			if frame+1 not in [6,15,24]:continue
			var elapsed: float=(frame+1)/60.0
			var weights: Array[float]=[]
			for bone in ["DEF-foot.L","DEF-foot.R","DEF-toe.L","DEF-toe.R","DEF-hand.L","DEF-hand.R"]:
				var a := raw_position(outgoing,bone,.7+elapsed)
				var b := raw_position(incoming,bone,elapsed)
				if a.distance_to(b)<.03:continue
				var actual := sk.get_bone_pose_position(sk.find_bone(bone))
				var weight := (actual-a).dot(b-a)/a.distance_squared_to(b)
				check(actual.distance_to(a.lerp(b,weight))<.001,"Pose lies between both advancing animations: "+bone)
				weights.append(weight)
			check(not weights.is_empty(),"Different source poses are available for blend validation")
			var mean := 0.0
			for weight in weights:mean+=weight
			mean/=maxi(weights.size(),1)
			var expected: float=elapsed/duration
			report.pose_weights.append({"from":pair[0],"to":pair[1],"elapsed":elapsed,"expected_weight":expected,"actual_weight":mean})
			check(absf(mean-expected)<.001,"Continuous pose crossfade, rather than a delayed start: %s -> %s at %.2f s, weight %.3f" % [pair[0],pair[1],elapsed,mean])
	# Exercise the actual capsule/controller, not just the animation sampler.
	report.controller=[]
	p.enabled=true;p.root_motion_enabled=true;p.root_motion_scale=1;p.root_motion_playback_speed=1;p.animation_blend_time=duration
	for actions in [["forward"],["forward","left"],["back","right"]]:
		m.current="";m.blend_time=0;m.play("idle");m.advance_motion(0)
		p.position=Vector3(0,.04,6.2);p.rotation=Vector3.ZERO;p.visual.rotation=Vector3.ZERO;p.velocity=Vector3.ZERO;p.reset_camera_follow()
		for action in actions:Input.action_press(action)
		var start: Vector3=p.position
		await physics_frame
		p._physics_process(1.0/60)
		var movement: Vector3=p.position-start;movement.y=0
		var expected: float=m.clip_metadata[m.current].average_speed/60.0
		check(absf(movement.length()-expected)<.0001,"Capsule starts at the authored stride speed on the first input tick: "+str(actions))
		report.controller.append({"actions":actions,"first_tick_distance_m":movement.length(),"expected_distance_m":expected})
		for action in actions:Input.action_release(action)
	report.failures=failures
	FileAccess.open("res://docs/animation-response-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free();await process_frame
	print("ANIMATION_RESPONSE_OK: immediate authored root motion and measured crossfades between two advancing poses" if failures.is_empty() else "ANIMATION_RESPONSE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
