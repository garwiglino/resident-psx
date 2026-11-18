extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={"frames":[]}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func source_player(model: Node) -> AnimationPlayer:
	var player: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(player.get_animation_list()[0],0);player.advance(0)
	return player
func run() -> void:
	seed(5001)
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player
	p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.position=Vector3(0,.05,6);p.rotation=Vector3.ZERO;p.reset_camera_follow()
	await create_timer(.1).timeout
	var m=p.motion;var w=m.weapon
	var sk: Skeleton3D=m.body_skeleton
	var body=load("res://assets/character/animations/player_pistol_fire.glb").instantiate()
	var gun=load("res://assets/weapons/animations/pistol_fire.glb").instantiate()
	var base=load("res://assets/character/cop_player.glb").instantiate()
	root.add_child(body);root.add_child(gun);root.add_child(base)
	var body_player := source_player(body);var gun_player := source_player(gun)
	var source_sk: Skeleton3D=body.get_node("rig/Skeleton3D")
	var source_gun: Skeleton3D=gun.find_child("Skeleton3D",true,false)
	for imported in base.find_children("*","AnimationPlayer",true,false):imported.active=false
	var baseline := AnimationPlayer.new()
	base.add_child(baseline);baseline.root_node=NodePath("..");baseline.root_motion_track=m.mixer.root_motion_track
	baseline.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new();library.add_animation("strafe_left",m.mixer.get_animation("strafe_left"))
	baseline.add_animation_library("",library);baseline.play("strafe_left",0);baseline.advance(0);baseline.advance(1.5)
	var baseline_sk: Skeleton3D=base.get_node("rig/Skeleton3D")
	var affected: Array[int]=[]
	for entry in m.aim_pose.entries:affected.append(entry.bone)
	var pelvis := sk.find_bone("DEF-spine")
	var body_metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/animations/player_pistol_fire.json"))
	var gun_metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/animations/pistol_fire.json"))
	check(absf(m.aim_pose.fire_length-body_metadata.duration)<.00001,"Character fire preserves the updated Blender strip duration")
	check(absf(w.mixer.get_animation("pistol_fire").length-gun_metadata.duration)<.00001,"Pistol preserves its own updated strip duration")
	check(body_metadata.fps==gun_metadata.fps and body_metadata.start_frame==gun_metadata.start_frame,"Both animations share their original FPS and starting frame")
	m.current="";m.blend_time=0;m.set_aiming(true,0);m.play("strafe_left");m.advance_motion(1.5)
	m.fire();p._apply_upper_body_look()
	check(m.current=="strafe_left" and absf(m.mixer.current_animation_position-1.5)<.00001,"Firing never replaces or restarts locomotion")
	check(m.aim_pose.fire_time==0 and w.shot_time==0 and w.mixer.current_animation_position==0,"Character and pistol fire start on exactly the same tick")
	var ejection_tested := false;var reset_tested := false
	for frame in int(body_metadata.end_frame-body_metadata.start_frame+1):
		var time := frame/float(body_metadata.fps)
		if frame>0:m.advance_motion(1.0/float(body_metadata.fps));baseline.advance(1.0/float(body_metadata.fps))
		p._apply_upper_body_look()
		body_player.seek(time,true);gun_player.seek(time,true)
		var source_pelvis := source_sk.get_bone_global_pose(source_sk.find_bone("DEF-spine"))
		source_pelvis.basis=Basis.IDENTITY
		var anchor := sk.get_bone_global_pose(pelvis);anchor.basis=Basis.IDENTITY
		anchor=anchor*source_pelvis.affine_inverse()
		var max_position := 0.0;var max_rotation := 0.0
		for entry in m.aim_pose.entries:
			var expected := anchor*source_sk.get_bone_global_pose(source_sk.find_bone(sk.get_bone_name(entry.bone)))
			var actual := sk.get_bone_global_pose(entry.bone)
			max_position=maxf(max_position,actual.origin.distance_to(expected.origin))
			max_rotation=maxf(max_rotation,actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()))
		check(max_position<.0001 and max_rotation<.002,"Upper recoil matches the Blender export at authored frame "+str(frame+1))
		for bone in sk.get_bone_count():
			if bone not in affected:check(sk.get_bone_pose(bone).is_equal_approx(baseline_sk.get_bone_pose(bone)),"Shooting preserves moving pelvis, legs and root: "+String(sk.get_bone_name(bone)))
		for bone in w.skeleton.get_bone_count():
			var name := String(w.skeleton.get_bone_name(bone))
			if name==w.bullet_bone:continue
			check(w.skeleton.get_bone_pose(bone).is_equal_approx(source_gun.get_bone_pose(source_gun.find_bone(name))),"Pistol mechanics match Blender: "+name+" at "+str(time))
		check(absf(m.aim_pose.fire_time-w.shot_time)<.000001,"Shared body/pistol timing remains exact throughout recoil")
		if frame==2:
			check(w._attached_case>=0,"The actual b_bullet bone ejects while the slide is open")
			var world_before: Transform3D=w.skeleton.global_transform*w.skeleton.get_bone_global_pose(w._bullet_bone)
			var before: Vector3=p.position
			p.position+=Vector3(.3,0,0);p._apply_upper_body_look()
			var world_after: Transform3D=w.skeleton.global_transform*w.skeleton.get_bone_global_pose(w._bullet_bone)
			check(world_before.origin.distance_to(world_after.origin)<.00001,"Ejected bone moves through world space independently of the hand")
			p.position=before;p._apply_upper_body_look();ejection_tested=true
		if frame==3:
			check(w._attached_case<0,"Bullet bone is restored when the slide closes at frame 4")
			check(w.skeleton.get_bone_pose(w._bullet_bone).is_equal_approx(source_gun.get_bone_pose(source_gun.find_bone(w.bullet_bone))),"Bullet bone resets to its authored pose")
			check(w.casings[0].mesh.visible and w.casings[0].time_left>0,"The ejected copy continues after the bone resets")
			reset_tested=true
		report.frames.append({"frame":frame+1,"body_time":m.aim_pose.fire_time,"gun_time":w.shot_time,"max_source_position_error_m":max_position,"max_source_rotation_error_degrees":rad_to_deg(max_rotation),"attached_case":w._attached_case})
	check(ejection_tested and reset_tested,"Ejection and reset were exercised")
	# Root playback speed is independent of the weapon's real-time action clock.
	m.play("strafe_right",2);m.fire();p._apply_upper_body_look()
	for frame in 6:m.advance_motion(1.0/60);p._apply_upper_body_look()
	check(absf(m.aim_pose.fire_time-.1)<.000001 and absf(w.mixer.current_animation_position-.1)<.000001,"Changing locomotion playback speed never retimes gunfire")
	var pool_ids: Array=[]
	for casing in w.casings:pool_ids.append(casing.mesh.get_instance_id())
	var variants: Dictionary={};var previous := -1
	for shot in 32:
		m.fire();p._apply_upper_body_look()
		m.advance_motion(w.ejection_delay+.001);p._apply_upper_body_look()
		check(w.flash_variant>=0 and w.flash_variant<16 and w.flash_variant!=previous,"Every shot chooses a valid random atlas cell without immediate repetition")
		previous=w.flash_variant;variants[previous]=true
	check(variants.size()>=8,"Random shots use visibly different flash shapes")
	for index in w.casings.size():check(w.casings[index].mesh.get_instance_id()==pool_ids[index],"Repeated fire reuses the registered casing pool")
	check(w.casings.size()==8,"Casing geometry remains bounded during repeated fire")
	var base_time: float=m.mixer.current_animation_position
	m.set_aiming(false,.05)
	for frame in 90:m.advance_motion(0,1.0/60);p._apply_upper_body_look()
	check(is_equal_approx(m.mixer.current_animation_position,base_time),"Disabling body playback still lets gun actions and effects finish on their own clock")
	check(m.aim_pose.fire_time<0 and w.flash_time_left==0 and w._attached_case<0,"Releasing aim and completing a shot clears recoil, flash and bone override")
	for casing in w.casings:check(not casing.mesh.visible and casing.time_left==0,"Expired casings leave no persistent meshes")
	report.flash_variants=variants.keys();report.pool_size=w.casings.size();report.failures=failures
	FileAccess.open("res://docs/shooting-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	body.queue_free();gun.queue_free();base.queue_free()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free();await process_frame;await create_timer(.08).timeout
	print("SHOOTING_OK: synchronized source recoil/mechanics, unchanged locomotion, world-space bone ejection/reset, pooled casings, random flashes" if failures.is_empty() else "SHOOTING_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
