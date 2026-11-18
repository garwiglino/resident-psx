extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player
	p.free_orbit_enabled=false
	report.initial_root_motion={"enabled":p.root_motion_enabled,"scale":p.root_motion_scale,"playback_speed":p.root_motion_playback_speed}
	p.set_process(false)
	p.set_physics_process(false)
	p.enabled=true
	p.camera_rotation_lag=0
	p.camera_translation_lag=0
	p.camera_collision_enabled=false
	p.position=Vector3(0,.02,6)
	p.rotation=Vector3.ZERO
	p.pitch=0
	p.reset_camera_follow()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var m=p.motion
	var sk: Skeleton3D=m.model.get_node("rig/Skeleton3D")
	check(m.upper_body.stages.size()==3,"Three distributed spine pivots available")
	# Test the real mouse handler, rather than setting the resulting pose directly.
	var mouse := InputEventMouseMotion.new()
	mouse.relative=Vector2(-20/p.mouse_sensitivity,-15/p.mouse_sensitivity)
	# The headless display cannot capture an OS cursor; exercise the same mouse mapping.
	if DisplayServer.get_name()=="headless":p._apply_mouse_motion(mouse.relative)
	else:p._unhandled_input(mouse)
	check(absf(rad_to_deg(p.look_yaw)-20)<.001,"Mouse yaw updates the view target")
	check(absf(rad_to_deg(p.pitch)-15)<.001,"Mouse pitch updates the view target")
	p._update_body_orientation(Vector2.ZERO,1.0/60)
	check(absf(p.global_rotation.y)<.00001,"Lower body stays still below the yaw threshold")
	p.update_camera_follow(1.0/60)
	m.advance_motion(0)
	var head := sk.find_bone("DEF-spine.006")
	var hand := sk.find_bone("DEF-hand.R")
	var before_head := sk.get_bone_global_pose(head)
	var before_muzzle: Vector3=m.weapon.get_muzzle_transform().origin
	m.hand_attachment.on_skeleton_update()
	var mount_before: Transform3D=(sk.global_transform*sk.get_bone_global_pose(hand)).affine_inverse()*m.weapon.global_transform
	var lower_poses: Dictionary={}
	for bone in sk.get_bone_count():
		var name := sk.get_bone_name(bone)
		if name.begins_with("DEF-thigh") or name.begins_with("DEF-shin") or name.begins_with("DEF-foot") or name.begins_with("DEF-toe") or name.begins_with("DEF-pelvis") or name=="DEF-spine":lower_poses[bone]=sk.get_bone_pose(bone)
	p._apply_upper_body_look()
	var after_head := sk.get_bone_global_pose(head)
	var actual := (after_head.basis*before_head.basis.inverse()).orthonormalized().get_rotation_quaternion()
	var expected := Quaternion(Vector3.UP,deg_to_rad(20))*Quaternion(Vector3.RIGHT,deg_to_rad(-15))
	check(actual.angle_to(expected)<.003,"Upper body follows camera yaw and pitch with the correct signs")
	for bone in lower_poses:check(sk.get_bone_pose(bone).is_equal_approx(lower_poses[bone]),"Look layer does not alter lower-body animation: "+String(sk.get_bone_name(bone)))
	var mount_after: Transform3D=(sk.global_transform*sk.get_bone_global_pose(hand)).affine_inverse()*m.weapon.global_transform
	check(mount_after.is_equal_approx(mount_before),"Weapon stays attached to the right hand while looking")
	check(m.weapon.get_muzzle_transform().origin.distance_to(before_muzzle)>.02,"Weapon muzzle follows the upper body")
	# Reapplying during render frames must not accumulate additional rotation.
	for frame in 120:p._apply_upper_body_look()
	check(sk.get_bone_global_pose(head).is_equal_approx(after_head),"Repeated render updates do not accumulate twist")
	report.upper_body_error_degrees=rad_to_deg(actual.angle_to(expected))
	# The lower body catches up smoothly only once the idle threshold is crossed.
	p.look_yaw=deg_to_rad(80)
	p.pitch=0
	var first_step := 0.0
	for frame in 90:
		p._update_body_orientation(Vector2.ZERO,1.0/60)
		if frame==0:first_step=p.global_rotation.y
		p.update_camera_follow(1.0/60)
		m.advance_motion(0)
		p._apply_upper_body_look()
		check(absf(m.upper_body.yaw)<=deg_to_rad(p.torso_yaw_limit_degrees)+.0001,"Torso twist remains within its limit")
	check(first_step>0 and first_step<deg_to_rad(10),"Lower-body turn starts progressively")
	var remaining: float=absf(wrapf(p.look_yaw-p.global_rotation.y,-PI,PI))
	check(remaining<=deg_to_rad(p.body_turn_recenter_degrees)+.002,"Lower body recentres the upper body")
	report.recenter_error_degrees=rad_to_deg(remaining)
	var settled: float=p.global_rotation.y
	for frame in 60:p._update_body_orientation(Vector2.ZERO,1.0/60)
	check(is_equal_approx(p.global_rotation.y,settled),"Idle hysteresis prevents continuous lower-body drift")
	# Follow the displayed camera, including its requested small rotation lag.
	m.advance_motion(p.turn_in_place_blend_time)
	p.rotation=Vector3.ZERO
	p.pitch=0
	p.reset_camera_follow()
	p.camera_rotation_lag=.05
	p.look_yaw=deg_to_rad(30)
	p.pitch=deg_to_rad(20)
	p.update_camera_follow(1.0/60)
	m.advance_motion(0)
	p._apply_upper_body_look()
	var local_view: Vector3=sk.global_basis.inverse()*(-p.camera.global_basis.z)
	var limit := deg_to_rad(float(p.torso_yaw_limit_degrees))
	check(absf(m.upper_body.yaw-clampf(atan2(local_view.x,local_view.z),-limit,limit))<.0001,"Upper body follows the delayed camera within the configured yaw limit")
	p.global_rotation.y=deg_to_rad(179)
	p.reset_camera_follow()
	p.look_yaw=deg_to_rad(-179)
	p._update_body_orientation(Vector2.ZERO,1.0/60)
	check(absf(wrapf(p.look_yaw-p.global_rotation.y,-PI,PI))<deg_to_rad(2.1),"Yaw wraparound takes the short path")
	# Root-motion travel follows camera-relative controls even during body recentering.
	p.position=Vector3(0,.02,6)
	p.rotation=Vector3.ZERO
	p.pitch=0
	p.reset_camera_follow()
	p.camera_rotation_lag=0
	p.look_yaw=PI/4
	p.root_motion_enabled=true
	p.root_motion_scale=1
	p.root_motion_playback_speed=1
	p.root_motion_steer_with_input=true
	Input.action_press("forward")
	var start: Vector3=p.position
	for frame in 12:
		await physics_frame
		p._physics_process(1.0/60)
		p._process(1.0/60)
	Input.action_release("forward")
	var movement: Vector3=p.position-start
	check(movement.x<-.02 and movement.z<-.02 and absf(movement.x-movement.z)<.003,"Movement follows camera yaw while the lower body turns")
	report.camera_relative_movement=str(movement)
	FileAccess.open("res://docs/look-follow-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"measurements":report,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	print("LOOK_FOLLOW_OK: mouse pitch/yaw, lower-body threshold, hysteresis, wraparound, camera lag, unchanged leg poses, weapon socket, root motion" if failures.is_empty() else "LOOK_FOLLOW_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
