extends SceneTree
func _initialize() -> void:
	var model=load("res://assets/character/cop_player.glb").instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D=model.get_node("rig/Skeleton3D")
	for bone in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(bone)
		if not (name.begins_with("DEF-") or name.begins_with("VTX-")):continue
		print(name," ",skeleton.get_bone_global_rest(bone).origin)
	model.queue_free()
	quit()
