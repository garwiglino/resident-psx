extends Node3D

const Materials = preload("res://scripts/psx_materials.gd")
const AnimationAssets = preload("res://scripts/animation_assets.gd")
const UpperBodyLook = preload("res://scripts/upper_body_look.gd")
const UpperBodyAim = preload("res://scripts/upper_body_aim.gd")
const LowerBodyTurn = preload("res://scripts/lower_body_turn.gd")
const RunHeading = preload("res://scripts/run_heading.gd")
const WalkSpine = preload("res://scripts/walk_spine_compensation.gd")
const PistolShoulders = preload("res://scripts/pistol_shoulders.gd")
const WeaponDefinition = preload("res://scripts/weapon_definition.gd")
const UnarmedLocomotion: AnimationLibrary = preload("res://assets/character/animations/unarmed_locomotion.res")
const UNARMED_PREFIX := "unarmed_"
const WALK_DIRECTIONS := ["walk","forward_right","strafe_right","backward_right","backward","backward_left","strafe_left","forward_left"]
var weapon_slots: Dictionary={}
var mixer: AnimationPlayer
var root_sampler: AnimationPlayer
var model: Node3D
var weapon: Node3D
var hand_attachment: BoneAttachment3D
var weapon_socket: Node3D
var current := ""
var _action := ""
var clip_metadata: Dictionary={}
var blend_time := .22
var _root_fade_left := 0.0
var _pose_blend_budget := 0.0
var upper_body := UpperBodyLook.new()
var aim_pose := UpperBodyAim.new()
var _aim_profile: Array[String] = ["aim_pose","fire","reload"]
var turn_in_place := LowerBodyTurn.new()
var _armed_turn := turn_in_place
var _unarmed_turn := LowerBodyTurn.new()
var _unarmed_long_turn := LowerBodyTurn.new()
var run_heading := RunHeading.new()
var walk_spine := WalkSpine.new()
var pistol_shoulders := PistolShoulders.new()
var turn_in_place_speed := 1.0
var body_skeleton: Skeleton3D
var flashlight_bone := -1
var _flashlight_anchor := Vector3.ZERO
var _root_rotation := Quaternion.IDENTITY

