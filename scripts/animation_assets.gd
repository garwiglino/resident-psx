extends RefCounted
## Read animation resources without instantiating temporary meshes and skeletons.
static func read(path: String) -> Array[Animation]:
	var packed: PackedScene=load(path)
	var state := packed.get_state()
	var animations: Array[Animation]=[]
	for node in state.get_node_count():
		if state.get_node_type(node)!="AnimationPlayer":continue
		for property in state.get_node_property_count(node):
			var resource=state.get_node_property_value(node,property)
			if not resource is AnimationLibrary:continue
			for clip in resource.get_animation_list():
				if clip!="RESET":animations.append(resource.get_animation(clip))
	return animations

## The updated coat and body use one more B-Bone segment in each upper arm.
## Older clips already animate its neighbours in the same local space.
static func complete_upper_arm_segments(animation: Animation, skeleton: Skeleton3D,
	copy_source := false) -> Animation:
	for side in ["L", "R"]:
		var prefix := "rig/Skeleton3D:SEG-DEF-upper_arm.%s.001-" % side
		var bone_name := "SEG-DEF-upper_arm.%s.001-01" % side
		if skeleton.find_bone(bone_name) < 0:
			continue
		var target := NodePath(prefix + "01")
		for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			if animation.find_track(target, type) >= 0:
				continue
			var start := animation.find_track(NodePath(prefix + "00"), type)
			if start < 0 or animation.track_get_key_count(start) == 0:
				continue
			for segment in range(2, 11):
				var end := animation.find_track(NodePath(prefix + "%02d" % segment), type)
				if end < 0 or animation.track_get_key_count(end) == 0:
					continue
				if copy_source:
					animation = animation.duplicate()
					copy_source = false
				_interpolate_segment(animation, target, type, start, end, 1.0 / segment)
				break
	return animation

static func _interpolate_segment(animation: Animation, path: NodePath, type: Animation.TrackType,
		start: int, end: int, weight: float) -> void:
	var times: Dictionary[float, bool] = {}
	for track in [start, end]:
		for key in animation.track_get_key_count(track):
			times[animation.track_get_key_time(track, key)] = true
	var track := animation.add_track(type)
	animation.track_set_path(track, path)
	animation.track_set_interpolation_type(track, animation.track_get_interpolation_type(start))
	animation.track_set_interpolation_loop_wrap(track, animation.track_get_interpolation_loop_wrap(start))
	var ordered := times.keys()
	ordered.sort()
	for time in ordered:
		match type:
			Animation.TYPE_POSITION_3D:
				var a := animation.position_track_interpolate(start, time)
				var b := animation.position_track_interpolate(end, time)
				animation.position_track_insert_key(track, time, a.lerp(b, weight))
			Animation.TYPE_ROTATION_3D:
				var a := animation.rotation_track_interpolate(start, time)
				var b := animation.rotation_track_interpolate(end, time)
				animation.rotation_track_insert_key(track, time, a.slerp(b, weight))
			Animation.TYPE_SCALE_3D:
				var a := animation.scale_track_interpolate(start, time)
				var b := animation.scale_track_interpolate(end, time)
				animation.scale_track_insert_key(track, time, a.lerp(b, weight))
