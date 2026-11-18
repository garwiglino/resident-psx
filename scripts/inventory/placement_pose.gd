extends RefCounted
## Reversible visual ownership. Only pose tracks run; completion gameplay uses
## the interaction's WorldActions, never a seek through embedded method/audio tracks.
var nodes: Array[Dictionary]=[]
var bones: Array[Dictionary]=[]
var shapes: Array[Dictionary]=[]
var mixers: Array[Dictionary]=[]
var player: AnimationPlayer
var elapsed := 0.0
var length := 0.0
var speed := 1.0
var reversed := false
func capture(root: Node3D,suspend_mixers := true) -> void:
	for node in root.find_children("*","Node",true,false):
		if node is Node3D:nodes.append({"node":weakref(node),"transform":node.transform,"visible":node.visible})
		if node is Skeleton3D:
			var poses: Array[Transform3D]=[]
			for bone in node.get_bone_count():poses.append(node.get_bone_pose(bone))
			bones.append({"node":weakref(node),"poses":poses})
		if node is MeshInstance3D and node.mesh:
			var values := PackedFloat32Array()
			for index in node.get_blend_shape_count():values.append(node.get_blend_shape_value(index))
			shapes.append({"node":weakref(node),"values":values})
		if node is AnimationMixer and not node.is_in_group("mechanism_pose_sampler"):
			mixers.append({"node":weakref(node),"active":node.active})
			if suspend_mixers:node.active=false
func begin(source: AnimationPlayer,animation: StringName,parent: Node,rate := 1.0,track_filter := Callable(),backwards := false) -> void:
	if not source or animation.is_empty() or not source.has_animation(animation):return
	for state in mixers:
		var mixer=state.node.get_ref()
		if mixer:mixer.active=false
	var clip := source.get_animation(animation).duplicate(true) as Animation
	clip.loop_mode=Animation.LOOP_NONE
	for track in range(clip.get_track_count()-1,-1,-1):
		if track_filter.is_valid() and not track_filter.call(source,clip,track):clip.remove_track(track);continue
		if clip.track_get_type(track) in [Animation.TYPE_METHOD,Animation.TYPE_AUDIO,Animation.TYPE_ANIMATION]:clip.remove_track(track)
		elif clip.track_get_type(track) in [Animation.TYPE_VALUE,Animation.TYPE_BEZIER]:
			var property := String(clip.track_get_path(track).get_concatenated_subnames())
			if property.get_slice(":",0) not in ["transform","position","rotation","rotation_degrees","quaternion","scale","visible"] and not property.begins_with("blend_shapes/"):clip.remove_track(track)
	speed=maxf(rate,.01);length=clip.length/speed;elapsed=0;reversed=backwards
	player=AnimationPlayer.new();player.name="AnimationInstallation";parent.add_child(player)
	player.root_node=player.get_path_to(source.get_node(source.root_node));player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new();library.add_animation(&"installation",clip);player.add_animation_library(&"",library)
	player.play(&"installation");player.seek(clip.length if reversed else 0,true,true)
func advance(delta: float) -> bool:
	if not player:return true
	elapsed=minf(elapsed+maxf(delta,0),length);player.seek((length-elapsed if reversed else elapsed)*speed,true,true)
	return elapsed>=length-.000001
func finish(commit: bool) -> void:
	if is_instance_valid(player):player.stop(true);player.free()
	player=null
	if not commit:restore()
	for state in mixers:
		var node=state.node.get_ref()
		if not node:continue
		if commit and node is AnimationPlayer:node.stop(true)
		node.active=state.active
	nodes.clear();bones.clear();shapes.clear();mixers.clear()
func restore() -> void:
	for state in nodes:
		var node=state.node.get_ref()
		if node:node.transform=state.transform;node.visible=state.visible
	for state in bones:
		var node=state.node.get_ref()
		if node:
			for index in mini(node.get_bone_count(),state.poses.size()):node.set_bone_pose(index,state.poses[index])
	for state in shapes:
		var node=state.node.get_ref()
		if node and node.mesh:
			for index in mini(node.get_blend_shape_count(),state.values.size()):node.set_blend_shape_value(index,state.values[index])
