@tool
extends CharacterBody3D

signal fired(origin: Vector3, direction: Vector3)
signal hurt
const Motion = preload("res://scripts/character_motion.gd")

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
@export var root_motion_rotation_enabled := true
## Garde la direction demandee pendant les fondus entre avant, arriere et strafes.
@export var root_motion_steer_with_input := true

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
## Suivi plus réactif en visée. 0 = aucun retard en visée, 1 = retard normal.
@export_range(0.0,1.0,.05) var camera_aim_lag_multiplier := .5
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
@export_range(1,100,1) var magazine_capacity := 12
@export_range(0,100,1) var starting_ammo := 12
@export_range(0,500,1) var starting_reserve := 24
@export_range(.05,2.0,.01,"suffix:s") var shot_interval := .28
@export_range(.1,5.0,.05,"suffix:s") var reload_duration := 1.5
@export_range(0.0,5.0,.05,"suffix:s") var invulnerability_duration := 1.2
@export_range(0.0,8.0,.05,"degrees") var recoil_degrees := 1.55
@export_range(1.0,90.0,.5,"suffix:°/s") var recoil_return_speed := 45.8
@export var flashlight_at_start := true

@export_group("Audio")
@export_range(.1,2.0,.01,"suffix:m") var walk_step_spacing := .62
@export_range(.1,2.0,.01,"suffix:m") var run_step_spacing := 1.05
@export_range(-40.0,0.0,.5,"suffix:dB") var shot_volume_db := -5.0
@export_range(-40.0,0.0,.5,"suffix:dB") var effects_volume_db := -10.0

