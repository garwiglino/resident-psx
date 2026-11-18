extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game: Node3D=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.set_process(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p: Node3D=game.player;var m: Node3D=p.motion;var sk: Skeleton3D=m.body_skeleton
	p.free_orbit_enabled=false
	p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false);m.set_process(false)
	p.enabled=true;p.controls_blocked=false;p.camera_collision_enabled=false;p.aim_pose_blend_time=0
	m.set_aiming(false,0);m.blend_time=0;m.current="";m.play("idle");m.advance_motion(0)
	var untouched := {}
	for bone in sk.get_bone_count():
		var name := String(sk.get_bone_name(bone)).trim_prefix("SEG-")
		if name in ["DEF-spine","RootMotion"] or name.begins_with("DEF-spine-"):untouched[bone]=sk.get_bone_pose(bone)
		for prefix in ["DEF-pelvis.","DEF-thigh.","DEF-shin.","DEF-foot.","DEF-toe."]:
			if name.begins_with(prefix):untouched[bone]=sk.get_bone_pose(bone)
	var hand := sk.find_bone("DEF-hand.R");var chest := sk.find_bone("DEF-spine.003")
	var direction: Vector3=sk.global_basis*(Basis(Vector3.UP,.45)*Basis(Vector3.RIGHT,-.3)*Vector3.BACK)
	m.apply_look(direction,1,1,true,&"DEF-spine.001")
	var old_chest := sk.get_bone_global_pose(chest);var old_hand := sk.get_bone_global_pose(hand)
	var grip: Transform3D=(sk.global_transform*old_hand).affine_inverse()*m.weapon.global_transform
	m.apply_look(direction,1,1,true,&"DEF-spine")
	var new_chest := sk.get_bone_global_pose(chest);var new_hand := sk.get_bone_global_pose(hand)
	check(m.upper_body.stages[0].pivot==sk.find_bone("DEF-spine"),"Lower torso pivot uses the actual pelvis anchor")
	var shift: float=new_chest.origin.distance_to(old_chest.origin)
	check(shift>.001,"Lowering the pivot changes the torso's yaw/pitch arc")
	check(new_hand.basis.get_rotation_quaternion().angle_to(old_hand.basis.get_rotation_quaternion())<.002,"The lower pivot preserves the complete hand aiming rotation")
	for bone in untouched:check(sk.get_bone_pose(bone).is_equal_approx(untouched[bone]),"Pivot selection leaves pelvis and legs authored: "+String(sk.get_bone_name(bone)))
	check(((sk.global_transform*new_hand).affine_inverse()*m.weapon.global_transform).is_equal_approx(grip),"Lower pivot keeps the pistol aligned with the hand")
	for frame in 80:m.apply_look(direction,1,1,true,&"DEF-spine")
	check(sk.get_bone_global_pose(chest).is_equal_approx(new_chest),"Render updates never accumulate pivot rotation")
	p.torso_pivot_bone="DEF-spine.001";p._apply_upper_body_look()
	check(m.upper_body.stages[0].pivot==sk.find_bone("DEF-spine.001"),"Inspector option can restore the previous pivot live")
	p.torso_pivot_bone="DEF-spine";p._apply_upper_body_look()
	check(m.upper_body.stages[0].pivot==sk.find_bone("DEF-spine"),"Inspector option returns to the lower pivot live")
	m.upper_body.restore();p.position=Vector3(0,.05,6.2);p.rotation=Vector3.ZERO;p.velocity=Vector3.ZERO;p.reset_camera_follow()
	for frame in 24:await physics_frame;p._physics_process(1.0/60)
	check(p.is_on_floor(),"Controller fixture stands on actual level collision")
	var samples: Array=[]
	for fraction in [.05,.35,.65,.9]:
		Input.action_release("aim");p.aiming=false;m.turn_in_place.cancel();m.advance_motion(.3)
		p.rotation.y=0;p.look_yaw=0;p.reset_camera_follow();p.look_yaw=deg_to_rad(60);p.pitch=.2;p.velocity=Vector3.ZERO
		p.camera_rotation_lag=.12;p.update_camera_follow(1.0/60)
		p._update_body_orientation(Vector2.ZERO,1.0/60)
		check(m.turn_in_place.active,"Exploration still starts the authored turn")
		m.advance_motion(m.turn_in_place.length*fraction/p.turn_in_place_speed)
		p.global_rotation.y+=m.turn_in_place.rotation_delta
		var prior_weight: float=m.turn_in_place.weight;var prior_position: Vector3=p.global_position
		Input.action_press("aim");await physics_frame;p._physics_process(1.0/60)
		var error := absf(wrapf(p.look_yaw-p.global_rotation.y,-PI,PI))
		check(p.aiming and not m.turn_in_place.active and is_zero_approx(m.turn_in_place.rotation_delta),"Aim cancels angular turn extraction on its first physics tick")
		check(error<.00001 and not p._body_turning,"Aim faces the mouse immediately at every turn phase")
		check(m.turn_in_place.weight<prior_weight,"The interrupted pose blends out while root facing is already aligned")
		check(p.global_position.distance_to(prior_position)<.001,"Aiming during a turn introduces no character displacement")
		check(p.camera_pivot.global_basis.get_rotation_quaternion().angle_to(p._camera_target_rotation())<.002,"Aim also clears exploration camera rotation lag on the same tick")
		for frame in 12:
			p.look_yaw=deg_to_rad(-75+frame*14);p.update_camera_follow(0);await physics_frame;p._physics_process(1.0/60)
			check(not m.turn_in_place.active and absf(wrapf(p.look_yaw-p.global_rotation.y,-PI,PI))<.00001,"Held aim tracks both yaw directions without starting another turn")
		samples.append({"fraction":fraction,"first_tick_error_degrees":rad_to_deg(error),"remaining_pose_weight":m.turn_in_place.weight})
		Input.action_release("aim");await physics_frame;p._physics_process(1.0/60)
		check(not m.turn_in_place.active,"Releasing aim does not resume cancelled root rotation")
	var result := {"ok":failures.is_empty(),"errors":failures,"lower_pivot_chest_shift_m":shift,"aim_interruptions":samples}
	FileAccess.open("res://docs/torso-aim-priority-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;game.queue_free();await process_frame;await process_frame
	print("TORSO_AIM_PRIORITY_OK " if failures.is_empty() else "TORSO_AIM_PRIORITY_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
