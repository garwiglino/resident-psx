extends SceneTree
var failures: Array[String]=[]
var rows: Array=[]
func _initialize() -> void:call_deferred("run")
func capture(m: Node) -> Dictionary:
	var result := {}
	for bone in m.body_skeleton.get_bone_count():
		var name: String=m.body_skeleton.get_bone_name(bone)
		if not ("forearm.R" in name or "upper_arm.R" in name or "hand.R" in name):continue
		result[name]=m.body_skeleton.get_bone_pose_rotation(bone)
	return result
func sample(m: Node,clip: String,time: float) -> Array:
	m.current="";m.blend_time=0;m.play(clip);m.advance_motion(time)
	var result: Array=[capture(m)]
	for frame in 30:m.advance_motion(1.0/120);result.append(capture(m))
	return result
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var p=load("res://scenes/player.tscn").instantiate();root.add_child(p)
	p.set_physics_process(false);p.set_process(false)
	var m=p.motion;m.set_process(false)
	if "--original" in OS.get_cmdline_user_args():
		var source=load("res://assets/character/cop_player.glb").instantiate()
		var skeleton: Skeleton3D=source.get_node("rig/Skeleton3D")
		for name in ["DEF-upper_arm.R","DEF-forearm.R","DEF-upper_arm.L","DEF-forearm.L"]:
			var bone: int=m.body_skeleton.find_bone(name)
			m.body_skeleton.set_bone_rest(bone,skeleton.get_bone_rest(bone))
		m.mixer.clear_caches();source.free()
	for pair in [["run","walk"],["walk","run"],["run","idle"]]:
		var incoming := sample(m,pair[1],0)
		for phase in 24:
			var time: float=m.mixer.get_animation(pair[0]).length*phase/24.0
			var outgoing := sample(m,pair[0],time)
			m.current="";m.blend_time=0;m.play(pair[0]);m.advance_motion(time)
			m.blend_time=.25;m.play(pair[1])
			var error := {};var peak_step := {};var previous := capture(m)
			for frame in 31:
				if frame>0:m.advance_motion(1.0/120)
				var actual := capture(m)
				for name in actual:
					var expected: Quaternion=outgoing[frame][name].slerp(incoming[frame][name],frame/30.0)
					error[name]=maxf(error.get(name,0),rad_to_deg(actual[name].angle_to(expected)))
					peak_step[name]=maxf(peak_step.get(name,0),rad_to_deg(actual[name].angle_to(previous[name])))
				previous=actual
			rows.append({"from":pair[0],"to":pair[1],"phase":phase,"error_degrees":error,"peak_step_degrees":peak_step})
			for name in error:
				if "forearm.R" in name and error[name]>2:failures.append("Forearm unwinds %s %s->%s phase %d: %.2f" % [name,pair[0],pair[1],phase,error[name]])
	FileAccess.open("res://docs/run-walk-blend%s.json" % ("-before" if "--original" in OS.get_cmdline_user_args() else "-validation"),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failures":failures},"\t"))
	p.queue_free();await process_frame
	print("RUN_WALK_BLEND_OK" if failures.is_empty() else "RUN_WALK_BLEND_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
