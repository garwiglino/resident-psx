@tool
extends CharacterBody3D

signal fired(origin: Vector3, direction: Vector3)
signal hurt
signal weapon_added(visual: Node3D)
signal footstepped(foot: StringName,position: Vector3)
const Motion = preload("res://scripts/character_motion.gd")
const WeaponDefinition = preload("res://scripts/weapon_definition.gd")
const WeaponInventory = preload("res://scripts/weapon_inventory.gd")
const FootstepSync = preload("res://scripts/footstep_sync.gd")
const AudioRouting=preload("res://scripts/audio/psx_audio_routing.gd")
const ObstructionProbe=preload("res://scripts/obstruction_probe.gd")

@export_group("Déplacements")
@export_range(0.1,10.0,0.05,"suffix:m/s") var walk_speed := 1.65
@export_range(0.1,15.0,0.05,"suffix:m/s") var run_speed := 3.1
@export_range(0.1,8.0,0.05,"suffix:m/s") var aim_walk_speed := 1.05
@export_range(0.1,2.0,0.05) var strafe_speed_multiplier := 1.0
@export_range(0.1,2.0,0.05) var backward_speed_multiplier := 1.0
@export_range(0.1,50.0,0.1,"suffix:m/s²") var acceleration := 10.0
@export_range(0.1,50.0,0.1,"suffix:m/s²") var braking := 14.0
@export_range(0.0,50.0,0.1,"suffix:m/s²") var gravity := 18.0

@export_group("Root motion")
## Utilise la distance animee pour les clips qui contiennent un deplacement racine.
@export var root_motion_enabled := true
## 1 = vitesse et longueur de pas de Blender. Ne depend pas de walk_speed.
@export_range(.1,3.0,.05) var root_motion_scale := 1.0
## Vitesse de lecture. Modifie ensemble la cadence et la vitesse de deplacement.
@export_range(.1,3.0,.05) var root_motion_playback_speed := 1.0
## Cadence du jog uniquement. Le root motion suit la meme vitesse de lecture.
@export_range(.5,2.0,.05) var run_animation_speed := 1.1
@export var root_motion_rotation_enabled := true
## Garde la direction demandee pendant les fondus entre avant, arriere et strafes.
@export var root_motion_steer_with_input := true

@export_group("Transitions")
## Duree du melange des poses. Le root motion repond immediatement aux deplacements.
@export_range(0.0,.5,.01,"suffix:s") var animation_blend_time := .22

@export_group("Course - orientation")
## Reutilise la course avant pour les diagonales. Le buste garde le regard.
@export var run_direction_enabled := true
@export_range(0,45,1,"degrees") var run_direction_max_yaw_degrees := 45.0
## Reponse progressive vers la diagonale et retour vers la marche ou l'idle.
@export_range(0,.4,.01,"suffix:s") var run_direction_response := .10

@export_group("Marche - compensation du buste")
## Repartit la torsion des quatre diagonales de marche dans le dos.
@export var walk_spine_compensation_enabled := true
@export_range(0,1,.05) var walk_spine_compensation_strength := 1.0
@export_range(0,.4,.01,"suffix:s") var walk_spine_compensation_response := .10

@export_group("Visee")
## Superpose la pose Blender au haut du corps. Le bassin et les jambes gardent leur animation.
@export var aim_pose_enabled := true
@export_range(0.0,.5,.01,"suffix:s") var aim_pose_blend_time := .18
## Fondu apres la derniere pose de recharge vers l'animation en cours.
## Les images du chargeur et le moment du remplissage des munitions ne changent pas.
@export_range(0.0,.8,.01,"suffix:s") var reload_pose_return_time := .24
## X = epaule, Y = hauteur, Z = recul pendant la visee.
@export var aim_camera_offset := Vector3(.32,1.45,.85)
## Angle vertical pendant la visee.
@export_range(10.0,100.0,.1,"degrees") var aim_camera_fov := 40.0
@export_range(0.0,.5,.01,"suffix:s") var aim_camera_transition_time := .18

@export_group("Buste et orientation")
@export var torso_follow_enabled := true
## DEF-spine abaisse le pivot d'un os ; DEF-spine.001 reprend le pivot precedent.
## Le bassin sert de point de rotation, mais garde sa propre animation.
@export_enum("DEF-spine","DEF-spine.001") var torso_pivot_bone := "DEF-spine"
## Rotation maximale du buste par rapport au bas du corps.
@export_range(10.0,85.0,1.0,"degrees") var torso_yaw_limit_degrees := 55.0
@export_range(5.0,70.0,1.0,"degrees") var torso_pitch_limit_degrees := 50.0
## Au repos, le bassin commence a suivre au-dela de cet ecart.
@export_range(5.0,80.0,1.0,"degrees") var body_turn_threshold_degrees := 45.0
## Arrete le recentrage lorsque l'ecart redescend sous ce seuil.
@export_range(0.0,30.0,1.0,"degrees") var body_turn_recenter_degrees := 10.0
@export_range(30.0,720.0,10.0,"suffix:deg/s") var body_turn_speed_degrees := 240.0
@export_range(.02,.3,.01,"suffix:s") var body_turn_response := .10

@export_group("Rotation sur place")
## Joue le turn Blender sur le corps entier, avec visee et suivi souris superposes.
@export var turn_in_place_enabled := true
## La vitesse de lecture et la rotation racine restent synchronisees.
@export_range(.25,3.0,.05) var turn_in_place_speed := 1.0
@export_range(0.0,.4,.01,"suffix:s") var turn_in_place_blend_time := .12
@export_enum("Court","Long") var unarmed_turn_variant := 0

@export_group("Camera - exploration")
## A l'arret, la souris fait orbiter la camera. En mouvement, le corps suit la direction demandee.
@export var free_orbit_enabled := false
@export_range(180.0,1440.0,10.0,"suffix:deg/s") var exploration_turn_speed_degrees := 1080.0
@export_range(.02,.2,.005,"suffix:s") var exploration_turn_response := .045
## Amplitude du regard quand Hitomi engage un virage en repartant.
@export_range(0.0,65.0,1.0,"degrees") var exploration_head_turn_degrees := 22.0
## Temps de reponse du cou et des epaules pendant l'anticipation.
@export_range(.03,.2,.005,"suffix:s") var exploration_head_turn_response := .075
@export_range(30.0,360.0,5.0,"suffix:deg/s") var exploration_head_turn_speed_degrees := 140.0
## Le buste accompagne legerement le regard en marchant. La visee a sa propre limite.
@export_range(0.0,25.0,1.0,"degrees") var exploration_torso_pitch_degrees := 12.0

