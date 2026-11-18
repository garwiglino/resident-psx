extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	var target=load("res://assets/character/cop_player.glb").instantiate()
	root.add_child(target)
	for player in target.find_children("*","AnimationPlayer",true,false):player.active=false
	var dst: Skeleton3D=target.get_node("rig/Skeleton3D")
	var player := AnimationPlayer.new()
	target.add_child(player);player.root_node=NodePath("..")
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	player.add_animation_library("",library)
	for clip in ["run","aim","aim_walk"]:
		var source=load("res://assets/character/%s.glb" % clip).instantiate()
		root.add_child(source)
		var src: Skeleton3D=source.get_node("rig/Skeleton3D")
		var original: AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0]
		original.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		original.play("rig",0)
		var converted: Animation=load("res://assets/character/legacy_animations/%s.res" % clip).duplicate()
		converted.loop_mode=Animation.LOOP_NONE
		library.add_animation(clip,converted)
		player.play(clip,0)
		for fraction in [0.0,.25,.5,.75,1.0]:
			var time := minf(floorf(converted.length*30*fraction)/30,converted.length-.000001)
			original.seek(time,true);player.seek(time,true)
			for b in dst.get_bone_count():
				var name := dst.get_bone_name(b)
				var old := src.find_bone(name)
				if old<0:continue
				var expected := src.get_bone_global_pose(old)*src.get_bone_global_rest(old).affine_inverse()*dst.get_bone_global_rest(b)
				var actual := dst.get_bone_global_pose(b)
				check(actual.origin.distance_to(expected.origin)<.001,"Rebased source body position: %s %s %.2f" % [clip,name,time])
				check(actual.basis.orthonormalized().get_rotation_quaternion().angle_to(expected.basis.orthonormalized().get_rotation_quaternion())<.002,"Rebased source body rotation: %s %s %.2f" % [clip,name,time])
		check(dst.get_bone_global_pose(dst.find_bone("DEF-spine")).origin.y>.85,"Pelvis stays at body height: "+clip)
		source.free()
	target.free()
	print("LEGACY_ANIMATION_OK: course and aim reproduce the original body clip in the correct parent-local coordinates" if failures.is_empty() else "LEGACY_ANIMATION_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
