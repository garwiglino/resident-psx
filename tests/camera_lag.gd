extends SceneTree
var failures: Array[String]=[]
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func simulate_follow(p: Node,steps: int,delta: float) -> Transform3D:
	p.position=Vector3(0,.05,6)
	p.rotation=Vector3.ZERO
	p.pitch=0
	p.reset_camera_follow()
	p.position.x=.1
	p.look_yaw=deg_to_rad(8)
	for i in steps:
		p.update_camera_follow(delta)
	return p.camera_pivot.global_transform

func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.psx_renderer.set_process(false)
	var p=game.player
	p.set_process(false)
	p.set_physics_process(false)
	# User scene tuning may disable lag; test the feature with explicit settings.
	p.camera_translation_lag=.065
	p.camera_rotation_lag=.05
	p.camera_max_translation_lag=.22
	p.camera_max_rotation_lag_degrees=12
	p.camera_teleport_snap_distance=3
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for i in 3:
		await physics_frame
	p.camera_collision_enabled=false
	var source_y: float=p.source_offset.y
	p.position=Vector3(0,.05,6)
	p.rotation=Vector3.ZERO
	p.pitch=0
	p.reset_camera_follow()
	p.position.x=.1
	p.look_yaw=deg_to_rad(8)
	p.pitch=.08
	p.update_camera_follow(1.0/60)
	check(p.camera_pivot.global_position.x>0 and p.camera_pivot.global_position.x<.1,"Camera translation should trail the player")
	var remaining_angle: float=p._camera_follow_rotation.angle_to(p._camera_target_rotation())
	check(remaining_angle>.001 and remaining_angle<deg_to_rad(10),"Camera rotation should trail yaw and pitch")
	check(is_equal_approx(p.look_yaw,deg_to_rad(8)),"Camera lag should not delay the mouse target")
	for i in 120:
		p.update_camera_follow(1.0/60)
	check(p.camera_pivot.global_position.distance_to(p.global_position+Vector3.UP*source_y)<.001,"Camera should settle back to its original framing")
	check(p._camera_follow_rotation.angle_to(p._camera_target_rotation())<.001,"Camera rotation should settle")
	var at_60 := simulate_follow(p,6,1.0/60)
	var at_120 := simulate_follow(p,12,1.0/120)
	check(at_60.origin.distance_to(at_120.origin)<.0001,"Translation lag should be frame-rate independent")
	check(at_60.basis.get_rotation_quaternion().angle_to(at_120.basis.get_rotation_quaternion())<.001,"Rotation lag should be frame-rate independent")
	p.rotation.y=deg_to_rad(179)
	p.reset_camera_follow()
	p.look_yaw=deg_to_rad(-179)
	p.update_camera_follow(1.0/60)
	check(p._camera_follow_rotation.angle_to(p._camera_target_rotation())<deg_to_rad(2.1),"Yaw should follow the short path across +/-180 degrees")
	p.position+=Vector3(10,0,0)
	p.update_camera_follow(1.0/60)
	check(p.camera_pivot.global_position.distance_to(p.global_position+Vector3.UP*source_y)<.001,"Teleports should reset camera lag")
	p.camera_translation_lag=0
	p.camera_rotation_lag=0
	p.position.x+=.1
	p.look_yaw+=.1
	p.update_camera_follow(1.0/60)
	check(p.camera_pivot.global_position.distance_to(p.global_position+Vector3.UP*source_y)<.001,"Zero translation lag should follow immediately")
	check(p._camera_follow_rotation.angle_to(p._camera_target_rotation())<.001,"Zero rotation lag should follow immediately")
	p.camera_translation_lag=.065
	p.camera_rotation_lag=.05
	p.aiming=true
	p.position.x+=.12;p.look_yaw+=.2;p.pitch+=.1
	p.update_camera_follow(1.0/60)
	check(p.camera_pivot.global_position.distance_to(p.global_position+Vector3.UP*p._current_camera_offset().y)<.00001,"Aiming has no translation lag")
	check(p._camera_follow_rotation.angle_to(p._camera_target_rotation())<.00001,"Aiming has no rotation lag")
	p.aiming=false;p._camera_aim_weight=0
	p.camera_collision_enabled=true
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.02,3,2)
	collider.shape=shape
	wall.add_child(collider)
	wall.position=Vector3(.15,1.5,6)
	root.add_child(wall)
	p.position=Vector3(0,.05,6)
	p.rotation=Vector3.ZERO
	p.pitch=0
	p.reset_camera_follow()
	await physics_frame
	await physics_frame
	p.position.x=.4
	p.update_camera_follow(1.0/60)
	check(p.camera_pivot.global_position.x>=.295,"The lagged camera anchor should not cross a wall")
	wall.queue_free()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):
		audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	print("CAMERA_LAG_OK: translation, yaw/pitch, steady framing, frame-rate independence, angle wrap, teleport, zero lag, collision" if failures.is_empty() else "CAMERA_LAG_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