@export_group("Caméra — cadrage")
## Position relative au joueur : X = épaule, Y = hauteur, Z = recul.
@export var camera_offset := Vector3(.3564056754,1.3540377617,1.7886838913):
	set(value):
		camera_offset=value
		_request_settings_update()
## Angle VERTICAL, calculé depuis les 50 mm et le sensor-fit AUTO de Blender.
@export_range(10.0,100.0,0.01,"degrees") var camera_fov := 30.219150726:
	set(value):
		camera_fov=value
		_request_settings_update()
@export_range(-80.0,80.0,0.1,"degrees") var initial_pitch_degrees := 0.0
@export_enum("Droite:1","Gauche:-1") var initial_shoulder := 1
@export_range(0.01,1.0,0.01,"suffix:m") var camera_near := 0.1
@export_range(10.0,200.0,1.0,"suffix:m") var camera_far := 55.0
@export_tool_button("Reprendre la caméra Blender") var restore_blender_camera: Callable=import_blender_camera

@export_group("Caméra — souris")
@export_range(.01,1.0,.001,"suffix:°/px") var mouse_sensitivity := .14323945
@export_range(.01,1.0,.001,"suffix:°/px") var aim_mouse_sensitivity := .1031324
@export var invert_y := false
@export_range(-89.0,0.0,.1,"degrees") var pitch_min_degrees := -48.7
@export_range(0.0,89.0,.1,"degrees") var pitch_max_degrees := 37.2
@export_range(1.0,30.0,.5) var shoulder_switch_speed := 10.0

@export_group("Caméra — suivi amorti")
## Temps de réponse du suivi de position. 0 = suivi immédiat.
@export_range(0.0,.3,.005,"suffix:s") var camera_translation_lag := .065
## Temps de réponse en lacet et en pitch. 0 = rotation immédiate.
@export_range(0.0,.3,.005,"suffix:s") var camera_rotation_lag := .05
@export_range(.01,.75,.01,"suffix:m") var camera_max_translation_lag := .22
@export_range(1.0,30.0,.5,"degrees") var camera_max_rotation_lag_degrees := 12.0
## Recale immédiatement la caméra lors des téléportations et changements de zone.
@export_range(.5,10.0,.25,"suffix:m") var camera_teleport_snap_distance := 3.0

@export_group("Caméra — collisions")
@export var camera_collision_enabled := true
@export_range(.02,.5,.01,"suffix:m") var camera_collision_radius := .14
@export_range(.01,.5,.01,"suffix:m") var camera_collision_margin := .16
@export_flags_3d_physics var camera_collision_mask := 1

@export_group("Personnage")
@export_range(.1,.6,.01,"suffix:m") var collision_radius := .24
@export_range(.8,2.4,.01,"suffix:m") var collision_height := 1.72
@export_range(.1,3.0,.01) var model_scale := 1.0
@export var animations_enabled := true
@export_range(0.0,10.0,.1,"degrees") var strafe_lean_degrees := 2.0

@export_group("Santé et arme")
@export_range(1,500,1) var max_health := 100
@export var starting_weapons: Array[WeaponDefinition]=[preload("res://assets/weapons/desert_eagle.tres")]
## -1 demarre sans arme equipee.
@export_range(-1,8,1) var starting_weapon_slot := 0
@export_range(0.0,5.0,.05,"suffix:s") var invulnerability_duration := 1.2
@export_range(1.0,90.0,.5,"suffix:°/s") var recoil_return_speed := 45.8
## Petite secousse visuelle seche ; ne modifie ni la visee ni la rotation du buste.
@export_range(0.0,2.0,.05) var shot_shake_strength := .55
@export_range(.04,.3,.01,"suffix:s") var shot_shake_duration := .12

@export_group("Lampe torche")
@export var flashlight_at_start := true
## Decalage depuis la hauteur du buste, oriente par la camera : X = cote, Y = hauteur, Z = devant.
@export var flashlight_offset := Vector3(0,0,.03)
## Obstacles qui retiennent la source du faisceau du cote du joueur.
@export_flags_3d_physics var flashlight_collision_mask := 1
@export var flashlight_color := Color.WHITE
@export_range(0.0,8.0,.1) var flashlight_energy := 2.0
@export_range(1.0,40.0,.5,"suffix:m") var flashlight_range := 16.0
## Ouverture totale du cone, avec un bord progressif.
@export_range(5.0,100.0,1.0,"degrees") var flashlight_cone_degrees := 44.0

@export_group("Audio - pas")
@export var footstep_sounds: Array[AudioStream]=[
	preload("res://assets/audio/footsteps/player_concrete_footsteps-01.wav"),preload("res://assets/audio/footsteps/player_concrete_footsteps-02.wav"),
	preload("res://assets/audio/footsteps/player_concrete_footsteps-03.wav"),preload("res://assets/audio/footsteps/player_concrete_footsteps-04.wav"),
	preload("res://assets/audio/footsteps/player_concrete_footsteps-05.wav"),preload("res://assets/audio/footsteps/player_concrete_footsteps-06.wav"),
	preload("res://assets/audio/footsteps/player_concrete_footsteps-07.wav"),preload("res://assets/audio/footsteps/player_concrete_footsteps-08.wav")]
@export_range(-40.0,0.0,.5,"suffix:dB") var footstep_volume_db := -16.0
@export_range(0.0,4.0,.5,"suffix:dB") var running_footstep_gain_db := 1.5
@export_range(0.0,.1,.005) var footstep_pitch_variation := .03
## Hauteur de la semelle au contact, dans le repere du squelette.
@export_range(0.0,.03,.001,"suffix:m") var footstep_contact_height := .008
## Le pied doit se relever avant de pouvoir declencher un nouveau pas.
@export_range(.02,.12,.005,"suffix:m") var footstep_lift_height := .04
## Evite deux sons superposes lors d'un changement de direction rapide.
@export_range(0.0,.25,.01,"suffix:s") var footstep_min_interval := .10
@export_group("Audio - armes")
@export_range(-40.0,0.0,.5,"suffix:dB") var shot_volume_db := -8.0
@export_range(-40.0,0.0,.5,"suffix:dB") var reload_volume_db := -14.0
@export_range(-40.0,0.0,.5,"suffix:dB") var weapon_handling_volume_db := -18.0
@export_group("Audio - joueur")
@export_range(-40.0,0.0,.5,"suffix:dB") var effects_volume_db := -14.0

