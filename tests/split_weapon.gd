extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.psx_renderer.set_process(false)
	var p=game.player
	p.set_process(false)
	p.set_physics_process(false)
	p.motion.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	await create_timer(.1).timeout
	var motion=p.motion
	var weapon=motion.weapon
	var skeleton: Skeleton3D=motion.model.get_node("rig/Skeleton3D")
	check(skeleton.find_bone("RootMotion")>=0 and skeleton.find_bone("root")<0,"Player exports a game skeleton without Rigify controls")
	check(weapon.skeleton.get_bone_count()==5,"Weapon keeps all bones including the muzzle helper")
	check(not motion.model.has_node("gun_amature"),"Player GLB must not embed the weapon")
	check(motion.hand_attachment.bone_name=="DEF-hand.R","Weapon attaches to exported right hand")
	check(weapon.mixer!=motion.mixer,"Player and weapon have separate AnimationPlayers")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/split-export-player_pistol_idle.json"))
	var base_metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/cop_player.json"))
	var measurements: Array[Dictionary]=[]
	for sample in reference.samples:
		motion.mixer.play("player_pistol_idle")
		motion.mixer.seek(sample.time,true)
		weapon.mixer.play("pistol_idle")
		weapon.mixer.seek(sample.time,true)
		motion.hand_attachment.on_skeleton_update()
		var inverse_model: Transform3D=motion.model.global_transform.affine_inverse()
		for entry in game.psx_renderer.entries:
			var name: String=entry.node.name
			# The updated base has different body geometry. Its Blender fidelity
			# is checked against cop_base.blend in tests/face_expressions.gd.
			if name=="cop_char" and base_metadata.get("base_mesh_only",false):continue
			if not sample.meshes.has(name):continue
			var expected: PackedVector3Array=[]
			for xyz in sample.meshes[name]:expected.append(Vector3(xyz[0],xyz[1],xyz[2]))
			var sk: Skeleton3D=entry.skeleton
			var transforms: Array[Transform3D]=[]
			for b in entry.binds.size():transforms.append(inverse_model*sk.global_transform*sk.get_bone_global_pose(entry.bind_indices[b])*entry.binds[b])
			var max_error := 0.0
			var sum_error := 0.0
			for v in entry.vertices.size():
				var actual := Vector3.ZERO
				var stride: int=entry.bones.size()/entry.vertices.size()
				for w in stride:
					var weight: float=entry.weights[v*stride+w]
					if weight>0:actual+=(transforms[entry.bones[v*stride+w]]*entry.vertices[v])*weight
				var closest := INF
				for point in expected:closest=minf(closest,actual.distance_squared_to(point))
				var error := sqrt(closest)
				max_error=maxf(max_error,error)
				sum_error+=error
			measurements.append({"frame":sample.frame,"mesh":name,"max_error_m":max_error,"mean_error_m":sum_error/entry.vertices.size()})
			check(max_error<.001,"Export must reproduce Blender within 1mm: %s frame %s error %.6f m" % [name,sample.frame,max_error])
	# A local slide animation must not move the hand or the magazine.
	var gun_skeleton: Skeleton3D=weapon.skeleton
	var slide := gun_skeleton.find_bone("b_slide")
	var magazine := gun_skeleton.find_bone("b_mag")
	var hand := skeleton.find_bone("DEF-hand.R")
	var hand_before := skeleton.get_bone_global_pose(hand)
	var magazine_before := gun_skeleton.get_bone_pose(magazine)
	var slide_before := gun_skeleton.get_bone_pose_position(slide)
	var test_animation := Animation.new()
	test_animation.length=1
	var track := test_animation.add_track(Animation.TYPE_POSITION_3D)
	test_animation.track_set_path(track,NodePath(String(weapon.model.get_path_to(gun_skeleton))+":b_slide"))
	test_animation.position_track_insert_key(track,0,slide_before)
	test_animation.position_track_insert_key(track,1,slide_before+Vector3(0,.02,0))
	weapon.mixer.get_animation_library("").add_animation("test_slide_independence",test_animation)
	weapon.mixer.play("test_slide_independence",0)
	weapon.mixer.seek(1,true)
	check(gun_skeleton.get_bone_pose_position(slide).distance_to(slide_before)>.019,"Weapon slide can animate locally")
	check(skeleton.get_bone_global_pose(hand).is_equal_approx(hand_before),"Weapon animation must not affect player hand")
	check(gun_skeleton.get_bone_pose(magazine).is_equal_approx(magazine_before),"Slide animation must not affect magazine")
	FileAccess.open("res://docs/split-validation.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	print("SPLIT_WEAPON_OK: separate rigs, hand socket, source geometry at five frames, independent mechanical animation" if failures.is_empty() else "SPLIT_WEAPON_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
