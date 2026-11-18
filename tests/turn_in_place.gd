extends SceneTree
const Layer=preload("res://scripts/lower_body_turn.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.set_process(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;var m=p.motion;var sk: Skeleton3D=m.body_skeleton
	p.free_orbit_enabled=false
	p.set_process(false);p.set_physics_process(false);m.set_process(false)
	p.set_process_unhandled_input(false)
	var clip: Animation=m.mixer.get_animation(&"turn_in_place_left")
	check(clip!=null and clip.loop_mode==Animation.LOOP_NONE and is_equal_approx(clip.length,1),"Export is the authored 1-31 frame, one-second non-looping turn")
	var layer=Layer.new();layer.setup(sk,clip,30)
	print("TURN_SOURCE angle=",rad_to_deg(layer.total_rotation)," body_bones=",layer.bones.size()," protected_lower=",layer.protected_indices.size())
	check(layer.available() and absf(rad_to_deg(layer.total_rotation)-43.10507)<.02,"Source root yaw is retained as approximately 43 degrees left")
	if not layer.available():game.queue_free();await process_frame;quit(1);return
	check(layer.bones.size()>50 and sk.find_bone("DEF-spine") in layer.bones and sk.find_bone("DEF-foot.L") in layer.bones and sk.find_bone("DEF-foot.R") in layer.bones,"Mask includes pelvis, both legs, feet and their B-Bone segments")
	check(sk.find_bone("DEF-spine.003") in layer.bones and sk.find_bone("DEF-hand.R") in layer.bones and sk.find_bone("DEF-shoulder.L") in layer.bones,"The full turn includes the chest, shoulders and arms")
	check(sk.find_bone("RootMotion") not in layer.bones and sk.find_bone("DEF-spine.002") in layer.bones,"Root extraction remains separate while the upper abdomen joins the turn")
	check(sk.find_bone("DEF-spine.001") in layer.bones,"Pelvis torsion continues into the lower abdomen instead of stopping abruptly at the belt")
	m.set_aiming(false,0);m.blend_time=0;m.current="";m.play("idle");m.advance_motion(0)
	var poses: Array[Transform3D]=[]
	for bone in sk.get_bone_count():poses.append(sk.get_bone_pose(bone))
	layer.blend_time=0;check(layer.start(),"Whole-body turn starts over the base animation")
	layer.advance(.5);layer.apply()
	var changed := 0
	for bone in sk.get_bone_count():
		if bone in layer.bones:
			if not sk.get_bone_pose(bone).is_equal_approx(poses[bone]):changed+=1
		else:check(sk.get_bone_pose(bone).is_equal_approx(poses[bone]),"The turn does not reapply extracted root rotation")
	check(changed>10 and not sk.get_bone_pose(sk.find_bone("DEF-spine.003")).is_equal_approx(poses[sk.find_bone("DEF-spine.003")]),"The authored step also animates the upper torso")
	layer.restore()
	for bone in sk.get_bone_count():check(sk.get_bone_pose(bone).is_equal_approx(poses[bone]),"Restoring the layer prevents accumulated per-frame offsets")
	# Compare actual world-space feet/pelvis against the complete Blender export.
	# This catches root-space mistakes that would otherwise make planted feet slide.
	var source=load("res://assets/character/animations/player_turn_in_place_left.glb").instantiate();root.add_child(source)
	var original_yaw: float=p.global_rotation.y;source.global_transform=m.model.global_transform
	var source_skeleton: Skeleton3D=source.get_node("rig/Skeleton3D")
	var source_player: AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0]
	source_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;source_player.play(source_player.get_animation_list()[0],0);source_player.advance(0)
	var source_position_error := 0.0;var source_rotation_error := 0.0
	for at in [0.0,.25,.5,.75,1.0]:
		source_player.seek(at,true);layer.time=at;layer.weight=1;layer.apply();p.global_rotation.y=original_yaw+layer._yaw(at)-layer._yaw(0)
		for bone in layer.bones:
			var source_bone := source_skeleton.find_bone(sk.get_bone_name(bone))
			if source_bone<0:continue
			var actual := sk.global_transform*sk.get_bone_global_pose(bone)
			var expected := source_skeleton.global_transform*source_skeleton.get_bone_global_pose(source_bone)
			source_position_error=maxf(source_position_error,actual.origin.distance_to(expected.origin))
			source_rotation_error=maxf(source_rotation_error,actual.basis.orthonormalized().get_rotation_quaternion().angle_to(expected.basis.orthonormalized().get_rotation_quaternion()))
		layer.restore()
	p.global_rotation.y=original_yaw;source.queue_free()
	check(source_position_error<.001 and source_rotation_error<.003,"The full body reproduces the Blender export before aim/look layers")
	# Playback speed changes timing and root rotation together, without a yaw warp.
	var totals: Array[float]=[]
	for speed in [1.0,2.0]:
		var sample=Layer.new();sample.setup(sk,clip,30);sample.blend_time=.12;sample.start()
		var total := 0.0
		for frame in roundi(60/speed):sample.advance(1.0/60,speed);total+=sample.rotation_delta
		check(not sample.active and absf(total-sample.total_rotation)<.00001,"Playback consumes the exact source root angle at speed "+str(speed))
		totals.append(total)
		sample.advance(.12,speed);check(is_zero_approx(sample.weight),"Natural completion blends back to the advancing idle pose")
	var blended=Layer.new();blended.setup(sk,clip,30);blended.start();blended.advance(.06)
	check(absf(blended.weight-.5)<.0001 and blended.rotation_delta>0,"Blend smooths the pose without slowing the authored root start")
	blended.cancel();blended.advance(.06);check(is_zero_approx(blended.rotation_delta) and is_zero_approx(blended.weight),"Cancellation blends out and stops root rotation immediately")
	# Controller: settle onto real ground, then cross the existing torso threshold.
	p.enabled=true;p.controls_blocked=false;p.position=Vector3(0,.05,6.2);p.velocity=Vector3.ZERO;p.rotation=Vector3.ZERO;p.reset_camera_follow()
	p.camera_translation_lag=0;p.camera_rotation_lag=0;p.camera_collision_enabled=false;p.aim_pose_blend_time=0;p.aim_camera_transition_time=0
	for frame in 24:await physics_frame;p._physics_process(1.0/60)
	check(p.is_on_floor(),"Controller fixture is grounded")
	p.look_yaw=deg_to_rad(minf(p.body_turn_threshold_degrees,p.torso_yaw_limit_degrees)*.8);p._update_body_orientation(Vector2.ZERO,1.0/60)
	check(not m.turn_in_place.active and is_zero_approx(p.rotation.y),"Looking within the threshold keeps the legs idle")
	m.set_aiming(true,0);m.advance_motion(0)
	var hand := sk.find_bone("DEF-hand.R")
	var hand_forward := sk.get_bone_global_pose(hand).basis.inverse()*Vector3.BACK
	m.set_aiming(false,0);m.advance_motion(0)
	p.look_yaw=deg_to_rad(60);p.pitch=.15;p.update_camera_follow(0)
	# Controller turns now run only in exploration. Exercise the aim pose layer
	# directly below to keep validating its independent composition with a turn.
	var review := Camera3D.new();game.add_child(review);review.global_position=p.global_position+Vector3(-.8,1.25,-2.4);review.look_at(p.global_position+Vector3(0,.95,0));review.fov=45
	game.psx_renderer.set_active_camera(review);game.psx_renderer.ambient_light_color=Color(.6,.6,.6);game.psx_renderer.fog_start=30;game.psx_renderer.fog_end=40
	var sheet := Image.create(1600,240,false,Image.FORMAT_RGBA8);var captured := 0
	var position_before: Vector3=p.global_position;var hand_error := 0.0
	var root_delta_sum := 0.0;var maximum_left_lift := -INF;var maximum_right_lift := -INF
	var layered_position_error := 0.0;var layered_rotation_error := 0.0
	var aimed_torso_motion := 0.0;var aimed_torso_roll := 0.0
	for frame in 78:
		if frame==22:p.look_yaw=deg_to_rad(70);p.pitch=-.2;p.update_camera_follow(0)
		if frame==40:p.look_yaw=deg_to_rad(65);p.pitch=.28;p.update_camera_follow(0)
		await physics_frame;p._physics_process(1.0/60)
		m._restore_pose_layers();m.set_aiming(true,0);m._apply_pose_layers(0)
		m.apply_look(-p.camera.global_basis.z,deg_to_rad(p.torso_yaw_limit_degrees),deg_to_rad(p.torso_pitch_limit_degrees),true)
		root_delta_sum+=m.turn_in_place.rotation_delta
		if is_equal_approx(m.turn_in_place.weight,1.0):
			# Read the final skeleton after aim AND mouse look, not just the layer.
			var turning=m.turn_in_place
			var sample := clampf(turning.time*turning.fps,0,turning.frames.size()-1)
			var first := floori(sample);var last := mini(first+1,turning.frames.size()-1)
			for index in turning.protected_indices:
				var expected: Transform3D=turning.frames[first][index].interpolate_with(turning.frames[last][index],sample-first)
				var actual: Transform3D=sk.get_bone_pose(turning.bones[index])
				layered_position_error=maxf(layered_position_error,actual.origin.distance_to(expected.origin))
				layered_rotation_error=maxf(layered_rotation_error,actual.basis.orthonormalized().get_rotation_quaternion().angle_to(expected.basis.orthonormalized().get_rotation_quaternion()))
			var chest_bone := sk.find_bone("DEF-spine.003")
			var animated_torso := sk.get_bone_global_pose(chest_bone)
			var view: Vector3=-p.camera.global_basis.z
			# Compare against the old translation-only aim on the same turn frame.
			# This proves the authored upper motion survives both aim AND look.
			m._restore_pose_layers();turning.apply();m.aim_pose.capture();m.aim_pose.advance(0)
			turning.enforce();m.upper_body.capture()
			m.upper_body.apply(view,deg_to_rad(p.torso_yaw_limit_degrees),deg_to_rad(p.torso_pitch_limit_degrees),true)
			turning.enforce()
			var old_torso := sk.get_bone_global_pose(chest_bone)
			aimed_torso_motion=maxf(aimed_torso_motion,animated_torso.origin.distance_to(old_torso.origin))
			aimed_torso_roll=maxf(aimed_torso_roll,animated_torso.basis.get_rotation_quaternion().angle_to(old_torso.basis.get_rotation_quaternion()))
			m._restore_pose_layers();m._apply_pose_layers(0);m.apply_look(view,deg_to_rad(p.torso_yaw_limit_degrees),deg_to_rad(p.torso_pitch_limit_degrees),true)
		if frame==0:check(m.turn_in_place.active and m.current=="idle","Torso catch-up starts the whole-body layer without restarting locomotion")
		if frame>=10 and frame<=55:
			var actual_forward := (sk.global_basis*sk.get_bone_global_pose(hand).basis*hand_forward).normalized()
			var target_forward: Vector3=(sk.global_basis*(Quaternion(Vector3.UP,m.upper_body.yaw)*Quaternion(Vector3.RIGHT,m.upper_body.pitch)*Vector3.BACK)).normalized()
			hand_error=maxf(hand_error,actual_forward.angle_to(target_forward))
		if p.footsteps.feet.size()==2:
			maximum_left_lift=maxf(maximum_left_lift,p.footsteps.feet[0].height)
			maximum_right_lift=maxf(maximum_right_lift,p.footsteps.feet[1].height)
		if frame in [0,14,29,44,59]:
			game.psx_renderer._process(0);await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image();sheet.blit_rect(image,Rect2i(0,0,320,240),Vector2i(captured*320,0));captured+=1
	Input.action_release("aim")
	sheet.save_png("res://docs/turn-in-place-poses.png");game.psx_renderer.set_active_camera(p.camera)
	check(absf(p.rotation.y-m.turn_in_place.total_rotation)<.001 and absf(root_delta_sum-m.turn_in_place.total_rotation)<.001,"Actual character yaw follows the authored angular root motion exactly")
	check(Vector2(p.global_position.x-position_before.x,p.global_position.z-position_before.z).length()<.0001,"Turning in place introduces no horizontal character displacement")
	check(hand_error<.003,"Aim yaw and pitch stay on the mouse target while authored torso motion and roll remain")
	check(aimed_torso_motion>.0001 or aimed_torso_roll>.001,"Authored torso motion visibly survives aim/look instead of remaining translation-only")
	check(layered_position_error<.00001 and layered_rotation_error<.001,"The final pelvis, abdomen, legs and all B-bone segments retain the full authored turn after aim and look, with no compensation")
	check(not m.turn_in_place.active and m.turn_in_place.weight<.0001 and not p._body_turning,"One completed step settles without restarting below the torso threshold")
	# Walking interrupts the turn, so directional locomotion remains responsive.
	p.rotation.y=0;p.look_yaw=deg_to_rad(60);p.velocity=Vector3.ZERO;p._update_body_orientation(Vector2.ZERO,1.0/60)
	check(m.turn_in_place.active,"The turn can be triggered again after a completed cycle")
	p._update_body_orientation(Vector2.UP,1.0/60);check(not m.turn_in_place.active,"Movement cancels the turn instead of blocking locomotion")
	m.advance_motion(.2);p.rotation.y=0;p.look_yaw=deg_to_rad(60);p.velocity=Vector3.ZERO;p._update_body_orientation(Vector2.ZERO,1.0/60)
	p.look_yaw=-.2;p._update_body_orientation(Vector2.ZERO,1.0/60);check(not m.turn_in_place.active,"Reversing mouse yaw cancels a left turn cleanly")
	m.advance_motion(.2);p.rotation.y=0;p.look_yaw=deg_to_rad(60);p.velocity=Vector3.ZERO;p.controls_blocked=true;p._body_turning=false
	p._update_body_orientation(Vector2.ZERO,1.0/60);check(not m.turn_in_place.active,"Blocked controls do not start a new turn")
	p.controls_blocked=false;p.rotation.y=0;p.look_yaw=deg_to_rad(60);p.velocity=Vector3.ZERO;p._update_body_orientation(Vector2.ZERO,1.0/60);p.reset_camera_follow()
	check(not m.turn_in_place.active,"Camera/teleport reset cancels obsolete angular root motion")
	game.psx_renderer.ambient_light_color=Color(.55,.55,.55);game.psx_renderer._process(0)
	check(game.psx_renderer.native_geometry.get_statistics().batches==1,"The lower animation keeps the same native PSX draw batch")
	FileAccess.open("res://docs/turn-in-place-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"source_angle_degrees":rad_to_deg(layer.total_rotation),"body_bones":layer.bones.size(),"protected_lower_bones":layer.protected_indices.size(),"source_position_error_m":source_position_error,"source_rotation_error_degrees":rad_to_deg(source_rotation_error),"final_lower_position_error_m":layered_position_error,"final_lower_rotation_error_degrees":rad_to_deg(layered_rotation_error),"aim_direction_error_degrees":rad_to_deg(hand_error),"aimed_torso_motion_m":aimed_torso_motion,"aimed_torso_roll_degrees":rad_to_deg(aimed_torso_roll),"foot_lift_m":[maximum_left_lift,maximum_right_lift],"root_angles":totals},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free();await process_frame
	print("TURN_IN_PLACE_OK: original whole-body turn, exact root and lower pose, animated torso under aim, mouse yaw/pitch, blending, interrupts and one PSX batch" if failures.is_empty() else "TURN_IN_PLACE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
