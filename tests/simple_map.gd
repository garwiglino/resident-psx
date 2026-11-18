extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func travel(player: CharacterBody3D,target: Vector3) -> void:
	for tick in 360:
		await physics_frame
		var offset := target-player.position
		offset.y=0
		if offset.length()<.06:return
		player.velocity=offset.limit_length(.10)*60
		player.velocity.y=-.1 if player.is_on_floor() else player.velocity.y-.3
		player.move_and_slide()
	check(false,"Blocked route to room: "+str(target)+" reached "+str(player.position))

func run() -> void:
	root.disable_3d=true
	var level=load("res://scenes/couloir_pieces.tscn").instantiate()
	root.add_child(level)
	var player=load("res://scenes/player.tscn").instantiate()
	player.position=level.get_node("Gameplay/PlayerSpawn").position
	root.add_child(player)
	player.set_physics_process(false)
	var parts: Dictionary={}
	var triangles := 0
	for node in level.find_children("*","Node3D",true,false):
		if node.has_meta("source_module"):parts[node.get_meta("source_module")]=true
	for mesh in level.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():triangles+=mesh.mesh.surface_get_array_index_len(surface)/3
	for name in ["wall_straight","floor_tile","ceiling_tile","corner_inner","corner_outer","wall_door_frame","door"]:
		check(parts.has(name),"Map uses supplied module: "+name)
	check(triangles<5000,"Static map stays within its geometry budget")
	for tick in 3:await physics_frame
	for marker in level.get_node("Gameplay").get_children():
		var position: Vector3=marker.global_position
		var ray := PhysicsRayQueryParameters3D.create(Vector3(position.x,.8,position.z),Vector3(position.x,-.5,position.z),1)
		var hit: Dictionary=level.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y)<.01,"Gameplay marker is above reachable floor: "+String(marker.name))
	# Enter and leave both side rooms through their opened doors, then reach the end room.
	for target in [Vector3(0,0,-5),Vector3(-5,0,-5),Vector3(0,0,-5),Vector3(0,0,-13),Vector3(5,0,-13),Vector3(0,0,-13),Vector3(0,0,-26)]:
		await travel(player,target)
	for tick in 60:
		await physics_frame
		player.velocity=Vector3(0,-.1,-3)
		player.move_and_slide()
	check(player.position.z> -27.84,"Closed exit door blocks the capsule")
	player.position=Vector3(0,.02,0)
	for tick in 60:
		await physics_frame
		player.velocity=Vector3(3,-.1,0)
		player.move_and_slide()
	check(player.position.x<1.77,"Corridor walls block the capsule")
	FileAccess.open("res://docs/simple-map-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"modules":parts.keys(),"static_triangles":triangles,"failures":failures},"\t"))
	for audio in player.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	player.queue_free()
	level.queue_free()
	await process_frame
	print("SIMPLE_MAP_OK: supplied modules, floors, both doorways, connected rooms, corridor and exit collisions" if failures.is_empty() else "SIMPLE_MAP_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