var health := 100
var weapon_inventory := WeaponInventory.new()
# Compatibility views for HUD/game code; all rounds and timers live in the inventory.
var ammo: int:
	get:return weapon_inventory.ammo()
	set(value):weapon_inventory.set_ammo(value)
var reserve: int:
	get:return weapon_inventory.reserve()
	set(value):weapon_inventory.set_reserve(value)
var magazine_capacity: int:
	get:return weapon_definition().magazine_capacity if weapon_definition() else 0
	set(value):
		if weapon_definition():
			weapon_definition().magazine_capacity=maxi(value,1)
			ammo=ammo
var reload_duration: float:
	get:return weapon_definition().reload_duration if weapon_definition() else 0.0
	set(value):
		if weapon_definition():weapon_definition().reload_duration=maxf(value,.01)
var aiming := false
var _action_release_guard := false
var _empty_sound_variants: Array[AudioStream]=[]
var _last_empty_variant := -1
var flashlight := true
var enabled := false
## Blocks player commands only; animation, physics and current actions continue.
var controls_blocked := false
var reload_left: float:
	get:return weapon_inventory.action_left if weapon_inventory.action==WeaponInventory.Action.RELOADING else 0.0
var shot_left: float:
	get:return weapon_inventory.cooldown()
var recoil := 0.0
var _shot_shake_left := 0.0
var _shot_shake_side := 1.0
var _shot_shake_multiplier := 1.0
var pitch := 0.0
var look_yaw := 0.0
var _body_turning := false
var _departure_elapsed := 0.0
var _departure_head_yaw := 0.0
var _departure_torso_yaw := 0.0
var _exploration_pitch := 0.0
var _aim_look_pitch := 0.0
var _aim_look_weight := 0.0
var _orbit_running := false
var _run_view_yaw := 0.0
var shoulder := 1.0
var footsteps := FootstepSync.new()
var invincible := 0.0
var camera: Camera3D
var camera_pivot: Node3D
var arm: SpringArm3D
var visual: Node3D
var motion: Node3D
var sounds: Dictionary = {}
var _footstep_players: Array[AudioStreamPlayer]=[]
var _footstep_cursor := 0
var _last_step_variant := -1
var _audio_settings: Array=[]
var source_offset := Vector3(.3564058,1.3540379,1.7886838)
var source_fov := 30.21915
var _applied_settings: Array=[]
var _camera_follow_ready := false
var _camera_follow_rotation := Quaternion.IDENTITY
var _camera_previous_player_position := Vector3.ZERO
var _camera_probe := ObstructionProbe.new()
var _flashlight_probe := ObstructionProbe.new()
var _camera_aim_weight := 0.0
var _aim_camera_obstructed := false
var _aim_chest_bone := -1
var _aim_head_bone := -1

func _request_settings_update() -> void:
	if is_inside_tree():
		apply_settings.call_deferred()

func import_blender_camera() -> void:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/camera.json"))
	var p: Array=config.position
	camera_offset=Vector3(p[0],p[1],p[2])
	camera_fov=config.fov_vertical_degrees
	camera_near=config.near
	initial_pitch_degrees=0
	apply_settings()

func apply_settings() -> void:
	camera_pivot=get_node_or_null("CameraPivot")
	arm=get_node_or_null("CameraPivot/SpringArm3D")
	camera=get_node_or_null("CameraPivot/SpringArm3D/Camera3D")
	visual=get_node_or_null("Visual")
	if not camera or not arm or not camera_pivot:
		return
	source_offset=camera_offset
	source_fov=camera_fov
	if Engine.is_editor_hint() or not _camera_follow_ready:
		camera_pivot.position=Vector3(0,_current_camera_offset().y,0)
	arm.spring_length=maxf(_current_camera_offset().z,.05)
	arm.margin=camera_collision_margin
	arm.collision_mask=camera_collision_mask if camera_collision_enabled else 0
	arm.shape.radius=camera_collision_radius
	arm.position.x=shoulder*_current_camera_offset().x
	camera.fov=lerpf(source_fov,aim_camera_fov,_camera_aim_blend())
	camera.near=camera_near
	camera.far=camera_far
	visual.get_node("CharacterMotion").scale=Vector3.ONE*model_scale
	var collider: CollisionShape3D=get_node("CollisionShape3D")
	collider.shape.radius=collision_radius
	collider.shape.height=maxf(collision_height,collision_radius*2)
	collider.position.y=collider.shape.height*.5
	if Engine.is_editor_hint():
		camera_pivot.rotation.x=deg_to_rad(initial_pitch_degrees)
	_applied_settings=_settings_values()

func _settings_values() -> Array:
	return [camera_offset,camera_fov,camera_near,camera_far,camera_collision_enabled,camera_collision_radius,camera_collision_margin,camera_collision_mask,collision_radius,collision_height,model_scale,aim_camera_offset,aim_camera_fov,aim_camera_transition_time]

func _ready() -> void:
	shoulder=float(initial_shoulder)
	pitch=deg_to_rad(initial_pitch_degrees)
	apply_settings()
	if Engine.is_editor_hint():
		set_process(true)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	motion=visual.get_node("CharacterMotion")
	_aim_chest_bone=motion.body_skeleton.find_bone("DEF-spine.003")
	_aim_head_bone=motion.body_skeleton.find_bone("DEF-spine.006")
	add_to_group("audio_listener_player")
	add_to_group("player")
	footsteps.setup(motion.body_skeleton)
	health=max_health
	flashlight=flashlight_at_start
	arm.add_excluded_object(get_rid())
	_camera_probe.setup(self)
	_flashlight_probe.setup(self)
	# Solve after the lag/shoulder/aim updates, rather than using the spring
	# arm's previous physics-tick result for this frame's changed transform.
	arm.set_physics_process_internal(false)
	camera_pivot.top_level=true
	reset_camera_follow()
	camera.current = true
	for sound_name in ["shot", "aim", "step", "reload", "empty", "hurt", "pickup"]:
		var audio := AudioStreamPlayer.new()
		audio.name="Son_"+sound_name
		if sound_name not in ["shot","aim","reload","empty","step"]:audio.stream=load("res://assets/audio/%s.wav" % sound_name)
		if sound_name=="shot":audio.max_polyphony=8
		AudioRouting.set_category(audio,{"shot":&"Weapon Shots","aim":&"Weapon Handling","reload":&"Weapon Handling","empty":&"Weapon Handling","step":&"Footsteps","hurt":&"Player Foley","pickup":&"UI"}[sound_name])
		add_child(audio)
		sounds[sound_name] = audio
	_footstep_players.append(sounds.step)
	for index in 3:
		var audio := AudioStreamPlayer.new();audio.name="Son_pas_%d" % (index+1);AudioRouting.set_category(audio,&"Footsteps");add_child(audio);_footstep_players.append(audio)
	_sync_audio_levels()
	weapon_inventory.weapon_changed.connect(_on_weapon_changed)
	for definition in starting_weapons:give_weapon(definition)
	if starting_weapon_slot>=0 and not weapon_inventory.weapons.is_empty():
		weapon_inventory.equip(mini(starting_weapon_slot,weapon_inventory.weapons.size()-1),true)
	else:
		weapon_inventory.holstered=starting_weapon_slot<0
		motion.current=""
		motion.play(motion.locomotion_variant("idle"))

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or controls_blocked or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_apply_mouse_motion(event.relative)
	if _action_release_guard:return
	if event.is_action_pressed("reload"):
		reload_weapon()
	if event.is_action_pressed("torch"):
		flashlight = not flashlight
	if event.is_action_pressed("shoulder"):
		shoulder *= -1
	if event.is_action_pressed("weapon_next"):cycle_weapon(1)
	if event.is_action_pressed("weapon_previous"):cycle_weapon(-1)
	for slot in 4:
		if event.is_action_pressed("weapon_slot_%d" % (slot+1)):equip_weapon(slot)