func _ready() -> void:
	run_heading.setup(self)
	model=get_node_or_null("cop")
	if not model:
		model=load("res://assets/character/cop_player.glb").instantiate()
		model.name="cop"
		add_child(model)
	body_skeleton=model.get_node("rig/Skeleton3D")
	mixer=AnimationPlayer.new()
	mixer.name="Motion"
	model.add_child(mixer)
	mixer.root_node=NodePath("..")
	mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	mixer.root_motion_track=NodePath("rig/Skeleton3D:RootMotion")
	var library := AnimationLibrary.new()
	_add_clip(library,"idle",model,true)
	# Existing prototype clips were converted once to the game skeleton.
	for clip in ["walk","backward","strafe_left","strafe_right","run","aim","aim_walk"]:
		var path := "res://assets/character/legacy_animations/%s.res" % clip
		if ResourceLoader.exists(path):
			library.add_animation(clip,AnimationAssets.complete_upper_arm_segments(load(path),body_skeleton,true))
	# New exports are discovered without editing the controller.
	for file in DirAccess.get_files_at("res://assets/character/animations"):
		if not file.ends_with(".glb"):continue
		var path := "res://assets/character/animations/"+file
		var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path.get_basename()+".json")) if FileAccess.file_exists(path.get_basename()+".json") else {}
		var authored_name: String=metadata.get("clip",file.get_basename())
		var alias: String=authored_name.trim_prefix("player_pistol_").trim_prefix("player_")
		alias={"run_pistol":"run","walk_forward_pistol":"walk","walk_backward_pistol":"backward","walk_strafe_left_pistol":"strafe_left","walk_strafe_right_pistol":"strafe_right",
			"walk_forward_left_pistol":"forward_left","walk_forward_right_pistol":"forward_right",
			"walk_backward_left_pistol":"backward_left","walk_backward_right_pistol":"backward_right"}.get(alias,alias)
		var animations := AnimationAssets.read(path)
		var loop: bool=metadata.get("loop",alias in WALK_DIRECTIONS or alias in ["idle","run","aim","aim_walk"])
		_add_animations(library,authored_name,animations,loop)
		if alias!=authored_name:_add_animations(library,alias,animations,loop)
		clip_metadata[authored_name]=metadata
		clip_metadata[alias]=metadata
	for clip in UnarmedLocomotion.get_animation_list():
		var animation := AnimationAssets.complete_upper_arm_segments(UnarmedLocomotion.get_animation(clip),body_skeleton,true)
		library.add_animation(clip,animation)
		clip_metadata[clip]=animation.get_meta("source",{})
	flashlight_bone=body_skeleton.find_bone("DEF-spine.003")
	_setup_grip_blend_reference(library.get_animation("idle"))
	mixer.add_animation_library("",library)
	_setup_root_sampler(library)
	mixer.animation_finished.connect(func(clip: String):
		if clip==_action:_action="";current="")
	play("idle")
	mixer.advance(0)
	if flashlight_bone>=0:
		_flashlight_anchor=body_skeleton.get_bone_global_pose(flashlight_bone).origin
	Materials.apply_character(model)
	upper_body.setup(body_skeleton)
	walk_spine.setup(body_skeleton)
	pistol_shoulders.setup(body_skeleton)
	aim_pose.setup(body_skeleton,library.get_animation("aim_pose"),upper_body.affected)
	aim_pose.setup_fire(library.get_animation("fire"),float(clip_metadata.get("fire",{}).get("fps",24.0)))
	aim_pose.setup_reload(library.get_animation("reload") if library.has_animation("reload") else null,float(clip_metadata.get("reload",{}).get("fps",24.0)))
	turn_in_place.setup(body_skeleton,library.get_animation("turn_in_place_left") if library.has_animation("turn_in_place_left") else null,float(clip_metadata.get("turn_in_place_left",{}).get("fps",30.0)))
	_unarmed_turn.setup(body_skeleton,library.get_animation("unarmed_turn_in_place_left"),float(clip_metadata["unarmed_turn_in_place_left"].fps))
	_unarmed_long_turn.setup(body_skeleton,library.get_animation("unarmed_turn_in_place_left_long"),float(clip_metadata["unarmed_turn_in_place_left_long"].fps))

func select_turn_variant(use_long_unarmed: bool) -> void:
	if turn_in_place.active or turn_in_place.weight>.00001:return
	turn_in_place=_armed_turn if weapon else (_unarmed_long_turn if use_long_unarmed else _unarmed_turn)

func get_reload_duration() -> float:
	return aim_pose.reload_length

func reload_weapon() -> void:
	_restore_pose_layers()
	aim_pose.start_reload()
	_apply_pose_layers(0)
	if weapon:
		weapon.reload_return_blend_time=aim_pose.reload_return_time
		weapon.reload_weapon(get_reload_duration(),aim_pose.reload_fps)

func cancel_reload() -> void:
	_restore_pose_layers();aim_pose.cancel_reload()
	if weapon:weapon.cancel_reload()
	_apply_pose_layers(0)

func fire() -> void:
	_restore_pose_layers()
	aim_pose.start_fire()
	_apply_pose_layers(0)
	if weapon:weapon.fire()

func set_aiming(value: bool,duration: float) -> void:
	aim_pose.requested=value
	aim_pose.blend_time=duration

func _restore_pose_layers() -> void:
	upper_body.restore()
	aim_pose.restore()
	pistol_shoulders.restore()
	walk_spine.restore()
	turn_in_place.restore()
	run_heading.restore()

func _apply_pose_layers(delta: float) -> void:
	run_heading.apply()
	turn_in_place.apply()
	var turning := turn_in_place.active or turn_in_place.weight>.00001
	walk_spine.advance(delta,current.trim_prefix(UNARMED_PREFIX),turning);walk_spine.apply(turning)
	var pistol_stance := is_instance_valid(weapon) and not turning and (current in WALK_DIRECTIONS or current == "run" or current == "idle")
	pistol_shoulders.apply(delta, pistol_stance, blend_time)
	if aim_pose.requested or aim_pose.weight>0.0 or aim_pose.fire_time>=0.0 or aim_pose.reload_time>=0.0:
		aim_pose.capture()
		aim_pose.advance(delta,turn_in_place.upper_motion)
	turn_in_place.enforce()
	upper_body.capture()

