extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var p=load("res://scenes/player.tscn").instantiate()
	root.add_child(p)
	p.set_process(false);p.set_physics_process(false)
	var m=p.motion
	var sk: Skeleton3D=m.model.get_node("rig/Skeleton3D")
	var report: Dictionary={}
	for clip in ["idle","walk","backward","strafe_left","strafe_right","forward_left","forward_right","backward_left","backward_right","run","aim","aim_walk"]:
		var samples: Array=[]
		m.upper_body.restore()
		m.mixer.play(clip,0)
		var duration: float=m.mixer.get_animation(clip).length
		var low := INF;var high := -INF;var mean := 0.0
		for frame in 121:
			var time: float=duration*frame/120
			m.mixer.seek(time,true)
			var row: Dictionary={"time":time}
			for name in ["DEF-spine","DEF-foot.L","DEF-foot.R","DEF-toe.L","DEF-toe.R"]:
				var local: Vector3=sk.get_bone_global_pose(sk.find_bone(name)).origin
				row[name]=local.y
			var height: float=row["DEF-spine"]
			low=minf(low,height);high=maxf(high,height);mean+=height
			samples.append(row)
		report[clip]={"pelvis_min":low,"pelvis_max":high,"pelvis_mean":mean/121,"samples":samples}
	FileAccess.open("res://docs/animation-heights.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for clip in report:print("CLIP_HEIGHT ",clip," ",report[clip].pelvis_min," ",report[clip].pelvis_max," ",report[clip].pelvis_mean," feet=",report[clip].samples[0]["DEF-foot.L"],"/",report[clip].samples[0]["DEF-foot.R"])
	p.queue_free()
	await process_frame
	quit()