func _apply_mouse_motion(relative: Vector2) -> void:
	var sensitivity := deg_to_rad(aim_mouse_sensitivity if aiming else mouse_sensitivity)
	look_yaw=wrapf(look_yaw-relative.x*sensitivity,-PI,PI)
	pitch=clampf(pitch-relative.y*sensitivity*(-1 if invert_y else 1),deg_to_rad(pitch_min_degrees),deg_to_rad(pitch_max_degrees))

func _physics_process(delta: float) -> void:
	if _action_release_guard and _action_inputs_released():_action_release_guard=false
	weapon_inventory.advance(delta)
	invincible = maxf(invincible-delta,0)
	var was_aiming := aiming
	aiming = enabled and not controls_blocked and not _action_release_guard and health>0 and weapon_definition()!=null and Input.is_action_pressed("aim") and weapon_inventory.action==WeaponInventory.Action.READY
	if aiming and not was_aiming and sounds.aim.stream:AudioRouting.play(sounds.aim)
	var axis := Input.get_vector("left","right","forward","back") if enabled and not controls_blocked else Vector2.ZERO
	var sprint := _run_requested(axis)
	if not free_orbit_enabled:motion.select_turn_variant(unarmed_turn_variant==1)
	_update_body_orientation(axis,delta)
	if aiming and (free_orbit_enabled or not was_aiming):update_camera_follow(0)
	var speed := run_speed if sprint else (aim_walk_speed if aiming else walk_speed)
	var direction := _movement_direction(axis)
	var exploring := free_orbit_enabled and not aiming
	var moving := axis.length_squared()>.001
	var stride_speed := 1.0
	if exploring and moving:
		# Shorten the first stride during a large turn, keeping its timing and
		# root displacement tied to the same playback speed.
		var alignment := -global_basis.z.normalized().dot(direction.normalized())
		stride_speed=lerpf(.3,1.0,smoothstep(0.0,.94,alignment))
	var clip := "idle"
	if moving:
		if sprint:clip="run"
		elif exploring:clip="walk"
		else:clip=motion.locomotion_clip(axis)
	motion.blend_time=animation_blend_time
	motion.walk_spine.enabled=walk_spine_compensation_enabled
	motion.walk_spine.strength=walk_spine_compensation_strength
	motion.walk_spine.response=walk_spine_compensation_response
	motion.aim_pose.reload_return_time=reload_pose_return_time
	motion.set_aiming(aiming and animations_enabled and aim_pose_enabled,aim_pose_blend_time)
	var selected_clip: String=clip if animations_enabled else "idle"
	var run_yaw := 0.0
	if not free_orbit_enabled and run_direction_enabled and selected_clip=="run" and motion._action.is_empty():
		run_yaw=clampf(atan2(-axis.x,-axis.y),-deg_to_rad(run_direction_max_yaw_degrees),deg_to_rad(run_direction_max_yaw_degrees))
	motion.run_heading.advance(run_yaw,delta,run_direction_response)
	selected_clip=motion.locomotion_variant(selected_clip)
	var root_playback: bool=root_motion_enabled and motion._clip_has_root_motion(selected_clip) and moving
	var playback_speed := root_motion_playback_speed*axis.length() if root_playback else 1.0
	if moving:playback_speed*=stride_speed
	if clip=="run" and animations_enabled:playback_speed*=run_animation_speed
	motion.play(selected_clip,playback_speed)
	var use_root: bool=animations_enabled and root_motion_enabled and motion.uses_root_motion()
	# Advance exactly once per physics tick; extraction removes the visible root travel.
	var root_delta: Vector3=motion.advance_motion(delta if animations_enabled else 0.0,delta)
	if enabled and not is_zero_approx(motion.turn_in_place.rotation_delta):
		global_rotation.y=wrapf(global_rotation.y+motion.turn_in_place.rotation_delta,-PI,PI)
	var rate := acceleration if moving else braking
	if use_root:
		var displacement: Vector3=motion.global_basis*root_delta*root_motion_scale
		var authored_direction: Vector3=motion.global_basis*motion.root_motion_direction()
		authored_direction.y=0
		if (root_motion_steer_with_input or exploring) and direction.length_squared()>.0001 and authored_direction.length_squared()>.0001:
			# Extract the authored stride along its axis. Cross-fading from another
			# direction must not carry the capsule sideways against the player's input.
			displacement=direction.normalized()*maxf(displacement.dot(authored_direction.normalized()),0.0)
		velocity.x=displacement.x/delta
		velocity.z=displacement.z/delta
		if root_motion_rotation_enabled and not free_orbit_enabled and not aiming and not sprint:rotation.y+=motion.root_motion_rotation().get_euler().y
	else:
		velocity.x = move_toward(velocity.x,direction.x*speed*stride_speed,delta*rate)
		velocity.z = move_toward(velocity.z,direction.z*speed*stride_speed,delta*rate)
	if not is_on_floor():
		velocity.y -= gravity*delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if aiming and not camera_pivot.global_position.is_equal_approx(global_position+Vector3.UP*_current_camera_offset().y):
		_resolve_camera_collision()
	var actual_speed := Vector2(get_real_velocity().x,get_real_velocity().z).length()
	var lean := 0.0 if exploring else -axis.x*deg_to_rad(strafe_lean_degrees)
	visual.rotation.z=lerpf(visual.rotation.z,lean,1-exp(-delta*8))
	if free_orbit_enabled:_update_exploration_pitch(delta,moving and not sprint)
	_apply_upper_body_look()
	_update_footsteps(delta,actual_speed)
	if enabled and not controls_blocked and aiming and not _action_release_guard:
		var trigger := Input.is_action_pressed("fire") if weapon_definition().automatic else Input.is_action_just_pressed("fire")
		if trigger:shoot()