func _setup_grip_blend_reference(idle: Animation) -> void:
	# Godot mixes rotations relative to bone rest. Flattened hand/finger
	# anchors and both right forearm deform bones cross the 180-degree boundary
	# during strafe_left and run, making their rotations unwind during fades.
	# Centre this mixing reference on the authored idle grip instead. Full
	# pose tracks and the GLB's explicit inverse skin binds stay unchanged.
	for bone in body_skeleton.get_bone_count():
		var name := String(body_skeleton.get_bone_name(bone))
		if not (name.begins_with("DEF-forearm.R") or name.begins_with("SEG-DEF-forearm.R") or name.begins_with("DEF-hand.") or name.begins_with("DEF-f_") or name.begins_with("DEF-thumb") or name.begins_with("DEF-palm")):continue
		var track := idle.find_track(NodePath("rig/Skeleton3D:"+name),Animation.TYPE_ROTATION_3D)
		if track<0:continue
		var reference := body_skeleton.get_bone_rest(bone)
		reference.basis=Basis(idle.rotation_track_interpolate(track,0)).scaled(reference.basis.get_scale())
		body_skeleton.set_bone_rest(bone,reference)

func _setup_root_sampler(library: AnimationLibrary) -> void:
	# Pose crossfades must not attenuate the newly requested stride. This
	# player samples only the authored root, independently of pose weights.
	root_sampler=AnimationPlayer.new()
	root_sampler.name="RootMotionSampler"
	model.add_child(root_sampler)
	root_sampler.root_node=mixer.root_node
	root_sampler.root_motion_track=mixer.root_motion_track
	root_sampler.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var roots := AnimationLibrary.new()
	for clip in library.get_animation_list():
		var source := library.get_animation(clip)
		var animation := Animation.new()
		animation.length=source.length
		animation.loop_mode=source.loop_mode
		for track in source.get_track_count():
			if source.track_get_path(track)==mixer.root_motion_track:source.copy_track(track,animation)
		roots.add_animation(clip,animation)
	root_sampler.add_animation_library("",roots)

func _add_clip(library: AnimationLibrary,name: String,source: Node,loop: bool) -> void:
	var animations: Array[Animation]=[]
	for imported in source.find_children("*","AnimationPlayer",true,false):
		if imported==mixer:continue
		for clip in imported.get_animation_list():
			if clip=="RESET":continue
			animations.append(imported.get_animation(clip))
		imported.active=false
	_add_animations(library,name,animations,loop)

func _add_animations(library: AnimationLibrary,name: String,animations: Array[Animation],loop: bool) -> void:
	var combined := Animation.new()
	combined.length=0
	for animation in animations:
		for track in animation.get_track_count():
			var node_path := String(animation.track_get_path(track)).get_slice(":",0)
			var bone_name := String(animation.track_get_path(track)).get_slice(":",1)
			if node_path=="rig/Skeleton3D" and model.get_node("rig/Skeleton3D").find_bone(bone_name)<0:continue
			if node_path=="rig" or node_path.begins_with("rig/"):
				animation.copy_track(track,combined)
				combined.length=maxf(combined.length,animation.length)
	combined.loop_mode=Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	AnimationAssets.complete_upper_arm_segments(combined,body_skeleton)
	if library.has_animation(name):library.remove_animation(name)
	library.add_animation(name,combined)

