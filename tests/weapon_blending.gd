extends SceneTree
var failures: Array[String]=[]
var measurements: Array=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func angle(a: Transform3D,b: Transform3D) -> float:
	return rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()))
func capture(sk: Skeleton3D,hand: int,bones: Array[int]) -> Array[Transform3D]:
	var result: Array[Transform3D]=[sk.get_bone_global_pose(hand)]
	var inverse := result[0].affine_inverse()
	for bone in bones:result.append(inverse*sk.get_bone_global_pose(bone))
	return result
func sample(m: Node,clip: String,time: float,hand: int,bones: Array[int]) -> Array:
	m.current="";m.blend_time=0;m.play(clip);m.advance_motion(time)
	var frames: Array=[]
	for frame in 31:
		frames.append(capture(m.body_skeleton,hand,bones))
		m.advance_motion(1.0/60)
	return frames
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	var p=game.player
	p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	await create_timer(.1).timeout
	var m=p.motion
	var sk: Skeleton3D=m.body_skeleton
	var original := "--original-grip-reference" in OS.get_cmdline_user_args()
	if original:
		var source=load("res://assets/character/cop_player.glb").instantiate()
		var source_skeleton: Skeleton3D=source.get_node("rig/Skeleton3D")
		for bone in sk.get_bone_count():sk.set_bone_rest(bone,source_skeleton.get_bone_rest(bone))
		m.mixer.clear_caches()
		source.free()
	for side in [".R",".L"]:
		var hand := sk.find_bone("DEF-hand"+side)
		var bones: Array[int]=[]
		for bone in sk.get_bone_count():
			var name := String(sk.get_bone_name(bone))
			if side in name and (name.begins_with("DEF-f_") or name.begins_with("DEF-thumb") or name.begins_with("DEF-palm")):bones.append(bone)
		check(not bones.is_empty(),"Exported grip bones exist on "+side)
		var incoming := sample(m,"idle",0,hand,bones)
		for clip in m.WALK_DIRECTIONS:
			for phase in 16:
				var time := phase*.25
				var outgoing := sample(m,clip,time,hand,bones)
				m.current="";m.blend_time=0;m.play(clip);m.advance_motion(time)
				m.blend_time=.5;m.play("idle")
				var hand_error := 0.0;var grip_angle := 0.0;var grip_position := 0.0
				var mount_error := 0.0
				for frame in 31:
					if frame>0:m.advance_motion(1.0/60)
					m.hand_attachment.on_skeleton_update()
					var actual := capture(sk,hand,bones)
					# Independent reference: both source poses continue advancing.
					var expected_hand: Transform3D=outgoing[frame][0].interpolate_with(incoming[frame][0],frame/30.0)
					hand_error=maxf(hand_error,angle(actual[0],expected_hand))
					for i in bones.size():
						var expected: Transform3D=outgoing[frame][i+1].interpolate_with(incoming[frame][i+1],frame/30.0)
						grip_angle=maxf(grip_angle,angle(actual[i+1],expected))
						grip_position=maxf(grip_position,actual[i+1].origin.distance_to(expected.origin))
					if side==".R":
						var relative: Transform3D=(sk.global_transform*actual[0]).affine_inverse()*m.weapon.global_transform
						mount_error=maxf(mount_error,relative.origin.distance_to(m.weapon_socket.position))
						check(angle(relative,m.weapon_socket.transform)<.1,"Pistol keeps its hand-relative orientation")
				check(hand_error<.2,"Hand takes the short rotation path: %s %s phase %.2f" % [side,clip,time])
				check(grip_angle<.2 and grip_position<.003,"Finger grip remains coherent during fade: %s %s phase %.2f" % [side,clip,time])
				check(mount_error<.00001,"Weapon mount stays fixed throughout the fade")
				measurements.append({"side":side,"clip":clip,"phase":time,"hand_error_degrees":hand_error,"grip_error_degrees":grip_angle,"grip_error_m":grip_position,"mount_error_m":mount_error})
	# Interrupt the problematic fade repeatedly and check the hand and grip.
	m.current="";m.blend_time=0;m.play("strafe_left");m.advance_motion(2)
	m.blend_time=.5
	var interruption_angle := 0.0;var interruption_position := 0.0
	var interruptions: Array=[]
	for next in ["idle","strafe_right","strafe_left","walk","idle","forward_left","strafe_left","idle"]:
		var before: Dictionary={}
		for bone in sk.get_bone_count():
			var name := String(sk.get_bone_name(bone))
			if name.begins_with("DEF-hand.") or name.begins_with("DEF-f_") or name.begins_with("DEF-thumb") or name.begins_with("DEF-palm"):before[bone]=sk.get_bone_pose(bone)
		m.play(next);m.advance_motion(0)
		var row := {"clip":next,"angle":0.0,"bone":"","hand_angle":0.0}
		for bone: int in before:
			var change := angle(before[bone],sk.get_bone_pose(bone))
			interruption_angle=maxf(interruption_angle,change)
			if change>row.angle:row.angle=change;row.bone=sk.get_bone_name(bone)
			if String(sk.get_bone_name(bone)).begins_with("DEF-hand"):row.hand_angle=maxf(row.hand_angle,change)
			interruption_position=maxf(interruption_position,before[bone].origin.distance_to(sk.get_bone_pose_position(bone)))
		interruptions.append(row)
		for frame in 6:m.advance_motion(1.0/60)
	check(interruption_angle<.5 and interruption_position<.001,"Interrupted blends retain the displayed grip without a rotation jump")
	var report_path := "res://docs/weapon-blending-before.json" if original else "res://docs/weapon-blending-validation.json"
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"measurements":measurements,"interruptions":interruptions,"interruption_angle_degrees":interruption_angle,"interruption_position_m":interruption_position,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free();await process_frame
	print("WEAPON_BLENDING_OK: both hands, eight directions, sixteen release phases, fixed grip, continuous interruptions" if failures.is_empty() else "WEAPON_BLENDING_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
