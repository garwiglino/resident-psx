extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game: Node3D=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p: Node3D=game.player;var m: Node3D=p.motion;var sk: Skeleton3D=m.body_skeleton
	p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false);m.set_process(false);p.enabled=true;p.controls_blocked=false
	var upper := {}
	for entry in m.aim_pose.entries:upper[entry.bone]=true
	var samples: Array=[]
	for clip in ["idle","walk","strafe_left"]:
		m._restore_pose_layers();m.aim_pose.reload_time=-1;m.set_aiming(false,0);m.blend_time=0;m.current="";m.play(clip);m.advance_motion(.4)
		p.ammo=2;p.reserve=20;p.reload_pose_return_time=.24
		check(p.reload_weapon(),"Reload starts during "+clip)
		var length: float=m.get_reload_duration();var phase: float=m.mixer.current_animation_position
		p.weapon_inventory.advance(length);m.advance_motion(length)
		check(p.ammo==12 and p.reserve==10 and p.weapon_inventory.action==p.WeaponInventory.Action.READY,"Ammo is available at the original authored completion, before the visual return")
		check(is_equal_approx(m.aim_pose.reload_time,length),"The authored last reload frame stays fully present")
		check(is_equal_approx(m.weapon.reload_return_blend_time,.24),"Pistol mechanical return uses the player's blend setting")
		var middle_gap := 0.0;var min_stride := INF
		for tick in 32:
			var dt := 1.0/120;var displacement: Vector3=m.advance_motion(dt)
			if clip!="idle":min_stride=minf(min_stride,displacement.length()/dt)
			var posed := {}
			for bone in sk.get_bone_count():posed[bone]=sk.get_bone_pose(bone)
			var hand := sk.find_bone("DEF-hand.L");var final_hand: Vector3=sk.get_bone_global_pose(hand).origin
			m._restore_pose_layers()
			var gap: float=sk.get_bone_global_pose(hand).origin.distance_to(final_hand)
			for bone in sk.get_bone_count():
				if not upper.has(bone):check(sk.get_bone_pose(bone).is_equal_approx(posed[bone]),"Return blend preserves pelvis, legs and root for "+clip)
			if tick==12:
				middle_gap=gap;check(middle_gap>.001 and m.aim_pose.reload_time>=0,"The arm still blends at 0.1 s instead of snapping back to "+clip)
			if tick==31:check(gap<.00001 and m.aim_pose.reload_time<0,"Return completes exactly onto the advancing "+clip+" pose")
			m._apply_pose_layers(0)
		var base_clip: Animation=m.mixer.get_animation(clip)
		var expected: float=phase+length+32.0/120
		if base_clip.loop_mode==Animation.LOOP_LINEAR and base_clip.length>0:expected=fposmod(expected,base_clip.length)
		check(m.current==clip and absf(m.mixer.current_animation_position-expected)<.0001,"The destination animation keeps its phase throughout the return")
		if clip!="idle":check(min_stride>1.4,"Root motion retains its authored stride throughout the upper-body blend")
		samples.append({"clip":clip,"middle_hand_gap_m":middle_gap,"minimum_stride_m_s":min_stride if clip!="idle" else 0})
	# Completion unlocks shooting immediately even while the arm is returning.
	p.ammo=2;p.reserve=20;check(p.reload_weapon(),"A second reload can start normally")
	p.weapon_inventory.advance(m.get_reload_duration()+.05);m.advance_motion(m.get_reload_duration()+.05)
	check(m.aim_pose.reload_time>=0 and p.shoot(),"Visual return never blocks a shot after ammo transfer")
	var result := {"ok":failures.is_empty(),"errors":failures,"samples":samples}
	FileAccess.open("res://docs/reload-return-blend-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	game.queue_free();await process_frame;await process_frame
	print("RELOAD_RETURN_BLEND_OK " if failures.is_empty() else "RELOAD_RETURN_BLEND_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
