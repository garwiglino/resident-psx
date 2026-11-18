extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.psx_renderer.set_process(false)
	var p=game.player
	p.set_physics_process(false)
	# Let the audio backend register the ambient stream before the short test exits.
	await create_timer(.1).timeout
	var m=p.motion
	m.mixer.root_motion_track=NodePath("")
	var measurements: Array=[]
	for clip in ["player_run_pistol","player_walk_forward_pistol","player_walk_backward_pistol","player_walk_strafe_left_pistol","player_walk_strafe_right_pistol",
		"player_walk_forward_left_pistol","player_walk_forward_right_pistol","player_walk_backward_left_pistol","player_walk_backward_right_pistol"]:
		# Inspect the authored endpoint, rather than wrapping it to the next loop.
		m.mixer.get_animation(clip).loop_mode=Animation.LOOP_NONE
		var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/split-export-%s.json" % clip))
		for sample in reference.samples:
			m.mixer.play(clip,0)
			m.mixer.seek(sample.time,true)
			var inverse_model: Transform3D=m.model.global_transform.affine_inverse()
			for entry in game.psx_renderer.entries:
				if entry.node.name!="cop_char":continue
				var expected: PackedVector3Array=[]
				for xyz in sample.meshes.cop_char:expected.append(Vector3(xyz[0],xyz[1],xyz[2]))
				var transforms: Array[Transform3D]=[]
				for b in entry.binds.size():transforms.append(inverse_model*entry.skeleton.global_transform*entry.skeleton.get_bone_global_pose(entry.bind_indices[b])*entry.binds[b])
				var stride: int=entry.bones.size()/entry.vertices.size()
				var max_error := 0.0
				for v in entry.vertices.size():
					var actual := Vector3.ZERO
					for w in stride:
						var weight: float=entry.weights[v*stride+w]
						if weight>0:actual+=(transforms[entry.bones[v*stride+w]]*entry.vertices[v])*weight
					var closest := INF
					for point in expected:closest=minf(closest,actual.distance_squared_to(point))
					max_error=maxf(max_error,sqrt(closest))
				measurements.append({"clip":clip,"frame":sample.frame,"max_error_m":max_error})
				if max_error>.001:failures.append("%s frame %s: %.6f m" % [clip,sample.frame,max_error])
	FileAccess.open("res://docs/walk-export-validation.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"\t"))
	print("WALK_EXPORT_OK: eight walks and the run strip reproduce Blender geometry within 1mm" if failures.is_empty() else "WALK_EXPORT_FAILED "+str(failures))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
