extends SceneTree
const Heading=preload("res://scripts/run_heading.gd")
var failures: Array[String]=[]
var players: Array=[]
var maximum_leg_error := 0.0
var maximum_hand_angle := 0.0
var samples := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func drive(count: int) -> void:
	for tick in count:
		for p in players:p._physics_process(1.0/60);p._process(1.0/60)
func bone_frame(p: Node,name: String) -> Transform3D:
	var sk: Skeleton3D=p.motion.body_skeleton
	return p.visual.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(sk.find_bone(name))
func compare() -> void:
	var a=players[0];var b=players[1]
	var sa: Skeleton3D=a.motion.body_skeleton;var sb: Skeleton3D=b.motion.body_skeleton
	for bone in sa.get_bone_count():
		var name := String(sa.get_bone_name(bone)).trim_prefix("SEG-")
		var lower := name=="DEF-spine" or name.begins_with("DEF-spine-")
		for prefix in ["DEF-pelvis.","DEF-thigh.","DEF-shin.","DEF-foot.","DEF-toe."]:
			lower=lower or name.begins_with(prefix)
		if not lower:continue
		var original := sa.get_bone_pose(bone);var actual := sb.get_bone_pose(bone)
		maximum_leg_error=maxf(maximum_leg_error,original.origin.distance_to(actual.origin))
		check(original.is_equal_approx(actual),"Lower-body source pose stays intact: "+String(sa.get_bone_name(bone)))
	var rotation := Transform3D(Basis(Vector3.UP,b.motion.run_heading.yaw),Vector3.ZERO)
	check((rotation*bone_frame(a,"DEF-spine")).is_equal_approx(bone_frame(b,"DEF-spine")),"Pelvis receives the whole rigid heading")
	for name in ["DEF-spine.003","DEF-hand.R","DEF-hand.L"]:
		var angle := rad_to_deg(bone_frame(a,name).basis.get_rotation_quaternion().angle_to(bone_frame(b,name).basis.get_rotation_quaternion()))
		maximum_hand_angle=maxf(maximum_hand_angle,angle)
		check(angle<.1,"Torso and hands retain the original mouse-facing rotation: "+name)
	check(a.velocity.distance_to(b.velocity)<.001,"Root-motion velocity is independent of visual diagonal steering")
	check(absf(a.motion.mixer.current_animation_position-b.motion.mixer.current_animation_position)<.00001,"Diagonal steering never restarts or retimes the clip")
	var attachment := sb.global_transform*sb.get_bone_global_pose(sb.find_bone("DEF-hand.R"))
	var mount: Transform3D=attachment.affine_inverse()*b.motion.weapon.global_transform
	var expected: Transform3D=b.motion.weapon_socket.transform
	check(mount.origin.distance_to(expected.origin)<.00001 and rad_to_deg(mount.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()))<.1,"Pistol stays fixed in the hand")
	samples+=1
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	for action in ["forward","back","left","right","sprint","aim","fire","reload","flashlight","shoulder","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	var floor := StaticBody3D.new();var collider := CollisionShape3D.new();var box := BoxShape3D.new()
	box.size=Vector3(1000,1,1000);collider.shape=box;floor.add_child(collider);root.add_child(floor);floor.position.y=-.5
	for index in 2:
		var p=load("res://scenes/player.tscn").instantiate();root.add_child(p);p.set_process(false);p.set_physics_process(false)
		p.free_orbit_enabled=false
		p.enabled=true;p.position.x=index*6;p.camera_collision_enabled=false;p.camera_translation_lag=0;p.camera_rotation_lag=0
		p.torso_yaw_limit_degrees=25;p.camera_max_rotation_lag_degrees=1;p.aim_pose_blend_time=0
		p.pitch=.2;p.reset_camera_follow();p.run_direction_enabled=index==1;players.append(p)
	await physics_frame;await physics_frame
	Input.action_press("forward");Input.action_press("sprint");drive(20);compare()
	check(players[1].motion.run_heading.yaw==0,"Forward jog stays unchanged")
	Input.action_press("left");drive(1);compare()
	var first: float=players[1].motion.run_heading.yaw
	check(first>0 and first<deg_to_rad(20),"Diagonal starts progressively")
	drive(70);compare()
	check(absf(players[1].motion.run_heading.yaw-deg_to_rad(45))<.001,"Forward-left reaches +45 degrees")
	Input.action_release("left");Input.action_press("right");drive(1);compare()
	check(players[1].motion.run_heading.yaw>0,"Reversing direction does not snap across ninety degrees")
	drive(70);compare();check(absf(players[1].motion.run_heading.yaw+deg_to_rad(45))<.001,"Forward-right reaches -45 degrees")
	# No drift or grip deformation from repeated render updates.
	var before := bone_frame(players[1],"DEF-hand.R")
	for frame in 120:players[1]._apply_upper_body_look()
	check(before.is_equal_approx(bone_frame(players[1],"DEF-hand.R")),"Render updates never accumulate steering compensation")
	# Aim replaces the run with the original directional walk while legs return smoothly.
	Input.action_press("aim");drive(1);compare()
	check(players[1].aiming and players[1].motion.current=="forward_right","Aim preserves the authored directional walk")
	drive(70);compare();check(absf(players[1].motion.run_heading.yaw)<.001,"Aim returns the lower body to its normal heading")
	Input.action_release("aim");drive(70);compare()
	Input.action_release("sprint");drive(1);compare()
	check(players[1].motion.current=="forward_right" and absf(players[1].motion.run_heading.yaw)>.1,"Course-to-walk retains a smooth heading return")
	drive(70);compare();check(absf(players[1].motion.run_heading.yaw)<.001,"Walking settles back to its authored orientation")
	Input.action_press("sprint");drive(70);compare();Input.action_release("forward");Input.action_release("right");drive(70);compare()
	check(players[1].motion.current=="idle" and absf(players[1].motion.run_heading.yaw)<.001,"Stopping returns smoothly to idle")
	Input.action_press("left");drive(70);compare();check(players[1].motion.current=="strafe_left","Shift plus pure side movement keeps the original strafe")
	Input.action_press("forward");drive(70);compare()
	players[1].run_direction_enabled=false;drive(70);compare();check(absf(players[1].motion.run_heading.yaw)<.001,"Inspector toggle restores ordinary running")
	players[1].run_direction_enabled=true;players[1].run_direction_max_yaw_degrees=20;drive(70);compare()
	check(absf(players[1].motion.run_heading.yaw-deg_to_rad(20))<.001,"Inspector angle limit is respected")
	for p in players:p.torso_follow_enabled=false
	drive(30);compare()
	check(absf(players[1].motion.run_heading.yaw-deg_to_rad(20))<.001,"Disabling mouse torso follow still keeps the procedural turn below the torso")
	# Pose restoration also removes the temporary node rotation for cinematic actors.
	players[1].motion._restore_pose_layers()
	check(players[1].motion.basis.orthonormalized().is_equal_approx(players[1].motion.run_heading.base_rotation),"Cinematic pose ownership removes visual steering")
	players[1].motion._apply_pose_layers(0);players[1]._apply_upper_body_look()
	players[1].reset_camera_follow();check(players[1].motion.run_heading.yaw==0,"Camera/actor reset clears obsolete steering")
	for action in ["forward","left","right","sprint","aim"]:Input.action_release(action)
	var node := Node3D.new();root.add_child(node);node.scale=Vector3.ONE*1.7
	var h := Heading.new();h.setup(node)
	for tick in 12:h.advance(deg_to_rad(45),1.0/60,.1)
	var at60 := h.yaw;h.reset()
	for tick in 24:h.advance(deg_to_rad(45),1.0/120,.1)
	check(absf(at60-h.yaw)<.000001,"Smoothing is independent of physics frame rate")
	for tick in 200:h.apply();h.restore()
	check(node.scale.is_equal_approx(Vector3.ONE*1.7),"Heading preserves the authored model scale")
	node.queue_free()
	floor.queue_free()
	for p in players:
		for audio in p.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.15).timeout
	for p in players:p.queue_free()
	await process_frame;await process_frame;await create_timer(.15).timeout
	var result := {"samples":samples,"maximum_leg_position_error_m":maximum_leg_error,"maximum_upper_rotation_error_degrees":maximum_hand_angle,"failures":failures}
	FileAccess.open("res://docs/run-direction-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("RUN_DIRECTION_OK " if failures.is_empty() else "RUN_DIRECTION_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
