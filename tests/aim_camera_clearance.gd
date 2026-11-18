extends SceneTree

const TICK := 1.0 / 60.0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func wall(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.position = position
	body.add_child(collider)
	parent.add_child(body)
	return body

func run() -> void:
	root.get_node("InventoryState").persist_collection = false
	var game := (load("res://scenes/systemes_jeu.tscn") as PackedScene).instantiate()
	var map := Node3D.new()
	map.name = "Map"
	game.add_child(map)
	wall(map, Vector3(0, -.5, 0), Vector3(12, 1, 12))
	var rear_wall := wall(map, Vector3(0, 1.5, .30), Vector3(12, 3, .04))
	root.add_child(game)
	var player: CharacterBody3D = game.player
	var renderer: Node2D = game.psx_renderer
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	renderer.set_process(false)
	player.position = Vector3(0, .04, 0)
	player.reset_camera_follow()
	await physics_frame
	await physics_frame
	Input.action_press("aim")
	Input.action_press("back")
	player._physics_process(TICK)
	check(player.position.z > .01 and player.motion.current == "backward", "Aim can still back up with the authored root motion")
	var center: Vector3 = player.global_position + Vector3.UP * player._current_camera_offset().y
	check(player.camera_pivot.global_position.is_equal_approx(center), "The camera anchor follows the post-move position in the same tick")
	var frame: Transform3D = player.get_render_camera_transform()
	check(player.should_hide_aim_meshes(frame) and frame.origin.z < .28, "A rear wall triggers close framing without moving the camera through the wall")
	check(renderer._local_aim_meshes.size() > 4 and renderer._local_aim_meshes.any(func(mesh: MeshInstance3D): return player.motion.weapon.model.is_ancestor_of(mesh)), "Body, clothing and held weapon take part in close-camera protection")
	var head: MeshInstance3D = player.motion.body_skeleton.get_node("cop_hair")
	var transitions: Array[bool] = []
	head.visibility_changed.connect(func(): transitions.append(head.visible))
	var atlas: Texture2D = renderer.atlas_texture
	renderer._process(0)
	check(transitions == [false, true] and head.visible, "The close view excludes the local mesh for its render pass and immediately restores visibility")
	check(renderer.atlas_texture == atlas, "The camera fallback does not rebuild the PSX atlas")
	var fixed := Camera3D.new()
	game.add_child(fixed)
	fixed.position = Vector3(0, 1.3, -3)
	fixed.look_at(Vector3(0, 1.3, 0))
	renderer.set_active_camera(fixed)
	transitions.clear()
	renderer._process(0)
	check(transitions.is_empty(), "A cinematic camera still sees Hitomi")
	renderer.set_active_camera(player.camera)
	Input.action_release("back")
	rear_wall.queue_free()
	await physics_frame
	await physics_frame
	player.look_yaw = deg_to_rad(35)
	player.update_camera_follow(TICK)
	check(absf(angle_difference(player.global_rotation.y, player.look_yaw)) < .001, "Mouse turns during aim align camera and body on the render frame")
	transitions.clear()
	renderer._process(0)
	check(transitions.is_empty() and not player.should_hide_aim_meshes(player.get_render_camera_transform()), "The shoulder view restores Hitomi as soon as there is room")
	for direction in ["left", "right"]:
		for side in [-1.0, 1.0]:
			player.position = Vector3(0, .04, 0)
			player.global_rotation.y = 0.0
			player.reset_camera_follow()
			player.shoulder = side
			player.update_camera_follow(.5)
			Input.action_press(direction)
			for i in 8:
				await physics_frame
				player._physics_process(TICK)
				frame = player.get_render_camera_transform()
				var offset: Vector3 = frame.origin - player.camera_pivot.global_position
				check(offset.dot(frame.basis.x) * side >= .25 and not player.should_hide_aim_meshes(frame), "Open-space aimed strafe keeps the selected shoulder and Hitomi visible")
			Input.action_release(direction)
			check(player.motion.current == "strafe_" + direction, "The aimed strafe still plays its own locomotion clip")
	player.position = Vector3(0, .04, 0)
	player.global_rotation.y = 0.0
	player.reset_camera_follow()
	player.shoulder = 1.0
	wall(map, Vector3(.28, 1.5, 0), Vector3(.04, 3, 5))
	Input.action_press("right")
	for i in 8:
		await physics_frame
		player._physics_process(TICK)
		player.update_camera_follow(TICK)
	frame = player.get_render_camera_transform()
	check(frame.origin.z - player.position.z > .6 and frame.origin.x < .26, "A side wall can center the camera while preserving safe rear distance")
	check(player.should_hide_aim_meshes(frame), "A wall-forced centered strafe view clears Hitomi from the reticle")
	Input.action_release("right")
	Input.action_release("aim")
	for audio in game.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	game.queue_free()
	await process_frame
	print("AIM_CAMERA_CLEARANCE_OK" if failures.is_empty() else "AIM_CAMERA_CLEARANCE_FAILED " + str(failures))
	quit(0 if failures.is_empty() else 1)
