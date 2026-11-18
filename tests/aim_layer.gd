extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={"poses":[],"directions":[]}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player
	p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	await create_timer(.1).timeout
	var m=p.motion
	var sk: Skeleton3D=m.body_skeleton
	var source=load("res://assets/character/animations/player_pistol_aim_pose.glb").instantiate()
	root.add_child(source)
	var source_sk: Skeleton3D=source.get_node("rig/Skeleton3D")
	var source_player: AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0]
	source_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	source_player.play(source_player.get_animation_list()[0],0);source_player.advance(0)
	var pelvis := sk.find_bone("DEF-spine")
	var source_pelvis := source_sk.get_bone_global_pose(source_sk.find_bone("DEF-spine"))
	source_pelvis.basis=Basis.IDENTITY
	var lower: Array[int]=[]
	var upper: Array[int]=[]
	for entry in m.aim_pose.entries:upper.append(entry.bone)
	for bone in sk.get_bone_count():
		if bone not in upper:lower.append(bone)
	check(pelvis in lower and sk.find_bone("RootMotion") in lower,"Aim mask excludes pelvis and root motion")
	for bone in lower:
		var name := String(sk.get_bone_name(bone))
		check(not (name.begins_with("DEF-hand") or name.begins_with("DEF-shoulder")),"Upper limbs are inside the aim mask")
	for clip in ["idle"]+m.WALK_DIRECTIONS:
		for time in [.0,.7,2.3,3.7]:
			m.set_aiming(false,0);m.current="";m.blend_time=0;m.play(clip);m.advance_motion(time)
			var unchanged: Dictionary={}
			for bone in lower:unchanged[bone]=sk.get_bone_pose(bone)
			m.set_aiming(true,0);m.advance_motion(0)
			for bone in lower:check(sk.get_bone_pose(bone).is_equal_approx(unchanged[bone]),"Aim preserves lower-body pose: "+clip+" "+String(sk.get_bone_name(bone)))
			var anchor := sk.get_bone_global_pose(pelvis)
			anchor.basis=Basis.IDENTITY
			anchor=anchor*source_pelvis.affine_inverse()
			var position_error := 0.0;var rotation_error := 0.0
			for entry in m.aim_pose.entries:
				var source_bone := source_sk.find_bone(sk.get_bone_name(entry.bone))
				var expected := anchor*source_sk.get_bone_global_pose(source_bone)
				var actual := sk.get_bone_global_pose(entry.bone)
				position_error=maxf(position_error,actual.origin.distance_to(expected.origin))
				rotation_error=maxf(rotation_error,actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()))
			check(position_error<.0001 and rotation_error<.002,"Aimed upper body follows only pelvis translation while retaining the saved orientation: "+clip)
			var root_delta: Vector3=m.advance_motion(1.0/60)
			var aimed_lower: Dictionary={}
			for bone in lower:aimed_lower[bone]=sk.get_bone_pose(bone)
			m.set_aiming(false,0);m.current="";m.blend_time=0;m.play(clip);m.advance_motion(time);var normal_delta: Vector3=m.advance_motion(1.0/60)
			for bone in lower:check(sk.get_bone_pose(bone).is_equal_approx(aimed_lower[bone]),"Pelvis and legs keep advancing identically while aiming: "+clip)
			check(root_delta.distance_to(normal_delta)<.00001,"Aim does not alter authored root motion: "+clip)
			report.poses.append({"clip":clip,"time":time,"upper_position_error_m":position_error,"upper_rotation_error_degrees":rad_to_deg(rotation_error),"root_difference_m":root_delta.distance_to(normal_delta)})
	# The independent pistol must match the source grip, rather than merely
	# remaining attached to a correctly posed hand.
	m.current="";m.play("idle");m.set_aiming(true,0);m.advance_motion(0)
	m.weapon.mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	m.weapon.mixer.play("pistol_idle",0);m.weapon.mixer.seek(0,true)
	m.hand_attachment.on_skeleton_update()
	var actual_pelvis := sk.get_bone_global_pose(pelvis)
	actual_pelvis.basis=Basis.IDENTITY
	var inverse_model: Transform3D=m.model.global_transform.affine_inverse()
	var alignment: Transform3D=inverse_model*sk.global_transform*actual_pelvis*source_pelvis.affine_inverse()*source_sk.global_transform.affine_inverse()
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/split-export-player_pistol_aim_pose.json"))
	report.weapon_source=[]
	for entry in game.psx_renderer.entries:
		if entry.skeleton!=m.weapon.skeleton:continue
		var name: String=entry.node.name
		if not reference.samples[0].meshes.has(name):continue
		var expected: PackedVector3Array=[]
		for xyz in reference.samples[0].meshes[name]:expected.append(alignment*Vector3(xyz[0],xyz[1],xyz[2]))
		var transforms: Array[Transform3D]=[]
		for bind in entry.binds.size():transforms.append(inverse_model*entry.skeleton.global_transform*entry.skeleton.get_bone_global_pose(entry.bind_indices[bind])*entry.binds[bind])
		var error := 0.0
		var stride: int=entry.bones.size()/entry.vertices.size()
		for vertex in entry.vertices.size():
			var actual := Vector3.ZERO
			for influence in stride:actual+=(transforms[entry.bones[vertex*stride+influence]]*entry.vertices[vertex])*entry.weights[vertex*stride+influence]
			var closest := INF
			for point in expected:closest=minf(closest,actual.distance_squared_to(point))
			error=maxf(error,sqrt(closest))
		report.weapon_source.append({"mesh":name,"error_m":error})
		check(error<.001,"Attached pistol matches the saved Blender aim grip within 1 mm: "+name)
	# Isolate pelvis sway from aiming: yaw, pitch and roll in a locomotion
	# pose must not steer either the torso or the pistol away from the view.
	m.set_aiming(false,0);m.current="";m.play("strafe_left");m.advance_motion(2)
	var pelvis_before := sk.get_bone_global_pose(pelvis)
	m.set_aiming(true,0);m.advance_motion(0)
	var upper_before: Dictionary={}
	for entry in m.aim_pose.entries:upper_before[entry.bone]=sk.get_bone_global_pose(entry.bone)
	m.apply_look(sk.global_basis*Vector3.BACK,deg_to_rad(55),deg_to_rad(50),true)
	var muzzle_before: Transform3D=m.weapon.get_muzzle_transform()
	report.pelvis_rotation=[]
	for angles in [Vector3(0,70,0),Vector3(0,-70,0),Vector3(25,0,0),Vector3(-25,0,0),Vector3(0,0,20),Vector3(0,0,-20),Vector3(20,55,-15)]:
		m._restore_pose_layers()
		var shift := Vector3(.025,.04,-.015)
		var changed := pelvis_before
		changed.origin+=shift
		changed.basis=Basis.from_euler(angles*PI/180)*pelvis_before.basis
		sk.set_bone_global_pose(pelvis,changed)
		var lower_snapshot: Dictionary={}
		for bone in lower:lower_snapshot[bone]=sk.get_bone_pose(bone)
		m._apply_pose_layers(0)
		var position_error := 0.0;var rotation_error := 0.0
		for entry in m.aim_pose.entries:
			var expected: Transform3D=upper_before[entry.bone]
			expected.origin+=shift
			var actual := sk.get_bone_global_pose(entry.bone)
			position_error=maxf(position_error,actual.origin.distance_to(expected.origin))
			rotation_error=maxf(rotation_error,actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()))
		m.apply_look(sk.global_basis*Vector3.BACK,deg_to_rad(55),deg_to_rad(50),true)
		var muzzle: Transform3D=m.weapon.get_muzzle_transform()
		var muzzle_angle := muzzle.basis.get_rotation_quaternion().angle_to(muzzle_before.basis.get_rotation_quaternion())
		check(position_error<.0001 and rotation_error<.002,"Pelvis rotations cannot steer the aimed upper body: "+str(angles))
		check(muzzle_angle<.002 and muzzle.origin.distance_to(muzzle_before.origin+sk.global_basis*shift)<.0001,"Pistol follows pelvis translation without inheriting yaw, pitch or roll")
		for bone in lower:check(sk.get_bone_pose(bone).is_equal_approx(lower_snapshot[bone]),"Aim cancellation preserves authored pelvis and leg rotations")
		report.pelvis_rotation.append({"pelvis_degrees":str(angles),"upper_position_error_m":position_error,"upper_rotation_error_degrees":rad_to_deg(rotation_error),"muzzle_rotation_error_degrees":rad_to_deg(muzzle_angle)})
	# Raising/lowering the weapon never starts another locomotion clip.
	m.set_aiming(false,0);m.current="";m.play("strafe_left");m.advance_motion(1)
	m.set_aiming(true,.2);m.advance_motion(.1)
	check(is_equal_approx(m.aim_pose.weight,.5),"Aim pose fades in without delaying locomotion")
	check(m.current=="strafe_left" and absf(m.mixer.current_animation_position-1.1)<.00001,"Aim keeps the locomotion clip and playback phase")
	var head := sk.find_bone("DEF-spine.006")
	var before_head := sk.get_bone_global_pose(head)
	var hand := sk.find_bone("DEF-hand.R")
	m.hand_attachment.on_skeleton_update()
	var before_mount: Transform3D=(sk.global_transform*sk.get_bone_global_pose(hand)).affine_inverse()*m.weapon.global_transform
	var lower_before: Dictionary={}
	for bone in lower:lower_before[bone]=sk.get_bone_pose(bone)
	var direction: Vector3=sk.global_basis*(Basis(Vector3.UP,.4)*Basis(Vector3.RIGHT,-.2)*Vector3.BACK)
	m.apply_look(direction,deg_to_rad(55),deg_to_rad(50),true)
	var looked_head := sk.get_bone_global_pose(head)
	check(looked_head.origin.distance_to(before_head.origin)>.001,"Mouse look still acts above the authored aim layer")
	for bone in lower:check(sk.get_bone_pose(bone).is_equal_approx(lower_before[bone]),"Aimed mouse look preserves the lower animation")
	var looked_mount: Transform3D=(sk.global_transform*sk.get_bone_global_pose(hand)).affine_inverse()*m.weapon.global_transform
	check(looked_mount.is_equal_approx(before_mount),"Aimed mouse look preserves the pistol grip")
	for frame in 120:m.apply_look(direction,deg_to_rad(55),deg_to_rad(50),true)
	check(sk.get_bone_global_pose(head).is_equal_approx(looked_head),"Aim and mouse layers do not accumulate rotation on render frames")
	m.set_aiming(false,.2);m.advance_motion(.1)
	check(is_zero_approx(m.aim_pose.weight) and absf(m.mixer.current_animation_position-1.2)<.00001,"Releasing aim resumes the advancing base pose without restarting it")
	# Exercise all eight directions through the actual aiming controller.
	p.enabled=true;p.root_motion_enabled=true;p.root_motion_scale=1;p.root_motion_playback_speed=1
	var actions := [["forward"],["forward","right"],["right"],["back","right"],["back"],["back","left"],["left"],["forward","left"]]
	for index in 8:
		p.position=Vector3(0,.05,6.2);p.rotation=Vector3.ZERO;p.visual.rotation=Vector3.ZERO;p.velocity=Vector3.ZERO;p.reset_camera_follow()
		m.set_aiming(false,0);m.current="";m.play("idle");m.advance_motion(0)
		Input.action_press("aim")
		for action in actions[index]:Input.action_press(action)
		var before: Vector3=p.position
		await physics_frame
		p._physics_process(1.0/60)
		check(p.aiming and m.current==m.WALK_DIRECTIONS[index],"Aiming uses the same directional animation: "+m.WALK_DIRECTIONS[index])
		var movement: Vector3=p.position-before;movement.y=0
		check(absf(movement.length()-1.473903/60)<.0001,"Aimed movement keeps authored stride speed: "+m.current)
		report.directions.append({"clip":m.current,"first_tick_distance_m":movement.length()})
		for action in actions[index]:Input.action_release(action)
		Input.action_release("aim")
	# Camera makes a reversible, gradual shoulder zoom with an unchanged mouse target.
	p.aiming=false;p.camera_collision_enabled=false;p.camera_translation_lag=0;p.camera_rotation_lag=0
	p._camera_aim_weight=0;p.reset_camera_follow();p.update_camera_follow(0)
	var base_fov: float=p.camera.fov
	p.aiming=true;p.update_camera_follow(1.0/60)
	check(p.camera.fov<base_fov and p.camera.fov>p.aim_camera_fov,"Aim camera starts a gradual FOV transition")
	check(p.arm.spring_length<p.camera_offset.z and p.arm.spring_length>p.aim_camera_offset.z,"Aim camera starts moving towards the shoulder")
	for frame in 60:p.update_camera_follow(1.0/60)
	check(absf(p.camera.fov-p.aim_camera_fov)<.0001 and absf(p.arm.spring_length-p.aim_camera_offset.z)<.0001,"Aim camera reaches the requested FOV and distance")
	check(absf(p.arm.position.x-p.shoulder*p.aim_camera_offset.x)<.001 and absf(p.camera_pivot.global_position.y-p.global_position.y-p.aim_camera_offset.y)<.001,"Aim framing uses the requested shoulder and height")
	report.camera={"base_fov":base_fov,"aim_fov":p.camera.fov,"aim_distance_m":p.arm.spring_length,"aim_offset":str(p.aim_camera_offset)}
	p.aiming=false
	for frame in 60:p.update_camera_follow(1.0/60)
	check(absf(p.camera.fov-p.camera_fov)<.0001 and absf(p.arm.spring_length-p.camera_offset.z)<.0001,"Releasing aim restores the user's normal framing")
	var fovs: Array[float]=[]
	for fps in [30,60,120]:
		p._camera_aim_weight=0;p.aiming=true
		for frame in fps/10:p.update_camera_follow(1.0/fps)
		fovs.append(p.camera.fov)
	check(absf(fovs[0]-fovs[1])<.0001 and absf(fovs[1]-fovs[2])<.0001,"Aim camera transition timing is independent of frame rate")
	report.failures=failures
	FileAccess.open("res://docs/aim-layer-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	source.queue_free()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free();await process_frame
	print("AIM_LAYER_OK: translation-only pelvis follow, stable aimed torso/pistol orientation, unchanged legs/root, eight direction clips and shoulder camera" if failures.is_empty() else "AIM_LAYER_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
