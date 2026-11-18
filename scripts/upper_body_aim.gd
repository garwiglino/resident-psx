extends RefCounted
## Authored aiming pose following pelvis translation over unchanged locomotion.
## During an authored turn it also rides the chest motion, before mouse look.
var skeleton: Skeleton3D
var pelvis := -1
var entries: Array[Dictionary]=[]
var base_poses: Dictionary={}
var applied := false
var requested := false
var weight := 0.0
var blend_time := .18
var fire_frames: Array[Array]=[]
var fire_fps := 24.0
var fire_length := 0.0
var fire_time := -1.0
var fire_return_time := .06
var reload_frames: Array[Array]=[]
var reload_fps := 24.0
var reload_length := 0.0
var reload_time := -1.0
var reload_blend_time := .06
var reload_return_time := .24
var _reload_weight := 0.0
var _release_left := 0.0
var _release_duration := 0.0
var _release_aim := 0.0
var _release_reload := 0.0

func setup(target: Skeleton3D,pose: Animation,anchors: Array[int]) -> void:
	skeleton=target
	pelvis=skeleton.find_bone("DEF-spine")
	if pelvis<0 or not pose:return
	var source := _sample_source(pose,0)
	var included: Array[int]=[]
	for bone in skeleton.get_bone_count():
		var ancestor := bone
		while ancestor>=0 and ancestor not in anchors:ancestor=skeleton.get_bone_parent(ancestor)
		if ancestor>=0:included.append(bone)
	# Finger anchors are flattened in the exported rig. Blend them relative
	# to the hand so the grip remains coherent while the pistol is raised.
	var parents: Dictionary={}
	for bone in included:
		var name := String(skeleton.get_bone_name(bone))
		var parent := skeleton.get_bone_parent(bone)
		if name.begins_with("DEF-f_") or name.begins_with("DEF-thumb") or name.begins_with("DEF-palm"):
			parent=skeleton.find_bone("DEF-hand.R" if ".R" in name else "DEF-hand.L")
		parents[bone]=parent if parent in included else pelvis
	while not included.is_empty():
		for index in range(included.size()-1,-1,-1):
			var bone := included[index]
			var parent: int=parents[bone]
			if parent in included:continue
			var reference: Transform3D=source[parent]
			if parent==pelvis:reference.basis=Basis.IDENTITY
			entries.append({"bone":bone,"parent":parent,"pose":reference.affine_inverse()*source[bone]})
			included.remove_at(index)

func _sample_source(pose: Animation,time: float) -> Dictionary:
	var source: Dictionary={}
	var pending: Array[int]=[]
	for bone in skeleton.get_bone_count():pending.append(bone)
	while not pending.is_empty():
		for index in range(pending.size()-1,-1,-1):
			var bone := pending[index]
			var parent := skeleton.get_bone_parent(bone)
			if parent>=0 and not source.has(parent):continue
			var path := NodePath("rig/Skeleton3D:"+skeleton.get_bone_name(bone))
			var local := skeleton.get_bone_rest(bone)
			var position_track := pose.find_track(path,Animation.TYPE_POSITION_3D)
			var rotation_track := pose.find_track(path,Animation.TYPE_ROTATION_3D)
			var scale_track := pose.find_track(path,Animation.TYPE_SCALE_3D)
			if position_track>=0:local.origin=pose.position_track_interpolate(position_track,time)
			var rotation := pose.rotation_track_interpolate(rotation_track,time) if rotation_track>=0 else local.basis.get_rotation_quaternion()
			var scale := pose.scale_track_interpolate(scale_track,time) if scale_track>=0 else local.basis.get_scale()
			local.basis=Basis(rotation).scaled_local(scale)
			source[bone]=source[parent]*local if parent>=0 else local
			pending.remove_at(index)
	return source

func setup_fire(animation: Animation,fps: float) -> void:
	if not animation:return
	fire_length=animation.length;fire_fps=fps
	fire_frames=_action_frames(animation,fps)

func setup_reload(animation: Animation,fps: float) -> void:
	reload_frames.clear();reload_time=-1.0;reload_length=0.0
	if not animation:return
	reload_length=animation.length;reload_fps=fps
	reload_frames=_action_frames(animation,fps)

func _action_frames(animation: Animation,fps: float) -> Array[Array]:
	var frames: Array[Array]=[]
	for frame in ceili(animation.length*fps)+1:
		var source := _sample_source(animation,minf(frame/fps,animation.length))
		var poses: Array=[]
		for entry in entries:
			var reference: Transform3D=source[entry.parent]
			if entry.parent==pelvis:reference.basis=Basis.IDENTITY
			poses.append(reference.affine_inverse()*source[entry.bone])
		frames.append(poses)
	return frames

