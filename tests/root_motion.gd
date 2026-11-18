extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	# Isolate locomotion from artist-authored conversations at the origin.
	# The fixture teleports into several map locations to exercise collisions.
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game)
	game.set_process(false)
	game.psx_renderer.set_process(false)
	var p=game.player
	p.free_orbit_enabled=false
	p.set_physics_process(false)
	# Real cursor events must not rotate the fixture during synthetic movement.
	p.set_process_unhandled_input(false)
	p.enabled=true
	for enemy in game.enemies:enemy.set_physics_process(false)
	var m=p.motion
	var skeleton: Skeleton3D=m.model.get_node("rig/Skeleton3D")
	var directions := {"walk":Vector3.BACK,"backward":Vector3.FORWARD,"strafe_left":Vector3.RIGHT,"strafe_right":Vector3.LEFT,
		"forward_left":Vector3(1,0,1).normalized(),"forward_right":Vector3(-1,0,1).normalized(),
		"backward_left":Vector3(1,0,-1).normalized(),"backward_right":Vector3(-1,0,-1).normalized()}
	for clip in directions:
		m.current=""
		m.play(clip)
		m.mixer.play(clip,0)
		m.mixer.advance(0)
		m.mixer.seek(0,true)
		m.advance_motion(0)
		var total := Vector3.ZERO
		var largest := 0.0
		for i in 480:
			var d: Vector3=m.advance_motion(1.0/60)
			total+=d
			largest=maxf(largest,d.length())
		check(total.distance_to(directions[clip]*11.79122)<.015,"Authored direction and distance across two loops: %s %s" % [clip,total])
		check(largest<.08,"No displacement spike at loop boundary")
		check(skeleton.get_bone_pose_position(skeleton.find_bone("RootMotion")).length()<.0001,"Root travel removed from visible skeleton")
		var axis := Vector2(-directions[clip].x,-directions[clip].z)
		check(m.locomotion_clip(axis)==clip,"Eight-way input selects "+clip)
	# Analog sector boundaries are halfway between authored directions.
	check(m.locomotion_clip(Vector2(.3,-1))=="walk","Shallow analog input stays forward")
	check(m.locomotion_clip(Vector2(.5,-1))=="forward_right","Analog input selects the nearest diagonal")
	# Exercise the actual controller, including rotation and wall collisions.
	p.position=Vector3(0,.04,0)
	p.rotation.y=PI/2
	p.reset_camera_follow()
	Input.action_press("forward")
	for i in 120:
		await physics_frame
		p._physics_process(1.0/60)
	check(p.position.x < -1.55,"Player rotation transforms authored root displacement")
	var stopped_x: float=p.position.x
	for i in 120:
		await physics_frame
		p._physics_process(1.0/60)
	check(absf(p.position.x-stopped_x)<.15,"Root motion respects the corridor wall")
	Input.action_release("forward")
	check(m.current=="walk","Controller selects authored forward clip")
	for action in ["left","right"]:
		p.position=Vector3(0,.04,2)
		p.velocity=Vector3.ZERO
		p.rotation=Vector3.ZERO
		p.reset_camera_follow()
		var stopped_position_z: float=p.position.z
		Input.action_press(action)
		for i in 90:
			await physics_frame
			p._physics_process(1.0/60)
			if i==59:stopped_position_z=p.position.z
		Input.action_release(action)
		# Includes the .18 s transition from the previous movement direction.
		check(p.position.x< -1.15 if action=="left" else p.position.x>1.15,"Authored root-motion strafe direction: %s %s" % [action,p.position])
		check(absf(p.position.z-stopped_position_z)<.01,"Settled strafe preserves forward/backward position: "+str(p.position))
	for clip in ["forward_left","forward_right","backward_left","backward_right"]:
		var wanted: Vector3=-directions[clip]
		p.position=Vector3(0,.04,6.2)
		p.velocity=Vector3.ZERO
		p.rotation=Vector3.ZERO
		p.reset_camera_follow()
		var horizontal: String="left" if wanted.x<0 else "right"
		var vertical: String="forward" if wanted.z<0 else "back"
		Input.action_press(horizontal)
		Input.action_press(vertical)
		var settled_position: Vector3=p.position
		for i in 90:
			await physics_frame
			p._physics_process(1.0/60)
			if i==29:settled_position=p.position
		Input.action_release(horizontal)
		Input.action_release(vertical)
		var travel: Vector3=p.position-settled_position
		travel.y=0
		check(m.current==clip,"Controller plays authored diagonal: "+clip)
		check(travel.normalized().dot(wanted)>.999,"Diagonal follows camera-relative input: "+clip)
		check(absf(travel.length()-1.4739027)<.015,"Diagonal retains authored speed without sqrt(2) boost: "+clip)
	print("ROOT_MOTION_OK: eight directions, authored distance, two loops, visual extraction, analog sectors, rotated movement, wall collision, actual strafes and diagonals" if failures.is_empty() else "ROOT_MOTION_FAILED "+str(failures))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
