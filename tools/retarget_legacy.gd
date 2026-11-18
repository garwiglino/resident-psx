extends SceneTree
# Preserve the prototype's existing clips when moving to the flattened game skeleton.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/character/legacy_animations")
	var target=load("res://assets/character/cop_player.glb").instantiate()
	root.add_child(target)
	var dst: Skeleton3D=target.get_node("rig/Skeleton3D")
	for clip in ["walk","backward","strafe_left","strafe_right","run","aim","aim_walk"]:
		var source=load("res://assets/character/%s.glb" % clip).instantiate()
		root.add_child(source)
		var src: Skeleton3D=source.get_node("rig/Skeleton3D")
		var body: MeshInstance3D=source.find_child("cop_char",true,false)
		var arrays := body.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int=bones.size()/vertices.size()
		var overflow_vertices: Dictionary={}
		for b in dst.get_bone_count():
			if not dst.get_bone_name(b).begins_with("VTX-"):continue
			var point := dst.get_bone_global_rest(b).origin
			var closest := 0
			for v in vertices.size():
				if vertices[v].distance_squared_to(point)<vertices[closest].distance_squared_to(point):closest=v
			overflow_vertices[b]=closest
		var player: AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0]
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		# These old GLBs also contain the weapon clip, sorted before the body.
		var name := "rig"
		assert(player.has_animation(name),"Missing original body animation: "+clip)
		player.play(name,0)
		var animation := Animation.new()
		animation.length=player.get_animation(name).length
		animation.loop_mode=Animation.LOOP_LINEAR
		var tracks: Array=[]
		for b in dst.get_bone_count():
			var row: Array=[]
			for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
				var track := animation.add_track(type)
				animation.track_set_path(track,NodePath("rig/Skeleton3D:"+dst.get_bone_name(b)))
				row.append(track)
			tracks.append(row)
		var frames := ceili(animation.length*30)
		for f in frames+1:
			var time := minf(float(f)/30,animation.length-.000001)
			player.seek(time,true)
			var global_poses: Array[Transform3D]=[]
			for b in dst.get_bone_count():
				var bone_name := dst.get_bone_name(b)
				var pose := dst.get_bone_global_rest(b)
				var original := src.find_bone(bone_name)
				var parent := dst.get_bone_parent(b)
				if original>=0:
					pose=src.get_bone_global_pose(original)*src.get_bone_global_rest(original).affine_inverse()*dst.get_bone_global_rest(b)
				elif overflow_vertices.has(b):
					var vertex: int=overflow_vertices[b]
					var point := Vector3.ZERO
					for w in stride:
						var bind: int=bones[vertex*stride+w]
						var bone_index := body.skin.get_bind_bone(bind)
						if bone_index<0:bone_index=src.find_bone(body.skin.get_bind_name(bind))
						point+=(src.get_bone_global_pose(bone_index)*body.skin.get_bind_pose(bind)*vertices[vertex])*weights[vertex*stride+w]
					pose.origin=point
				elif parent>=0:
					pose=global_poses[parent]*dst.get_bone_global_rest(parent).affine_inverse()*pose
				global_poses.append(pose)
				# Animation tracks store parent-local transforms. DEF anchors are
				# under RootMotion, while SEG joints are under their DEF anchor.
				if parent>=0:pose=global_poses[parent].affine_inverse()*pose
				animation.position_track_insert_key(tracks[b][0],time,pose.origin)
				animation.rotation_track_insert_key(tracks[b][1],time,pose.basis.orthonormalized().get_rotation_quaternion())
				animation.scale_track_insert_key(tracks[b][2],time,pose.basis.get_scale())
		assert(ResourceSaver.save(animation,"res://assets/character/legacy_animations/%s.res" % clip)==OK)
		source.free()
	target.free()
	print("LEGACY_RETARGET_OK")
	quit()