func prepare_weapon(definition: WeaponDefinition) -> Node3D:
	if weapon_slots.has(definition.id):return weapon_slots[definition.id].weapon
	if not definition.scene or not FileAccess.file_exists(definition.mount_file):return null
	var configuration=JSON.parse_string(FileAccess.get_file_as_string(definition.mount_file))
	if not configuration is Dictionary or not configuration.has("bone") or not configuration.has("transform_rows"):return null
	if body_skeleton.find_bone(configuration.bone)<0:return null
	var rows: Array=configuration.transform_rows
	if rows.size() not in [3,4]:return null
	for row in rows:
		if not row is Array or row.size()!=4:return null
	var instance=definition.scene.instantiate()
	if not instance is Node3D or not instance.has_method("deactivate") or not instance.has_method("fire"):
		instance.free();return null
	var attachment := BoneAttachment3D.new()
	attachment.name="WeaponAttachment_"+String(definition.id)
	attachment.bone_name=configuration.bone
	body_skeleton.add_child(attachment)
	var socket := Node3D.new()
	socket.name="WeaponSocket"
	socket.transform=Transform3D(Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2])),Vector3(rows[0][3],rows[1][3],rows[2][3]))
	attachment.add_child(socket)
	var visual: Node3D=instance
	socket.add_child(visual)
	if visual.has_method("configure_reload_hand"):visual.configure_reload_hand(body_skeleton,get_parent().get_parent() as CharacterBody3D)
	attachment.on_skeleton_update();attachment.visible=false
	Materials.apply_character(visual)
	weapon_slots[definition.id]={"weapon":visual,"attachment":attachment,"socket":socket}
	return visual

func equip_weapon(definition: WeaponDefinition) -> void:
	if not weapon and not definition:return
	_restore_pose_layers()
	if weapon:
		weapon.deactivate()
		hand_attachment.visible=false
	if not definition:
		weapon=null; hand_attachment=null; weapon_socket=null
		aim_pose.release(blend_time)
		_action=""
		_apply_pose_layers(0)
		return
	var slot: Dictionary=weapon_slots[definition.id]
	weapon=slot.weapon;hand_attachment=slot.attachment;weapon_socket=slot.socket
	hand_attachment.visible=true;hand_attachment.on_skeleton_update()
	var profile: Array[String]=[definition.aim_clip,definition.fire_clip,definition.reload_clip]
	if profile!=_aim_profile:
		_aim_profile=profile
		aim_pose=UpperBodyAim.new()
		var library := mixer.get_animation_library("")
		aim_pose.setup(body_skeleton,library.get_animation(definition.aim_clip) if library.has_animation(definition.aim_clip) else null,upper_body.affected)
		aim_pose.setup_fire(library.get_animation(definition.fire_clip) if library.has_animation(definition.fire_clip) else null,float(clip_metadata.get(definition.fire_clip,{}).get("fps",24.0)))
		aim_pose.setup_reload(library.get_animation(definition.reload_clip) if library.has_animation(definition.reload_clip) else null,float(clip_metadata.get(definition.reload_clip,{}).get("fps",24.0)))
	else:
		aim_pose.release(blend_time)
	_action=""
	weapon.play_idle()
	_apply_pose_layers(0)

func _process(_delta: float) -> void:
	# The custom renderer reads bone transforms before Godot's normal 3D draw pass.
	if hand_attachment:
		hand_attachment.on_skeleton_update()
		weapon.sync_after_attachment()

func get_flashlight_transform(offset: Vector3,view_basis: Basis) -> Transform3D:
	# Keep the source at chest height, independent of animated spine bob/twist.
	# +Z is the front of this mount; the camera looks along -Z.
	var anchor := body_skeleton.global_transform*_flashlight_anchor
	var facing := view_basis.orthonormalized()*Basis(Vector3.UP,PI)
	return Transform3D(facing,anchor).translated_local(offset)

func locomotion_clip(axis: Vector2) -> String:
	if axis.length_squared()<=.001:return "idle"
	var sector := posmod(roundi(atan2(axis.x,-axis.y)/(PI/4)),8)
	return WALK_DIRECTIONS[sector]

func locomotion_variant(clip: String) -> String:
	return clip if weapon else UNARMED_PREFIX+clip

