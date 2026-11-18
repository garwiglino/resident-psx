extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={"frames":[]}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.position=Vector3(0,.05,4);p.rotation=Vector3.ZERO;p.reset_camera_follow()
	await create_timer(.1).timeout
	var m=p.motion;var w=m.weapon;var magazines=w.magazines
	var sk: Skeleton3D=m.body_skeleton
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/animations/player_pistol_reload.json"))
	check(metadata.source.ends_with("cop_shoot_reload_bezier.blend"),"Reload uses the user's updated Bezier source")
	check(absf(m.get_reload_duration()-34.0/24)<.00001,"Player reload keeps its 1..35 timing at 24 fps")
	check(absf(w.mixer.get_animation("pistol_reload").length-27.0/24)<.00001,"Gun reload keeps its own 1..28 timing")
	var source=load("res://assets/character/animations/player_pistol_reload.glb").instantiate();root.add_child(source)
	var source_sk: Skeleton3D=source.get_node("rig/Skeleton3D")
	var source_player: AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0]
	source_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	source_player.play("player_pistol_reload",0);source_player.advance(0)
	var baseline_model=load("res://assets/character/cop_player.glb").instantiate();root.add_child(baseline_model)
	for imported in baseline_model.find_children("*","AnimationPlayer",true,false):imported.active=false
	var baseline := AnimationPlayer.new();baseline_model.add_child(baseline);baseline.root_node=NodePath("..")
	baseline.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;baseline.root_motion_track=m.mixer.root_motion_track
	var library := AnimationLibrary.new();library.add_animation("strafe_left",m.mixer.get_animation("strafe_left"));baseline.add_animation_library("",library)
	baseline.play("strafe_left",0);baseline.advance(0);baseline.advance(.4)
	var base_sk: Skeleton3D=baseline_model.get_node("rig/Skeleton3D")
	var upper: Array[int]=[]
	for entry in m.aim_pose.entries:upper.append(entry.bone)
	m.current="";m.blend_time=0;m.set_aiming(false,0);m.play("strafe_left");m.advance_motion(.4)
	p.ammo=2;p.reserve=20
	var entries_before: int=game.psx_renderer.entries.size()
	check(p.reload_weapon(),"Loaded partial magazine starts reload")
	check(m.current=="strafe_left" and m.aim_pose.reload_time==0 and w.reload_time==0,"Both reload animations start together without replacing locomotion")
	var drop_start := Vector3.ZERO;var drop_after := Vector3.ZERO
	for frame in 35:
		if frame>0:
			p.weapon_inventory.advance(1.0/24);m.advance_motion(1.0/24);baseline.advance(1.0/24)
		p._apply_upper_body_look()
		for bone in sk.get_bone_count():
			if bone not in upper:check(sk.get_bone_pose(bone).is_equal_approx(base_sk.get_bone_pose(bone)),"Reload preserves pelvis, legs and root pose: "+String(sk.get_bone_name(bone)))
		if frame<5:check(magazines.phase==magazines.Phase.IN_GUN and not magazines.held.visible,"Magazine remains seated before player frame 6")
		if frame==5:
			check(magazines.phase==magazines.Phase.IN_HAND and magazines.held.visible and magazines.proxy>=0,"Frame 6 drops the original bone and reveals the left-hand copy")
			var drop: Dictionary=magazines.drops[magazines.proxy]
			check(drop.body is RigidBody3D and not drop.body.freeze,"The old magazine is driven by real 3D rigid-body physics")
			drop_start=drop.body.global_position
			for tick in 18:await physics_frame;p._apply_upper_body_look()
			drop_after=drop.body.global_position
			check(drop_after.y<drop_start.y-.1,"Gravity makes the magazine fall independently of the animation")
			var held_relative: Transform3D=(sk.global_transform*sk.get_bone_global_pose(magazines.hand)).affine_inverse()*magazines.held.global_transform
			check(held_relative.is_equal_approx(magazines.hand_mount),"Fresh magazine keeps the calibrated left-hand grip")
			var before: Vector3=p.position;p.position.x+=.3;p._apply_upper_body_look()
			var old_world: Transform3D=w.skeleton.global_transform*w.skeleton.get_bone_global_pose(magazines.bone)
			check(old_world.origin.distance_to(drop.body.global_position)<.0001,"Original b_mag bone follows the falling world body when the player moves")
			p.position=before;p._apply_upper_body_look()
		if frame==16:
			check(magazines.phase==magazines.Phase.INSERTED and not magazines.held.visible and magazines.proxy<0,"Frame 17 hides the hand copy and returns the magazine to the pistol")
			check(w.skeleton.get_bone_pose(magazines.bone).is_equal_approx(magazines.home_pose),"Inserted magazine restores its initial pistol-local pose")
			var from_hand: Transform3D=sk.global_transform*sk.get_bone_global_pose(magazines.hand)*magazines.hand_mount
			var in_gun: Transform3D=w.skeleton.global_transform*w.skeleton.get_bone_global_pose(magazines.bone)
			check(from_hand.origin.distance_to(in_gun.origin)<.001,"Calibrated hand magazine meets the pistol slot at player frame 17")
			check(from_hand.basis.get_rotation_quaternion().angle_to(in_gun.basis.get_rotation_quaternion())<.001,"Left-hand magazine meets the original slot orientation without an insertion twist")
			check(magazines.drops[0].mesh.visible,"Old magazine continues falling after the new one is inserted")
		if frame in [5,16,23,34]:
			source_player.seek(frame/24.0,true)
			var pelvis := sk.get_bone_global_pose(sk.find_bone("DEF-spine"));pelvis.basis=Basis.IDENTITY
			var original := source_sk.get_bone_global_pose(source_sk.find_bone("DEF-spine"));original.basis=Basis.IDENTITY
			var anchor := pelvis*original.affine_inverse()
			var error := 0.0
			for entry in m.aim_pose.entries:
				var expected := anchor*source_sk.get_bone_global_pose(source_sk.find_bone(sk.get_bone_name(entry.bone)))
				error=maxf(error,sk.get_bone_global_pose(entry.bone).origin.distance_to(expected.origin))
			check(error<.001,"Reload upper pose reproduces the exported Blender key timing")
			report.frames.append({"player_frame":frame+1,"time":frame/24.0,"phase":magazines.phase,"source_position_error_m":error})
		if frame<34:check(p.ammo==2,"Reload does not grant rounds before its authored completion")
	check(p.ammo==12 and p.reserve==10,"Ammo transfer completes once, at the authored reload end")
	check(magazines.drop_count==1 and magazines.insert_count==1,"Each magazine event executes exactly once")
	check(game.psx_renderer.entries.size()==entries_before,"Reload reuses pre-registered magazine meshes")
	var drop: Dictionary=magazines.drops[0]
	for tick in 120:await physics_frame
	var bounds: AABB=drop.mesh.mesh.get_aabb()
	var minimum := INF
	for corner in 8:minimum=minf(minimum,(drop.mesh.global_transform*bounds.get_endpoint(corner)).y)
	check(minimum>-.025 and minimum<.06,"Dropped magazine collides with the real floor instead of passing through it")
	check(not drop.body.freeze,"Magazine settles through physics rather than a scripted freeze")
	p.ammo=1;p.reserve=5
	check(p.reload_weapon(),"Second reload starts normally")
	m.advance_motion(0,5.0/24);p._apply_upper_body_look()
	check(magazines.held.visible,"Cancellation test reached the left-hand phase")
	p.take_damage(p.health)
	check(not magazines.held.visible and magazines.phase==magazines.Phase.IDLE,"Death cancels the hand copy and bone override")
	p.weapon_inventory.advance(5);m.advance_motion(0,1);p._apply_upper_body_look()
	check(p.ammo==1 and p.reserve==5,"Cancelled reload cannot transfer ammo later")
	report.gravity_drop_m=drop_start.y-drop_after.y;report.floor_minimum_y=minimum;report.pool_size=magazines.drops.size();report.failures=failures
	FileAccess.open("res://docs/reload-magazine-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	source.queue_free();baseline_model.queue_free()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.08).timeout
	print("RELOAD_MAGAZINE_OK: updated clips, common clock, frame-6 rigid-body drop/left grip, frame-17 insertion, ground collision, unchanged locomotion and safe completion/cancellation" if failures.is_empty() else "RELOAD_MAGAZINE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