func _update_footsteps(delta: float,actual_speed: float) -> void:
	var audible := enabled and health>0 and animations_enabled and is_on_floor() and actual_speed>.02
	var contact := footsteps.advance(delta,audible,footstep_contact_height,footstep_lift_height,footstep_min_interval)
	if contact<0:return
	_play_footstep(actual_speed)
	var foot: Dictionary=footsteps.feet[contact]
	footstepped.emit(foot.side,motion.body_skeleton.global_transform*foot.position)

func _play_footstep(actual_speed: float) -> void:
	var variants: Array[AudioStream]=footstep_sounds.filter(func(source: AudioStream):return source!=null)
	if variants.is_empty():return
	var choice := randi_range(0,variants.size()-1)
	if variants.size()>1 and _last_step_variant>=0:
		choice=randi_range(0,variants.size()-2)
		if choice>=_last_step_variant:choice+=1
	_last_step_variant=choice
	sounds.step=_footstep_players[_footstep_cursor];_footstep_cursor=(_footstep_cursor+1)%_footstep_players.size()
	AudioRouting.stop(sounds.step)
	sounds.step.stream=get_node("/root/PSXAudio").prepare(variants[choice])
	sounds.step.volume_db=footstep_volume_db+(running_footstep_gain_db if actual_speed>walk_speed*1.25 else 0)
	sounds.step.pitch_scale=randf_range(1-footstep_pitch_variation,1+footstep_pitch_variation)
	AudioRouting.play(sounds.step)

func _sync_audio_levels() -> void:
	if sounds.is_empty():return
	var definition := weapon_definition()
	var gains := Vector3(definition.shot_gain_db,definition.reload_gain_db,definition.handling_gain_db) if definition else Vector3.ZERO
	var signature: Array=[footstep_volume_db,shot_volume_db,reload_volume_db,weapon_handling_volume_db,effects_volume_db,gains]
	if signature==_audio_settings:return
	_audio_settings=signature
	sounds.shot.volume_db=shot_volume_db+gains.x;sounds.reload.volume_db=reload_volume_db+gains.y
	for kind in ["aim","empty"]:sounds[kind].volume_db=weapon_handling_volume_db+gains.z
	for kind in ["hurt","pickup"]:sounds[kind].volume_db=effects_volume_db
	for player in _footstep_players:player.volume_db=footstep_volume_db

func _process(delta: float) -> void:
	var settings := _settings_values()
	if settings!=_applied_settings:
		apply_settings()
	if Engine.is_editor_hint():
		return
	_sync_audio_levels()
	recoil = move_toward(recoil,0,delta*deg_to_rad(recoil_return_speed))
	_shot_shake_left=maxf(_shot_shake_left-delta,0)
	update_camera_follow(delta)
	_apply_upper_body_look()

func _camera_aim_blend() -> float:
	return _camera_aim_weight*_camera_aim_weight*(3.0-2.0*_camera_aim_weight)

func _current_camera_offset() -> Vector3:
	return source_offset.lerp(aim_camera_offset,_camera_aim_blend())

func _run_requested(axis: Vector2) -> bool:
	if not enabled or controls_blocked or health<=0 or aiming or not Input.is_action_pressed("sprint"):
		return false
	return axis.length_squared()>.001 if free_orbit_enabled else axis.y<-.1

func _movement_direction(axis: Vector2) -> Vector3:
	var backwards := backward_speed_multiplier if axis.y>0 else 1.0
	return Basis(Vector3.UP,look_yaw)*Vector3(axis.x*strafe_speed_multiplier,0,axis.y*backwards)

func _face_camera_immediately() -> void:
	motion.turn_in_place.cancel();_body_turning=false;global_rotation.y=look_yaw

func _update_body_orientation(axis: Vector2,delta: float) -> void:
	motion.turn_in_place.blend_time=turn_in_place_blend_time
	motion.turn_in_place_speed=turn_in_place_speed
	if not enabled:
		motion.turn_in_place.cancel()
		_orbit_running=false
		_update_departure_look(0.0,delta,false)
		return
	if free_orbit_enabled:
		motion.turn_in_place.cancel()
		_body_turning=false
		_follow_running_camera(_run_requested(axis))
		if aiming and not controls_blocked:
			_reset_departure_look()
			_face_camera_immediately()
		elif not controls_blocked and health>0 and axis.length_squared()>.001:
			var direction := _movement_direction(axis)
			var target := atan2(-direction.x,-direction.z)
			var offset := angle_difference(global_rotation.y,target)
			# Keep the first turning side when the input crosses the seam behind Hitomi.
			if absf(offset)>PI-.04 and absf(_departure_head_yaw)>.001:
				offset=absf(offset)*signf(_departure_head_yaw)
			var turn_weight := 1.0
			if animations_enabled and exploration_head_turn_degrees>0.0:
				_update_departure_look(offset,delta,true)
				turn_weight=smoothstep(.045,.095,_departure_elapsed)
			else:
				_update_departure_look(0.0,delta,false)
			_turn_toward(offset,delta*turn_weight,exploration_turn_response,exploration_turn_speed_degrees)
		else:
			_update_departure_look(0.0,delta,false)
		return
	# Aim owns the facing immediately. Cancel angular extraction before the
	# animation advances, while allowing the current turn pose to blend out.
	if aiming or _run_requested(axis):
		_face_camera_immediately()
		return
	if not torso_follow_enabled:
		motion.turn_in_place.cancel()
		global_rotation.y=look_yaw
		_body_turning=false
		return
	var offset := wrapf(look_yaw-global_rotation.y,-PI,PI)
	var threshold := deg_to_rad(minf(body_turn_threshold_degrees,torso_yaw_limit_degrees))
	var recenter := deg_to_rad(minf(body_turn_recenter_degrees,rad_to_deg(threshold)*.8))
	var moving := axis.length_squared()>.001
	var animated_turn := turn_in_place_enabled and animations_enabled and root_motion_enabled and root_motion_rotation_enabled and not moving and is_on_floor()
	if motion.turn_in_place.active:
		# Finish the authored step rather than cutting it at the recenter threshold.
		# Movement, airborne state or a reversed look can interrupt it with a blend.
		if animated_turn and offset>.00001:
			_body_turning=true;return
		motion.turn_in_place.cancel();_body_turning=false
	if animated_turn and not controls_blocked and offset>=threshold and Vector2(velocity.x,velocity.z).length_squared()<.0025:
		if motion.turn_in_place.start():_body_turning=true;return
	# Keep the body still while the last lower-body pose blends back to idle.
	if animated_turn and motion.turn_in_place.weight>.00001 and offset>=0:return
	if animated_turn and offset>=0 and motion.turn_in_place.available():_body_turning=false;return
	if absf(offset)>=threshold:_body_turning=true
	elif absf(offset)<=recenter:_body_turning=false
	if moving or _body_turning:
		_turn_toward(offset,delta,body_turn_response,body_turn_speed_degrees)