func play(clip: String,speed := 1.0) -> void:
	if not mixer or not _action.is_empty():return
	mixer.speed_scale=speed
	if current!=clip:
		var duration := blend_time if not current.is_empty() else 0.0
		var start_at := 0.0
		if current.trim_prefix(UNARMED_PREFIX)==clip.trim_prefix(UNARMED_PREFIX) and current_clip_has_root_motion() and _clip_has_root_motion(clip):
			# The armed and unarmed takes share a stride cycle. Carry its phase
			# across a weapon change while sampling the new root immediately.
			start_at=fposmod(mixer.current_animation_position/mixer.current_animation_length,1.0)*mixer.get_animation(clip).length
		_start_clip(clip,duration,start_at)
		current=clip

func play_action(clip: String) -> bool:
	if not mixer.has_animation(clip):return false
	mixer.speed_scale=1.0
	_start_clip(clip,.06)
	_action=clip
	current=clip
	return true

func _start_clip(clip: String,duration: float,start_at := 0.0) -> void:
	_restore_pose_layers()
	_root_fade_left=duration if uses_root_motion() else 0.0
	# Native crossfading retains all still-playing outgoing clips when
	# interrupted. No frozen pose, slow-start curve or per-bone correction.
	var scaled_duration := duration*maxf(absf(mixer.speed_scale),.001)
	if duration<=0.0:
		mixer.stop(true)
		_pose_blend_budget=0.0
	else:
		_pose_blend_budget=maxf(_pose_blend_budget,scaled_duration)
	mixer.play(clip,scaled_duration)
	if start_at>0.0:mixer.seek(start_at)
	mixer.advance(0)
	root_sampler.stop(true)
	root_sampler.play(clip,0)
	if start_at>0.0:root_sampler.seek(start_at)
	root_sampler.advance(0)
	_apply_pose_layers(0)

func uses_root_motion() -> bool:
	return current_clip_has_root_motion() or _root_fade_left>.00001

func _clip_has_root_motion(clip: String) -> bool:
	return clip_metadata.get(clip,{}).get("root_motion",false)

func current_clip_has_root_motion() -> bool:
	return _clip_has_root_motion(current)

func advance_motion(delta: float,action_delta := -1.0) -> Vector3:
	if action_delta<0:action_delta=delta
	_restore_pose_layers()
	mixer.advance(delta)
	var displacement := mixer.get_root_motion_position()
	_root_rotation=mixer.get_root_motion_rotation()
	# Godot updates outgoing blend weights after evaluating the incoming
	# pose. Reapply those weights at the same time so a new request starts
	# from the displayed mixture, without advancing either clip again.
	if _pose_blend_budget>0.0:mixer.advance(0)
	_pose_blend_budget=maxf(_pose_blend_budget-absf(mixer.speed_scale*delta),0.0)
	root_sampler.speed_scale=mixer.speed_scale
	root_sampler.advance(delta)
	if current_clip_has_root_motion():
		displacement=root_sampler.get_root_motion_position()
		_root_rotation=root_sampler.get_root_motion_rotation()
	turn_in_place.advance(action_delta,turn_in_place_speed)
	_apply_pose_layers(action_delta)
	if weapon:weapon.advance_animation(action_delta)
	_root_fade_left=maxf(_root_fade_left-delta,0.0)
	return displacement

func root_motion_rotation() -> Quaternion:
	return _root_rotation

func root_motion_direction() -> Vector3:
	var xyz: Array=clip_metadata.get(current,{}).get("root_motion_vector",[0,0,0])
	return Vector3(xyz[0],xyz[1],xyz[2]).normalized()

func apply_look(view_direction: Vector3,yaw_limit: float,pitch_limit: float,enabled: bool,pivot_bone: StringName=&"DEF-spine",head_yaw := 0.0) -> void:
	upper_body.set_base_pivot(pivot_bone)
	upper_body.apply(view_direction,yaw_limit,pitch_limit,enabled,turn_in_place.upper_motion,run_heading.yaw if run_heading.applied else 0.0)
	upper_body.apply_head_turn(head_yaw)
	turn_in_place.enforce()
	if hand_attachment:
		hand_attachment.on_skeleton_update()
		weapon.sync_after_attachment()

