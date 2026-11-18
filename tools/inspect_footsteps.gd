extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var player=load("res://scenes/player.tscn").instantiate();root.add_child(player)
	player.set_process(false);player.set_physics_process(false);player.motion.set_process(false)
	var motion=player.motion;var sk: Skeleton3D=motion.body_skeleton
	var report: Dictionary={}
	for clip in motion.WALK_DIRECTIONS+["run","idle"]:
		motion.current="";motion.blend_time=0;motion.play(clip);motion.advance_motion(0)
		var samples: Array=[]
		var duration: float=motion.mixer.get_animation(clip).length
		for tick in roundi(duration*60):
			if tick>0:motion.advance_motion(1.0/60)
			var row: Dictionary={"time":tick/60.0}
			for name in ["DEF-foot.L","DEF-foot.R","DEF-toe.L","DEF-toe.R"]:
				var bone := sk.find_bone(name)
				var transform := sk.get_bone_global_pose(bone)
				row[name]=[transform.origin.x,transform.origin.y,transform.origin.z]
				var rest := sk.get_bone_global_rest(bone)
				var sole := rest.origin;sole.y=0
				row[name+"-sole"]=(transform*(rest.affine_inverse()*sole)).y
			samples.append(row)
		report[clip]={"duration":duration,"samples":samples}
	FileAccess.open("res://docs/footstep-source-curves.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	for audio in player.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in player.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;player.queue_free();await process_frame;await create_timer(.08).timeout
	print("FOOTSTEP_SOURCE_CURVES_OK");quit()