func _turn_toward(offset: float,delta: float,response: float,speed_degrees: float) -> void:
	var step := offset*(1-exp(-delta/maxf(response,.001)))
	var maximum := deg_to_rad(speed_degrees)*delta
	global_rotation.y=wrapf(global_rotation.y+clampf(step,-maximum,maximum),-PI,PI)

func _update_departure_look(offset: float,delta: float,moving: bool) -> void:
	_departure_elapsed=minf(_departure_elapsed+delta,.40) if moving else 0.0
	var envelope := 1.0-smoothstep(.20,.37,_departure_elapsed) if moving else 0.0
	var neck_limit := deg_to_rad(exploration_head_turn_degrees)
	var torso_limit := minf(neck_limit*.35,deg_to_rad(torso_yaw_limit_degrees)) if torso_follow_enabled else 0.0
	var follow := 1.0-exp(-delta/exploration_head_turn_response)
	var torso_target := clampf(offset*.3,-torso_limit,torso_limit)*smoothstep(.02,.13,_departure_elapsed)*envelope
	_departure_torso_yaw=lerpf(_departure_torso_yaw,torso_target,follow)
	var anticipation := clampf(offset,-neck_limit,neck_limit)*smoothstep(0.0,.075,_departure_elapsed)
	var head_target := (anticipation-_departure_torso_yaw)*envelope
	var speed := deg_to_rad(exploration_head_turn_speed_degrees)
	var next_yaw := lerpf(_departure_head_yaw,head_target,follow)
	_departure_head_yaw=move_toward(_departure_head_yaw,next_yaw,speed*delta)

func _reset_departure_look() -> void:
	_departure_elapsed=0.0
	_departure_head_yaw=0.0
	_departure_torso_yaw=0.0

func _follow_running_camera(running: bool) -> void:
	# A jog turn from the movement keys eases in. Mouse yaw stays immediate
	# once running, including input received between physics ticks.
	if running and _orbit_running:
		var view_change := angle_difference(_run_view_yaw,look_yaw)
		global_rotation.y=wrapf(global_rotation.y+view_change,-PI,PI)
	_orbit_running=running
	_run_view_yaw=look_yaw

func _update_exploration_pitch(delta: float,walking: bool) -> void:
	var limit := deg_to_rad(exploration_torso_pitch_degrees)
	var target := clampf(pitch*.3,-limit,limit) if walking else 0.0
	_exploration_pitch=lerpf(_exploration_pitch,target,1-exp(-delta/.10))
	if aiming:_aim_look_pitch=pitch+recoil
	var aim_target := 1.0 if aiming else 0.0
	_aim_look_weight=move_toward(_aim_look_weight,aim_target,delta/aim_pose_blend_time) if aim_pose_blend_time>0 else aim_target

func _apply_upper_body_look() -> void:
	if not motion or not camera:return
	var direction := -camera.global_basis.z
	var head_yaw := 0.0
	if free_orbit_enabled:
		var aim_weight := smoothstep(0.0,1.0,_aim_look_weight)
		var aim_pitch := pitch+recoil if aiming else _aim_look_pitch
		var torso_pitch := lerpf(_exploration_pitch,aim_pitch,aim_weight)
		var torso_yaw := global_rotation.y+_departure_torso_yaw
		direction=Quaternion(Vector3.UP,torso_yaw)*Quaternion(Vector3.RIGHT,torso_pitch)*Vector3.FORWARD
		head_yaw=_departure_head_yaw
	motion.apply_look(direction,deg_to_rad(torso_yaw_limit_degrees),deg_to_rad(torso_pitch_limit_degrees),torso_follow_enabled,StringName(str(torso_pivot_bone)),head_yaw)

func _camera_target_rotation() -> Quaternion:
	return Quaternion(Vector3.UP,look_yaw)*Quaternion(Vector3.RIGHT,pitch)

func reset_camera_follow(sync_facing := true) -> void:
	if not camera_pivot or Engine.is_editor_hint():
		return
	if sync_facing:
		look_yaw=global_rotation.y
		_body_turning=false
		_reset_departure_look()
		_orbit_running=false
		_exploration_pitch=0.0
		_aim_look_pitch=pitch+recoil
		_aim_look_weight=1.0 if aiming else 0.0
		if motion:motion.turn_in_place.cancel()
		if motion:motion.run_heading.reset()
	_camera_follow_rotation=_camera_target_rotation()
	camera_pivot.global_position=global_position+Vector3.UP*_current_camera_offset().y
	camera_pivot.global_basis=Basis(_camera_follow_rotation*Quaternion(Vector3.RIGHT,recoil))
	_camera_previous_player_position=global_position
	_camera_follow_ready=true
	_resolve_camera_collision()