var health := 100
var ammo := 12
var reserve := 24
var aiming := false
var flashlight := true
var enabled := false
var reload_left := 0.0
var shot_left := 0.0
var recoil := 0.0
var pitch := 0.0
var shoulder := 1.0
var step_distance := 0.0
var invincible := 0.0
var camera: Camera3D
var camera_pivot: Node3D
var arm: SpringArm3D
var visual: Node3D
var motion: Node3D
var sounds: Dictionary = {}
var source_offset := Vector3(.3564058,1.3540379,1.7886838)
var source_fov := 30.21915
var _applied_settings: Array=[]
var _camera_follow_ready := false
var _camera_follow_rotation := Quaternion.IDENTITY
var _camera_previous_player_position := Vector3.ZERO
var _camera_anchor_query: PhysicsShapeQueryParameters3D

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
		camera_pivot.position=Vector3(0,camera_offset.y,0)
	arm.spring_length=maxf(camera_offset.z,.05)
	arm.margin=camera_collision_margin
	arm.collision_mask=camera_collision_mask if camera_collision_enabled else 0
	arm.shape.radius=camera_collision_radius
	arm.position.x=shoulder*camera_offset.x
	camera.fov=camera_fov
	camera.near=camera_near
	camera.far=camera_far
	visual.get_node("CharacterMotion").scale=Vector3.ONE*model_scale
	var collider: CollisionShape3D=get_node("CollisionShape3D")
	collider.shape.radius=collision_radius
	collider.shape.height=maxf(collision_height,collision_radius*2)
	collider.position.y=collider.shape.height*.5
	if Engine.is_editor_hint():
		camera_pivot.rotation.x=deg_to_rad(initial_pitch_degrees)
	_applied_settings=[camera_offset,camera_fov,camera_near,camera_far,camera_collision_enabled,camera_collision_radius,camera_collision_margin,camera_collision_mask,collision_radius,collision_height,model_scale]

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
	health=max_health
	ammo=mini(starting_ammo,magazine_capacity)
	reserve=starting_reserve
	flashlight=flashlight_at_start
	arm.add_excluded_object(get_rid())
	_camera_anchor_query=PhysicsShapeQueryParameters3D.new()
	_camera_anchor_query.shape=arm.shape
	_camera_anchor_query.margin=.01
	_camera_anchor_query.exclude=[get_rid()]
	camera_pivot.top_level=true
	reset_camera_follow()
	camera.current = true
	for sound_name in ["shot", "step", "reload", "hurt", "pickup"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/%s.wav" % sound_name)
		audio.volume_db = shot_volume_db if sound_name == "shot" else effects_volume_db
		add_child(audio)
		sounds[sound_name] = audio

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var sensitivity := deg_to_rad(aim_mouse_sensitivity if aiming else mouse_sensitivity)
		rotation.y -= event.relative.x*sensitivity
		pitch = clampf(pitch-event.relative.y*sensitivity*(-1 if invert_y else 1),deg_to_rad(pitch_min_degrees),deg_to_rad(pitch_max_degrees))
	if event.is_action_pressed("reload"):
		reload_weapon()
	if event.is_action_pressed("torch"):
		flashlight = not flashlight
	if event.is_action_pressed("shoulder"):
		shoulder *= -1

func _physics_process(delta: float) -> void:
	shot_left = maxf(shot_left-delta,0)
	invincible = maxf(invincible-delta,0)
	if reload_left > 0:
		reload_left -= delta
		if reload_left <= 0:
			var transferred := mini(magazine_capacity-ammo,reserve)
			ammo += transferred
			reserve -= transferred
	aiming = enabled and Input.is_action_pressed("aim") and reload_left <= 0
	var axis := Input.get_vector("left","right","forward","back") if enabled else Vector2.ZERO
	var sprint := Input.is_action_pressed("sprint") and not aiming and axis.y < -0.1
	var speed := run_speed if sprint else (aim_walk_speed if aiming else walk_speed)
	var local_motion := Vector3(axis.x*strafe_speed_multiplier,0,axis.y*(backward_speed_multiplier if axis.y>0 else 1.0))
	var direction := global_basis*local_motion
	var clip := "aim" if aiming else "idle"
	if axis.length_squared()>.001:
		if aiming:clip="aim_walk"
		elif sprint:clip="run"
		elif absf(axis.x)>absf(axis.y):clip="strafe_left" if axis.x<0 else "strafe_right"
		elif axis.y>0:clip="backward"
		else:clip="walk"
	motion.mixer.active=true
	motion.play(clip if animations_enabled else "idle")
	var use_root: bool=animations_enabled and root_motion_enabled and motion.uses_root_motion()
	motion.mixer.speed_scale=root_motion_playback_speed*axis.length() if use_root else 1.0
	# Advance exactly once per physics tick; extraction removes the visible root travel.
	var root_delta: Vector3=motion.advance_motion(delta if animations_enabled else 0.0)
	var rate := acceleration if axis.length_squared()>.001 else braking
	if use_root:
		var displacement: Vector3=motion.global_basis*root_delta*root_motion_scale
		var authored_direction: Vector3=motion.global_basis*motion.root_motion_direction()
		authored_direction.y=0
		if root_motion_steer_with_input and direction.length_squared()>.0001 and authored_direction.length_squared()>.0001:
			# Extract the authored stride along its axis. Cross-fading from another
			# direction must not carry the capsule sideways against the player's input.
			displacement=direction.normalized()*maxf(displacement.dot(authored_direction.normalized()),0.0)
		velocity.x=displacement.x/delta
		velocity.z=displacement.z/delta
		if root_motion_rotation_enabled:rotation.y+=motion.mixer.get_root_motion_rotation().get_euler().y
	else:
		velocity.x = move_toward(velocity.x,direction.x*speed,delta*rate)
		velocity.z = move_toward(velocity.z,direction.z*speed,delta*rate)
	if not is_on_floor():
		velocity.y -= gravity*delta
	else:
		velocity.y = -0.1
	move_and_slide()
	var actual_speed := Vector2(get_real_velocity().x,get_real_velocity().z).length()
	step_distance += actual_speed * delta
	if step_distance > (run_step_spacing if sprint else walk_step_spacing) and is_on_floor():
		step_distance = 0
		sounds.step.pitch_scale = randf_range(0.9,1.1)
		sounds.step.play()
	visual.rotation.z = lerp(visual.rotation.z,-axis.x*deg_to_rad(strafe_lean_degrees),1-exp(-delta*8))
	if enabled and aiming and Input.is_action_pressed("fire") and shot_left <= 0:
		shoot()

func _process(delta: float) -> void:
	var settings := [camera_offset,camera_fov,camera_near,camera_far,camera_collision_enabled,camera_collision_radius,camera_collision_margin,camera_collision_mask,collision_radius,collision_height,model_scale]
	if settings!=_applied_settings:
		apply_settings()
	if Engine.is_editor_hint():
		return
	recoil = move_toward(recoil,0,delta*deg_to_rad(recoil_return_speed))
	update_camera_follow(delta)
	arm.spring_length = source_offset.z
	arm.position.x = lerpf(arm.position.x,shoulder*source_offset.x,1-exp(-delta*shoulder_switch_speed))
	camera.fov = source_fov

func _camera_target_rotation() -> Quaternion:
	return global_basis.orthonormalized().get_rotation_quaternion()*Quaternion(Vector3.RIGHT,pitch)

func reset_camera_follow() -> void:
	if not camera_pivot or Engine.is_editor_hint():
		return
	_camera_follow_rotation=_camera_target_rotation()
	camera_pivot.global_position=global_position+Vector3.UP*source_offset.y
	camera_pivot.global_basis=Basis(_camera_follow_rotation*Quaternion(Vector3.RIGHT,recoil))
	_camera_previous_player_position=global_position
	_camera_follow_ready=true

func update_camera_follow(delta: float) -> void:
	if not _camera_follow_ready or global_position.distance_to(_camera_previous_player_position)>camera_teleport_snap_distance:
		reset_camera_follow()
		return
	_camera_previous_player_position=global_position
	var target_position := global_position+Vector3.UP*source_offset.y
	var target_rotation := _camera_target_rotation()
	var multiplier := camera_aim_lag_multiplier if aiming else 1.0
	var translation_time := camera_translation_lag*multiplier
	var rotation_time := camera_rotation_lag*multiplier
	# Exponential response is independent of the render frame rate.
	var position_alpha := 1.0-exp(-delta/translation_time) if translation_time>.00001 else 1.0
	var rotation_alpha := 1.0-exp(-delta/rotation_time) if rotation_time>.00001 else 1.0
	var position := camera_pivot.global_position.lerp(target_position,position_alpha)
	var offset := (position-target_position).limit_length(camera_max_translation_lag)
	# Prevent the delayed anchor from taking a shortcut through a wall at a corner.
	if camera_collision_enabled and offset.length_squared()>.000001:
		_camera_anchor_query.collision_mask=camera_collision_mask
		_camera_anchor_query.transform=Transform3D(Basis.IDENTITY,target_position)
		_camera_anchor_query.motion=offset
		var collision := get_world_3d().direct_space_state.cast_motion(_camera_anchor_query)
		if not collision.is_empty():
			offset*=collision[0]
	camera_pivot.global_position=target_position+offset
	_camera_follow_rotation=_camera_follow_rotation.slerp(target_rotation,rotation_alpha).normalized()
	var angle := _camera_follow_rotation.angle_to(target_rotation)
	var limit := deg_to_rad(camera_max_rotation_lag_degrees)
	if angle>limit:
		_camera_follow_rotation=_camera_follow_rotation.slerp(target_rotation,1.0-limit/angle).normalized()
	# Recoil stays immediate and never feeds back into the rotation filter.
	camera_pivot.global_basis=Basis(_camera_follow_rotation*Quaternion(Vector3.RIGHT,recoil))

func shoot() -> void:
	if ammo <= 0:
		reload_weapon()
		shot_left = 0.35
		return
	ammo -= 1
	shot_left = shot_interval
	recoil = deg_to_rad(recoil_degrees)
	sounds.shot.play()
	motion.play_action("fire")
	if motion.weapon:motion.weapon.fire()
	fired.emit(camera.global_position,-camera.global_basis.z)

func reload_weapon() -> void:
	if ammo<magazine_capacity and reserve>0 and reload_left<=0:
		reload_left=reload_duration
		sounds.reload.play()
		motion.play_action("reload")
		if motion.weapon:motion.weapon.reload_weapon()

func take_damage(amount: int) -> void:
	if invincible>0 or health<=0:
		return
	health = maxi(health-amount,0)
	invincible=invulnerability_duration
	sounds.hurt.play()
	hurt.emit()
