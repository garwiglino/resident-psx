extends SceneTree
const Lower=preload("res://scripts/lower_body_turn.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game)
	game.set_process(false);game.psx_renderer.set_process(false)
	var p=game.player
	p.set_process(false);p.set_physics_process(false)
	p.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	await create_timer(.1).timeout
	var m=p.motion
	var sk: Skeleton3D=m.model.get_node("rig/Skeleton3D")
	var pelvis := sk.find_bone("DEF-spine")
	var measurements: Dictionary={}
	var references: Dictionary={}
	for file in JSON.parse_string(FileAccess.get_file_as_string("res://docs/locomotion-blender-audit.json")):
		if "harmonized" in file.source:continue
		for clip in file.clips:references[clip.clip]=clip
	var lower: Array[int]=[]
	for bone in sk.get_bone_count():
		var name := String(sk.get_bone_name(bone))
		if Lower.includes_bone(name) and not Lower.is_waist(name):lower.append(bone)
	m._restore_pose_layers();m.turn_in_place.cancel();m.turn_in_place.weight=0
	var global_position_error := 0.0;var global_basis_error := 0.0
	for clip in ["idle","walk","backward","strafe_left","strafe_right","forward_left","forward_right","backward_left","backward_right"]:
		var meta: Dictionary=m.clip_metadata[clip]
		check(not "harmonized" in meta.source and meta.source.begins_with("C:\\Users\\sheensaw\\Downloads\\"),"Installed clip comes directly from the original Blender source: "+clip)
		var animation: Animation=m.mixer.get_animation(clip)
		var rows: Array[Dictionary]=[]
		for aiming in [false,true]:
			m._restore_pose_layers();m.current="";m.blend_time=0;m.set_aiming(aiming,0);m.play(clip)
			var sum := 0.0;var bottom := INF;var top := -INF;var knees := 0.0;var position_error := 0.0;var basis_error := 0.0
			for frame in 120:
				if frame>0:m.advance_motion(animation.length/120)
				m.apply_look(Vector3(.3,.2,-1).normalized(),deg_to_rad(55),deg_to_rad(50),true)
				var at: float=m.mixer.current_animation_position
				for bone in lower:
					var path := NodePath("rig/Skeleton3D:"+sk.get_bone_name(bone))
					var expected := sk.get_bone_rest(bone)
					var pt := animation.find_track(path,Animation.TYPE_POSITION_3D);var rt := animation.find_track(path,Animation.TYPE_ROTATION_3D);var st := animation.find_track(path,Animation.TYPE_SCALE_3D)
					if pt>=0:expected.origin=animation.position_track_interpolate(pt,at)
					var rotation: Quaternion=animation.rotation_track_interpolate(rt,at) if rt>=0 else expected.basis.get_rotation_quaternion()
					var scale: Vector3=animation.scale_track_interpolate(st,at) if st>=0 else expected.basis.get_scale()
					expected.basis=Basis(rotation).scaled_local(scale)
					var actual := sk.get_bone_pose(bone)
					position_error=maxf(position_error,actual.origin.distance_to(expected.origin))
					for axis in 3:basis_error=maxf(basis_error,actual.basis[axis].distance_to(expected.basis[axis]))
				var height := sk.get_bone_global_pose(pelvis).origin.y
				sum+=height;bottom=minf(bottom,height);top=maxf(top,height)
				for side in ["L","R"]:
					var hip := sk.get_bone_global_pose(sk.find_bone("DEF-thigh."+side)).origin
					var knee := sk.get_bone_global_pose(sk.find_bone("DEF-shin."+side)).origin
					var ankle := sk.get_bone_global_pose(sk.find_bone("DEF-foot."+side)).origin
					knees+=180-rad_to_deg((hip-knee).angle_to(ankle-knee))
			var mean := sum/120
			var source: Dictionary=references[meta.clip]
			check(absf(mean-float(source.pelvis_mean_m))<.001,"Runtime pelvis height follows its own Blender clip, without flattening: "+clip)
			check(position_error<.00002 and basis_error<.00002,"Pelvis and legs preserve every source translation, rotation and scale after aim/look: "+clip+" aim="+str(aiming))
			check(absf(knees/240-float(source.deform_knee_mean_degrees))<.6,"Knee bending matches the same DEF anchors in Blender rather than an imposed minimum: "+clip)
			global_position_error=maxf(global_position_error,position_error);global_basis_error=maxf(global_basis_error,basis_error)
			rows.append({"aiming":aiming,"mean":mean,"minimum":bottom,"maximum":top,"blender_mean":source.pelvis_mean_m,"knee_mean_degrees":knees/240,"blender_knee_mean_degrees":source.deform_knee_mean_degrees,"position_error_m":position_error,"basis_error":basis_error})
		measurements[clip]={"source":meta.source,"samples":rows}
	FileAccess.open("res://docs/pelvis-runtime-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"clips":measurements,"maximum_position_error_m":global_position_error,"maximum_basis_error":global_basis_error,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout
	game.queue_free();await process_frame
	print("PELVIS_RUNTIME_OK: nine original Blender clips, full pelvis/leg translations rotations and scales after aim/look, source knee bending and no forced common height" if failures.is_empty() else "PELVIS_RUNTIME_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
