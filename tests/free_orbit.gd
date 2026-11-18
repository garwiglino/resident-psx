extends SceneTree

const TICK := 1.0 / 60.0
var failures: Array[String] = []
var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func tick() -> void:
	player._physics_process(TICK)
	player.update_camera_follow(TICK)
	player._apply_upper_body_look()

func run() -> void:
	root.get_node("InventoryState").persist_collection = false
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.setup_input()
	game.free()
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	collision.shape = box
	floor_body.position.y = -.5
	floor_body.add_child(collision)
	root.add_child(floor_body)
	player = preload("res://scenes/player.tscn").instantiate()
	player.position.y = .05
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.enabled = true
	player.camera_collision_enabled = false
	var motion: Node3D = player.motion
	check(player.free_orbit_enabled, "The shared player scene starts in free orbit mode")
	for frame in 12:
		await physics_frame
		tick()
	var start := player.position
	for degrees in range(0, 361, 30):
		player.look_yaw = wrapf(deg_to_rad(degrees), -PI, PI)
		player.pitch = deg_to_rad(35)
		tick()
		check(absf(angle_difference(player.look_yaw, player.camera.global_rotation.y)) < .002, "The camera can complete a full orbit")
		check(is_zero_approx(player.global_rotation.y) and player.position.distance_to(start) < .001, "Orbit does not rotate or move Hitomi")
		check(not motion.turn_in_place.active and is_zero_approx(motion.upper_body.pitch) and is_zero_approx(motion.upper_body.yaw), "Idle keeps the authored torso pose")

	player.look_yaw = PI
	Input.action_press("forward")
	await physics_frame
	tick()
	check(player.position.z > start.z and motion.current == "walk", "The first input starts the forward stride in the requested world direction")
	var skeleton: Skeleton3D = motion.body_skeleton
	var head := skeleton.find_bone("DEF-spine.006")
	var posed_head := skeleton.get_bone_global_pose(head)
	motion.upper_body.restore()
	var animated_head := skeleton.get_bone_global_pose(head)
	var first_step := posed_head.basis.get_rotation_quaternion().angle_to(animated_head.basis.get_rotation_quaternion())
	var neck_step_limit := deg_to_rad(player.exploration_head_turn_speed_degrees) * TICK
	check(first_step > deg_to_rad(.25) and first_step <= neck_step_limit + .001, "The actual head starts with a small, gradual turn")
	check(is_zero_approx(player.global_rotation.y) and is_zero_approx(player._departure_torso_yaw), "The first tick keeps the torso and body facing in place")
	for frame in 4:
		player._apply_upper_body_look()
	check(skeleton.get_bone_global_pose(head).is_equal_approx(posed_head), "The head layer does not accumulate between physics ticks")
	check(motion.mixer.speed_scale < 1.0 and motion.mixer.speed_scale > 0.0, "The first stride stays short and starts immediately")
	check(absf(motion.upper_body.pitch) < deg_to_rad(3), "The torso does not snap to the high orbit angle on the first step")
	var previous_head: float = player._departure_head_yaw
	var largest_neck_step := 0.0
	var peak_look := 0.0
	for frame in 24:
		await physics_frame
		tick()
		largest_neck_step = maxf(largest_neck_step, absf(player._departure_head_yaw - previous_head))
		peak_look = maxf(peak_look, absf(player._departure_head_yaw + player._departure_torso_yaw))
		previous_head = player._departure_head_yaw
		if frame == 0:
			check(absf(player._departure_torso_yaw) > .001 and is_zero_approx(player.global_rotation.y), "The shoulders start following the head before the pelvis turns")
	check(largest_neck_step <= neck_step_limit + .001, "The neck turns and recenters at the capped speed")
	check(peak_look > deg_to_rad(8) and peak_look <= deg_to_rad(player.exploration_head_turn_degrees), "The half-turn keeps the look ahead subtle")
	check(absf(angle_difference(player.global_rotation.y, PI)) < deg_to_rad(3), "A 180-degree departure aligns within about 420 ms")
	check(absf(player.position.x - start.x) < .002, "Root travel stays on the requested direction throughout the turn")
	check(is_equal_approx(motion.mixer.speed_scale, player.root_motion_playback_speed), "An aligned walk restores authored cadence")
	check(absf(motion.upper_body.pitch) > deg_to_rad(7) and absf(motion.upper_body.pitch) <= deg_to_rad(12), "Exploration blends toward a small, clamped torso pitch")
	var returning_head := absf(player._departure_head_yaw)
	for frame in 6:
		await physics_frame
		tick()
	check(absf(player._departure_head_yaw) < minf(returning_head, deg_to_rad(2)), "The head settles into the authored walking pose as movement continues")
	Input.action_release("forward")
	Input.action_press("left")
	Input.action_press("aim")
	player.look_yaw = 0
	await physics_frame
	tick()
	check(player.aiming and is_zero_approx(player.global_rotation.y) and motion.current == "strafe_left", "Aim aligns immediately and uses the authored strafe")
	check(is_zero_approx(player._departure_head_yaw) and is_zero_approx(player._departure_torso_yaw), "Aim takes over the head and torso immediately")
	for frame in 14:
		await physics_frame
		tick()
	check(absf(absf(motion.upper_body.pitch) - deg_to_rad(35)) < .001, "Aimed torso converges to full camera pitch")
	Input.action_release("aim")
	Input.action_release("left")
	player.look_yaw = PI / 2
	player.pitch = -deg_to_rad(40)
	await physics_frame
	tick()
	check(is_zero_approx(player.global_rotation.y) and motion.upper_body.pitch < 0.0, "Leaving aim preserves the old torso pitch during fade and frees the orbit")
	for frame in 34:
		await physics_frame
		tick()
	check(absf(motion.upper_body.pitch) < .01 and not motion.turn_in_place.active, "The idle torso returns to neutral without starting a turn")
	player.look_yaw = 0
	Input.action_press("forward")
	Input.action_press("right")
	Input.action_press("sprint")
	for frame in 20:
		await physics_frame
		tick()
	check(motion.current == "run" and absf(angle_difference(player.global_rotation.y, -PI / 4)) < .01, "Diagonal run faces its actual heading")
	check(player._camera_follow_rotation.angle_to(player._camera_target_rotation()) < .001, "The running camera has no lag or forced yaw")
	var body_yaw := player.global_rotation.y
	var clip_time: float = motion.mixer.current_animation_position
	player.look_yaw += .45
	player.update_camera_follow(TICK / 2.0)
	check(absf(angle_difference(body_yaw, player.global_rotation.y) - .45) < .001, "Mouse yaw still follows immediately while running")
	check(is_equal_approx(motion.mixer.current_animation_position, clip_time), "Render updates never advance the run animation")
	check(absf(motion.upper_body.pitch) < .01, "The run preserves its authored torso pitch")
	Input.action_release("forward")
	Input.action_release("right")
	Input.action_release("sprint")
	check(player.unequip_weapon(), "Hitomi can holster the pistol in exploration")
	Input.action_press("back")
	for frame in 21:
		await physics_frame
		tick()
	check(motion.current == "unarmed_walk" and absf(angle_difference(player.global_rotation.y, player.look_yaw + PI)) < .04, "Unarmed back input turns and walks toward the camera")
	Input.action_release("back")
	await physics_frame
	tick()
	var run_start := player.position
	var toward_camera := Basis(Vector3.UP, player.look_yaw) * Vector3.BACK
	Input.action_press("back")
	Input.action_press("sprint")
	for frame in 24:
		await physics_frame
		tick()
	var run_travel := player.position - run_start
	run_travel.y = 0.0
	check(motion.current == "unarmed_run" and run_travel.dot(toward_camera) > .8, "Shift plus back jogs toward the camera using forward root motion")
	check((-player.global_basis.z).dot(toward_camera) > .998, "The body faces the camera when jogging toward it")
	Input.action_release("back")
	Input.action_release("sprint")
	player.look_yaw = player.global_rotation.y
	await physics_frame
	tick()
	for frame in 16:
		player._update_body_orientation(Vector2.ZERO, TICK)
	var original_yaw := player.global_rotation.y
	player._update_body_orientation(Vector2.RIGHT, TICK)
	check(player._departure_head_yaw < -deg_to_rad(.25) and is_zero_approx(angle_difference(original_yaw, player.global_rotation.y)), "A right departure anticipates in the same direction as the upcoming body turn")
	player._update_body_orientation(Vector2.ZERO, TICK)
	for frame in 16:
		player._update_body_orientation(Vector2.ZERO, TICK)
	player._update_body_orientation(Vector2.LEFT, TICK)
	check(player._departure_head_yaw > deg_to_rad(.25) and is_zero_approx(angle_difference(original_yaw, player.global_rotation.y)), "A left departure uses the opposite neck turn")
	player.queue_free()
	floor_body.queue_free()
	await process_frame
	print("FREE_ORBIT_OK" if failures.is_empty() else "FREE_ORBIT_FAILED " + str(failures))
	quit(0 if failures.is_empty() else 1)