func start_fire() -> void:
	_release_left=0.0
	reload_time=-1.0
	if not fire_frames.is_empty():fire_time=0.0

func start_reload() -> void:
	_release_left=0.0
	fire_time=-1.0
	if not reload_frames.is_empty():reload_time=0.0

func cancel_reload() -> void:
	reload_time=-1.0
	_reload_weight=0.0
	_release_reload=0.0

func _sample_action(frames: Array[Array],fps: float,time: float,index: int) -> Transform3D:
	var frame := minf(time*fps,frames.size()-1)
	var first := floori(frame)
	var next := mini(first+1,frames.size()-1)
	var pose: Transform3D=frames[first][index]
	return pose.interpolate_with(frames[next][index],frame-first) if frame-first>.00001 else pose

func _target_pose(index: int) -> Transform3D:
	if fire_time<0:return entries[index].pose
	var pose := _sample_action(fire_frames,fire_fps,fire_time,index)
	if fire_time>fire_length:
		pose=pose.interpolate_with(entries[index].pose,clampf((fire_time-fire_length)/maxf(fire_return_time,.00001),0,1))
	return pose

func restore() -> void:
	if not applied:return
	for bone: int in base_poses:skeleton.set_bone_pose(bone,base_poses[bone])
	applied=false

func capture() -> void:
	for entry in entries:base_poses[entry.bone]=skeleton.get_bone_pose(entry.bone)
	applied=false

func release(duration: float) -> void:
	requested=false
	_release_aim=weight
	_release_reload=_reload_weight if reload_time>=0 else 0.0
	_release_duration=maxf(duration,0.0)
	_release_left=_release_duration if _release_aim>0.0 or _release_reload>0.0 else 0.0
	if _release_left<=0.0:
		weight=0.0;_reload_weight=0.0;fire_time=-1.0;reload_time=-1.0

func _advance_weights(delta: float) -> void:
	if _release_left>0.0:
		if not requested:
			_release_left=maxf(_release_left-delta,0.0)
			var fade := smoothstep(0.0,1.0,_release_left/_release_duration)
			weight=_release_aim*fade
			_reload_weight=_release_reload*fade
			if _release_left<=0.0:fire_time=-1.0;reload_time=-1.0
			return
		_release_left=0.0;fire_time=-1.0;reload_time=-1.0
	if fire_time>=0:
		fire_time+=delta
		if fire_time>fire_length+fire_return_time:fire_time=-1.0
	if reload_time>=0:
		reload_time+=delta
		if reload_time>reload_length+reload_return_time:reload_time=-1.0
	weight=move_toward(weight,1.0 if requested else 0.0,delta/maxf(blend_time,.00001)) if blend_time>0 else (1.0 if requested else 0.0)
	_reload_weight=0.0
	if reload_time>=0:
		# The exported last pose plays at full weight. Only its return is eased,
		# toward the live locomotion/aim pose evaluated on this same tick.
		var returning := clampf((reload_time-reload_length)/maxf(reload_return_time,.00001),0,1)
		_reload_weight=minf(reload_time/maxf(reload_blend_time,.00001),1.0)*(1.0-smoothstep(0.0,1.0,returning))

func advance(delta: float,turn_motion := Transform3D.IDENTITY) -> void:
	_advance_weights(delta)
	if (weight<=0.0 and _reload_weight<=0.0) or entries.is_empty():return
	var original: Dictionary={pelvis:skeleton.get_bone_global_pose(pelvis)}
	# Keep locomotion bob and sway, but let the character/view orientation
	# steer the upper body instead of the pelvis's animated yaw/pitch/roll.
	var anchor: Transform3D=original[pelvis]
	anchor.basis=Basis.IDENTITY
	original[pelvis]=anchor
	for entry in entries:original[entry.bone]=skeleton.get_bone_global_pose(entry.bone)
	for index in entries.size():
		var entry := entries[index]
		var local: Transform3D=original[entry.parent].affine_inverse()*original[entry.bone]
		var target := _target_pose(index)
		if entry.parent==pelvis:target=turn_motion*target
		var mixed: Transform3D=target if weight>=1.0 else local.interpolate_with(target,weight)
		if _reload_weight>0:
			var reload_pose := _sample_action(reload_frames,reload_fps,reload_time,index)
			if entry.parent==pelvis:reload_pose=turn_motion*reload_pose
			mixed=reload_pose if _reload_weight>=1.0 else mixed.interpolate_with(reload_pose,_reload_weight)
		var parent: Transform3D=anchor if entry.parent==pelvis else skeleton.get_bone_global_pose(entry.parent)
		skeleton.set_bone_global_pose(entry.bone,parent*mixed)
	applied=true
