extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var model=game.player.motion.model
	model.print_tree_pretty()
	for player in model.find_children("*","AnimationPlayer",true,false):
		print("PLAYER ",player.get_path()," root=",player.root_node," active=",player.active)
		for name in player.get_animation_list():
			if name=="RESET":
				continue
			var a=player.get_animation(name)
			print("ANIM ",name," length=",a.length," first=",a.track_get_path(0))
	for s in model.find_children("*","Skeleton3D",true,false):
		print("SKELETON ",s.get_path()," basis=",s.global_basis," bones=",s.get_bone_count())
		for b in range(mini(s.get_bone_count(),5)):
			print("BONE ",b," ",s.get_bone_name(b)," pose=",s.get_bone_pose(b)," global=",s.get_bone_global_pose(b))
	game.start_game()
	for i in 3:
		await process_frame
	for s in model.find_children("*","Skeleton3D",true,false):
		print("AFTER ",s.get_path()," pose0=",s.get_bone_pose(0))
	for entry in game.psx_renderer.entries:
		if entry.node.name in ["base","slide","cop_char"]:
			print("MESH ",entry.node.name," local=",entry.node.transform," world=",entry.node.global_transform," bind0=",entry.binds[0]," indices=",entry.bind_indices)
			var bounds := AABB()
			for v in entry.vertices.size():
				var p := Vector3.ZERO
				for w in 4:
					var b: int=entry.bones[v*4+w]
					var skin_transform: Transform3D=entry.skeleton.global_transform*entry.skeleton.get_bone_global_pose(entry.bind_indices[b])*entry.binds[b]
					p+=(skin_transform*entry.vertices[v])*entry.weights[v*4+w]
				bounds=bounds.expand(p)
			print("BOUNDS ",entry.node.name," ",bounds)
	game.queue_free()
	await process_frame
	quit()
