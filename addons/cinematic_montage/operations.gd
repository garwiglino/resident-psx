@tool
extends RefCounted
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")

static func copy_plans(sequence: Node) -> Array[Shot]:
	var result: Array[Shot]=[]
	for plan in sequence.get_plans():result.append(plan.duplicate(false))
	return result

static func timeline(sequence: Node) -> AnimationPlayer:return sequence.get_node_or_null(sequence.timeline_path) as AnimationPlayer if is_instance_valid(sequence) else null

static func library_edit(sequence: Node,animation: StringName) -> Dictionary:
	var player := timeline(sequence)
	if not player or not player.has_animation(animation):return {}
	var library_name := player.find_animation_library(player.get_animation(animation))
	var original := player.get_animation_library(library_name)
	return {"player":player,"name":library_name,"before":original,"after":original.duplicate(true),"animation":String(animation).trim_prefix(String(library_name)+"/") if not library_name.is_empty() else String(animation)}

static func new_animation(sequence: Node,plan: Resource,copy := false) -> Dictionary:
	var player := timeline(sequence)
	if not player:return {}
	var original := player.get_animation_library(&"") if player.has_animation_library(&"") else null
	var library: AnimationLibrary=original.duplicate(true) if original else AnimationLibrary.new()
	var index := 1;var name := "plan_01"
	while library.has_animation(name):index+=1;name="plan_%02d" % index
	var clip: Animation
	if copy and player.has_animation(plan.animation):clip=player.get_animation(plan.animation).duplicate(true)
	else:
		clip=Animation.new();clip.length=2
		var camera := sequence.get_node_or_null(plan.camera_path) as Camera3D
		if not camera:return {}
		var path := String(camera_path(sequence,plan))
		var position := clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(position,NodePath(path))
		var rotation := clip.add_track(Animation.TYPE_ROTATION_3D);clip.track_set_path(rotation,NodePath(path))
		var fov := clip.add_track(Animation.TYPE_VALUE);clip.track_set_path(fov,NodePath(path+":fov"))
		for time in [0.0,2.0]:
			clip.position_track_insert_key(position,time,camera.position);clip.rotation_track_insert_key(rotation,time,camera.quaternion);clip.track_insert_key(fov,time,camera.fov)
	library.add_animation(StringName(name),clip)
	return {"name":&"","before":original,"after":library,"animation":StringName(name)}

static func camera_path(sequence: Node,plan: Resource) -> NodePath:
	var player := timeline(sequence)
	var camera := sequence.get_node_or_null(plan.camera_path)
	return player.get_node(player.root_node).get_path_to(camera) if camera else NodePath()

static func key_times(sequence: Node,plan: Resource) -> PackedFloat32Array:
	var result := PackedFloat32Array();var player := timeline(sequence)
	if not player or not player.has_animation(plan.animation):return result
	var clip := player.get_animation(plan.animation);var path := String(camera_path(sequence,plan))
	for track in clip.get_track_count():
		var target := String(clip.track_get_path(track))
		if target!=path and target!=path+":fov":continue
		for key in clip.track_get_key_count(track):
			var time: float=clip.track_get_key_time(track,key)-plan.start_time
			if time>=-.00001 and time<=plan.duration(player)+.00001 and not result.has(time):result.append(time)
	result.sort();return result

static func camera_keys(sequence: Node,plan: Resource,relative_time: float,remove := false) -> Dictionary:
	var result := library_edit(sequence,plan.animation)
	var camera := sequence.get_node_or_null(plan.camera_path) as Camera3D
	if result.is_empty() or not camera:return {}
	var clip: Animation=result.after.get_animation(result.animation)
	var path := String(camera_path(sequence,plan));var time: float=plan.start_time+relative_time
	var changed := 0
	for data in [[Animation.TYPE_POSITION_3D,path,camera.position],[Animation.TYPE_ROTATION_3D,path,camera.quaternion],[Animation.TYPE_VALUE,path+":fov",camera.fov]]:
		var track := clip.find_track(NodePath(data[1]),data[0])
		if remove:
			if track<0:continue
			for key in range(clip.track_get_key_count(track)-1,-1,-1):
				if absf(clip.track_get_key_time(track,key)-time)<.0001:clip.track_remove_key(track,key);changed+=1
		else:
			if track<0:track=clip.add_track(data[0]);clip.track_set_path(track,NodePath(data[1]))
			match data[0]:
				Animation.TYPE_POSITION_3D:clip.position_track_insert_key(track,time,data[2])
				Animation.TYPE_ROTATION_3D:clip.rotation_track_insert_key(track,time,data[2])
				Animation.TYPE_VALUE:clip.track_insert_key(track,time,data[2])
			changed+=1
	result.changed=changed;return result