func update_camera_follow(delta: float) -> void:
	var running := false
	if enabled and not controls_blocked and health>0 and not aiming and InputMap.has_action("sprint") and Input.is_action_pressed("sprint"):
		running=_run_requested(Input.get_vector("left","right","forward","back"))
	# Mouse updates can arrive between physics ticks. Keep the running actor
	# aligned on render frames too, without advancing its animation a second time.
	if running:
		if not free_orbit_enabled:_face_camera_immediately()
		elif _orbit_running:_follow_running_camera(true)
	if aiming and enabled and not controls_blocked:
		global_rotation.y=look_yaw
	_camera_aim_weight=move_toward(_camera_aim_weight,1.0 if aiming else 0.0,delta/maxf(aim_camera_transition_time,.00001)) if aim_camera_transition_time>0 else (1.0 if aiming else 0.0)
	var framing := _current_camera_offset()
	arm.spring_length=maxf(framing.z,.05)
	arm.position.x=lerpf(arm.position.x,shoulder*framing.x,1-exp(-delta*shoulder_switch_speed))
	camera.fov=lerpf(source_fov,aim_camera_fov,_camera_aim_blend())
	if not _camera_follow_ready or global_position.distance_to(_camera_previous_player_position)>camera_teleport_snap_distance:
		reset_camera_follow(false)
		return
	_camera_previous_player_position=global_position
	var target_position := global_position+Vector3.UP*framing.y
	var target_rotation := _camera_target_rotation()
	var multiplier := 0.0 if aiming or running else 1.0
	var translation_time := camera_translation_lag*multiplier
	var rotation_time := camera_rotation_lag*multiplier
	# Exponential response is independent of the render frame rate.
	var position_alpha := 1.0-exp(-delta/translation_time) if translation_time>.00001 else 1.0
	var rotation_alpha := 1.0-exp(-delta/rotation_time) if rotation_time>.00001 else 1.0
	var position := camera_pivot.global_position.lerp(target_position,position_alpha)
	var offset := (position-target_position).limit_length(camera_max_translation_lag)
	# Prevent the delayed anchor from taking a shortcut through a wall at a corner.
	if camera_collision_enabled and offset.length_squared()>.000001:
		offset=_camera_probe.sweep(get_world_3d().direct_space_state,target_position,target_position+offset,_camera_probe_radius(),camera_collision_mask)-target_position
	camera_pivot.global_position=target_position+offset
	_camera_follow_rotation=_camera_follow_rotation.slerp(target_rotation,rotation_alpha).normalized()
	var angle := _camera_follow_rotation.angle_to(target_rotation)
	var limit := deg_to_rad(camera_max_rotation_lag_degrees)
	if angle>limit:
		_camera_follow_rotation=_camera_follow_rotation.slerp(target_rotation,1.0-limit/angle).normalized()
	# Recoil stays immediate and never feeds back into the rotation filter.
	camera_pivot.global_basis=Basis(_camera_follow_rotation*Quaternion(Vector3.RIGHT,recoil))
	_resolve_camera_collision()

func _camera_probe_radius() -> float:
	# Protect all four near-plane corners, not just the centre of the image.
	var half_height := camera.near*tan(deg_to_rad(camera.fov)*.5)
	var half_width := half_height*4.0/3.0
	# The PSX raster always uses a vertical FOV and a 320x240 framebuffer.
	return maxf(camera_collision_radius,Vector3(half_width,half_height,camera.near).length()+.01)

func _resolve_camera_collision() -> void:
	if aiming:
		camera_pivot.global_position=global_position+Vector3.UP*_current_camera_offset().y
	var pivot := camera_pivot.global_position
	var rear := camera_pivot.global_basis.z
	var aiming_view := aiming or _camera_aim_weight>0.0
	var reach := maxf(arm.spring_length,_aim_camera_minimum_depth()+.045) if aiming_view else arm.spring_length
	var lateral := arm.position.x
	if aiming_view:
		# Allow for the animated lean of the head and shoulder during a strafe.
		var side := signf(lateral) if absf(lateral)>.01 else shoulder
		lateral=side*maxf(absf(lateral),_aim_shoulder_clearance(camera_pivot.global_transform,side))
	var desired := camera_pivot.global_transform*Vector3(lateral,0,reach)
	if camera_collision_enabled:
		var space := get_world_3d().direct_space_state
		var radius := _camera_probe_radius()
		desired=_camera_probe.sweep(space,pivot,desired,radius,camera_collision_mask,camera_collision_margin)
		if aiming_view and (desired-pivot).dot(rear)<_aim_camera_minimum_depth():
			# A side wall can block the shoulder offset while leaving the
			# space directly behind Hitomi clear.
			var centered := _camera_probe.sweep(space,pivot,pivot+rear*reach,radius,camera_collision_mask,camera_collision_margin)
			if (centered-pivot).dot(rear)>(desired-pivot).dot(rear):desired=centered
	camera.global_transform=Transform3D(camera_pivot.global_basis,desired)

func _aim_camera_minimum_depth() -> float:
	return camera.near+maxf(.34*model_scale,collision_radius)

func _aim_shoulder_clearance(frame: Transform3D,side: float) -> float:
	var rig: Skeleton3D=motion.body_skeleton
	var minimum := 0.0
	if _aim_chest_bone>=0:
		var chest := rig.global_transform*rig.get_bone_global_pose(_aim_chest_bone).origin
		minimum=maxf(minimum,(chest-frame.origin).dot(frame.basis.x)*side+.23*model_scale)
	if _aim_head_bone>=0:
		var head := rig.global_transform*rig.get_bone_global_pose(_aim_head_bone).origin
		minimum=maxf(minimum,(head-frame.origin).dot(frame.basis.x)*side+.13*model_scale)
	return minimum

func should_hide_aim_meshes(frame: Transform3D) -> bool:
	if not aiming and _camera_aim_weight<=0.0:
		_aim_camera_obstructed=false
		return false
	# Use the actual render frame, including shake. A small recovery margin
	# prevents flicker where the camera leaves a wall or a door frame.
	var clearance := _aim_camera_minimum_depth()+(.045 if _aim_camera_obstructed else 0.0)
	var offset := frame.origin-camera_pivot.global_position
	var lateral := offset.dot(frame.basis.x)
	var side := signf(lateral) if absf(lateral)>.01 else shoulder
	var shoulder_clearance := _aim_shoulder_clearance(Transform3D(frame.basis,camera_pivot.global_position),side)
	_aim_camera_obstructed=offset.dot(frame.basis.z)<clearance or absf(lateral)<shoulder_clearance-(.015 if _aim_camera_obstructed else .045)
	return _aim_camera_obstructed

func get_flashlight_transform() -> Transform3D:
	var mount: Transform3D=motion.get_flashlight_transform(flashlight_offset,camera.global_basis)
	# Start at the capsule axis so an animated/model-side offset cannot put
	# the source on the other side of a wall when the player stands against it.
	var safe_anchor := Vector3(global_position.x,mount.origin.y,global_position.z)
	mount.origin=_flashlight_probe.sweep(get_world_3d().direct_space_state,safe_anchor,mount.origin,.035,flashlight_collision_mask,.015)
	return mount

func get_render_camera_transform() -> Transform3D:
	_resolve_camera_collision()
	if _shot_shake_left<=0 or shot_shake_strength<=0:return camera.global_transform
	var phase := 1.0-_shot_shake_left/maxf(shot_shake_duration,.001)
	var impulse := cos(phase*TAU*1.25)*pow(1.0-phase,2)*shot_shake_strength*_shot_shake_multiplier
	var angles := Vector3(deg_to_rad(.4),deg_to_rad(.15)*_shot_shake_side,deg_to_rad(.18)*_shot_shake_side)*impulse
	var offset := Vector3(.004*_shot_shake_side,.003,.012)*impulse
	var shaken := camera.global_transform*Transform3D(Basis.from_euler(angles),offset)
	if camera_collision_enabled:
		shaken.origin=_camera_probe.sweep(get_world_3d().direct_space_state,camera_pivot.global_position,shaken.origin,_camera_probe_radius(),camera_collision_mask,camera_collision_margin)
	return shaken

func weapon_definition() -> WeaponDefinition:
	return weapon_inventory.active_definition()

func give_weapon(definition: WeaponDefinition,equip := false) -> int:
	var inventory := get_node_or_null("/root/InventoryState")
	if inventory and inventory.is_bound_player(self): return inventory.give_weapon(definition,equip)
	if not ensure_weapon_visual(definition): return -1
	var slot := weapon_inventory.add_weapon(definition)
	if equip and slot>=0:equip_weapon(slot)
	return slot

func ensure_weapon_visual(definition: WeaponDefinition) -> bool:
	if not definition or not motion or definition.id.is_empty() or definition.ammo_type.is_empty():return false
	var existed: bool=motion.weapon_slots.has(definition.id)
	var visual: Node3D=motion.prepare_weapon(definition)
	if not visual:
		push_error("Impossible de preparer l'arme : "+String(definition.id));return false
	if not existed:
		if visual.has_signal("shot_event"):visual.connect("shot_event",_on_shot_event.bind(visual))
		weapon_added.emit(visual)
	return true

func bind_weapon_inventory(value: RefCounted) -> void:
	if weapon_inventory!=value:
		if weapon_inventory.weapon_changed.is_connected(_on_weapon_changed): weapon_inventory.weapon_changed.disconnect(_on_weapon_changed)
		weapon_inventory=value
	if not weapon_inventory.weapon_changed.is_connected(_on_weapon_changed): weapon_inventory.weapon_changed.connect(_on_weapon_changed)
	for state: Dictionary in weapon_inventory.weapons: ensure_weapon_visual(state.definition)
	_on_weapon_changed()

func equip_weapon(slot: int) -> bool:
	if not enabled or controls_blocked or health<=0:return false
	return weapon_inventory.equip(slot)

func unequip_weapon() -> bool:
	if not enabled or controls_blocked or health<=0:return false
	return weapon_inventory.unequip()

func cycle_weapon(direction: int) -> bool:
	if not enabled or controls_blocked or health<=0:return false
	return weapon_inventory.cycle(direction)

func _on_weapon_changed() -> void:
	aiming=false
	_audio_settings=[];_sync_audio_levels()
	motion.blend_time=animation_blend_time
	motion.equip_weapon(weapon_definition())
	_apply_upper_body_look()
	if not weapon_definition():
		for name in ["aim","shot","reload","empty"]: AudioRouting.stop(sounds[name]); sounds[name].stream=null
		_empty_sound_variants.clear(); return
	var streams := {"aim":weapon_definition().aim_sound,"shot":weapon_definition().shot_sound,"reload":weapon_definition().reload_sound,"empty":weapon_definition().empty_sound}
	for name in streams:
		AudioRouting.stop(sounds[name])
		var stream: AudioStream=streams[name]
		sounds[name].stream=get_node("/root/PSXAudio").prepare(stream) if stream else null
	_empty_sound_variants.clear();_last_empty_variant=-1
	for source in weapon_definition().empty_sound_variants:
		if source:_empty_sound_variants.append(get_node("/root/PSXAudio").prepare(source))
	if not _empty_sound_variants.is_empty():sounds.empty.stream=_empty_sound_variants[0]

func add_ammo(ammo_type: StringName,count: int) -> int:
	var inventory := get_node_or_null("/root/InventoryState")
	if inventory and inventory.is_bound_player(self): return inventory.add_ammo(ammo_type,count)
	return weapon_inventory.add_ammo(ammo_type,count)

func shoot() -> bool:
	if not enabled or controls_blocked or health<=0 or _action_release_guard or not weapon_definition():return false
	if not weapon_inventory.try_fire():
		if weapon_inventory.action==WeaponInventory.Action.READY and shot_left<=0 and ammo<=0:
			if weapon_inventory.dry_fire():_play_empty_sound()
		return false
	motion.fire()
	_apply_upper_body_look()
	return true

func _play_empty_sound() -> void:
	if not _empty_sound_variants.is_empty():
		var count := _empty_sound_variants.size()
		var choice := randi_range(0,count-1)
		if count>1 and _last_empty_variant>=0:
			choice=randi_range(0,count-2)
			if choice>=_last_empty_variant:choice+=1
		sounds.empty.stream=_empty_sound_variants[choice];_last_empty_variant=choice
	if sounds.empty.stream:AudioRouting.play(sounds.empty)

func suppress_action_inputs_until_release() -> void:_action_release_guard=true

func action_input_blocked() -> bool:return _action_release_guard

func _action_inputs_released() -> bool:
	for action in ["aim","fire","reload","interact","heal","torch","shoulder","weapon_next","weapon_previous","weapon_slot_1","weapon_slot_2","weapon_slot_3","weapon_slot_4"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):return false
	return true

func _on_shot_event(visual: Node3D) -> void:
	if visual!=motion.weapon:return
	if not enabled or health<=0 or not weapon_definition():
		visual.deactivate()
		return
	recoil=deg_to_rad(weapon_definition().recoil_degrees)
	_shot_shake_left=shot_shake_duration
	_shot_shake_side=-_shot_shake_side
	_shot_shake_multiplier=weapon_definition().shake_multiplier
	if sounds.shot.stream:AudioRouting.play(sounds.shot)
	fired.emit(camera.global_position,-camera.global_basis.z)

func reload_weapon() -> bool:
	if not weapon_definition(): return false
	if not enabled or controls_blocked or health<=0 or not weapon_inventory.begin_reload(motion.get_reload_duration()):return false
	if sounds.reload.stream:AudioRouting.play(sounds.reload)
	motion.aim_pose.reload_return_time=reload_pose_return_time
	motion.reload_weapon()
	return true

func take_damage(amount: int) -> void:
	if invincible>0 or health<=0:
		return
	health = maxi(health-amount,0)
	if health<=0:
		weapon_inventory.cancel_reload()
		motion.cancel_reload()
		AudioRouting.stop(sounds.reload)
	invincible=invulnerability_duration
	AudioRouting.play(sounds.hurt)
	hurt.emit()
