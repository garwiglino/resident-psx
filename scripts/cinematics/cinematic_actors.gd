@tool
extends RefCounted
## Private manual mixers never fire animation methods or audio. Actor controllers
## are suspended only while owned by the montage; their exact state is restored.
var actors: Dictionary={}
var cues: Array[Dictionary]=[]
var sequence: Node
var editor_preview := false

func prepare(owner: Node,plans: Array,preview := false) -> void:
	restore();sequence=owner;editor_preview=preview
	for plan in plans:
		for cue in plan.actors:
			var actor: Node3D=cue.actor(owner)
			if not actor or actors.has(actor.get_instance_id()):continue
			var snapshot: Dictionary={"actor":weakref(actor),"transform":actor.transform,"visible":actor.visible,"nodes":[],"skeletons":[],"transforms":[],"shapes":[],"mixers":[],"players":{},"base":actor.global_transform}
			var nodes: Array[Node]=[actor];nodes.append_array(actor.find_children("*","Node",true,false))
			var motion: Variant=actor.get("motion")
			if motion and motion.has_method("_restore_pose_layers"):motion._restore_pose_layers()
			for node in nodes:
				if node is Node3D and node!=actor:snapshot.transforms.append({"node":weakref(node),"transform":node.transform,"visible":node.visible})
				if node is MeshInstance3D and node.mesh:
					var values := PackedFloat32Array()
					for shape in node.get_blend_shape_count():values.append(node.get_blend_shape_value(shape))
					snapshot.shapes.append({"node":weakref(node),"values":values})
				if node is Skeleton3D:
					var poses: Array[Transform3D]=[]
					for bone in node.get_bone_count():poses.append(node.get_bone_pose(bone))
					snapshot.skeletons.append({"node":weakref(node),"poses":poses})
				if node is AnimationMixer:
					snapshot.mixers.append({"node":weakref(node),"active":node.active});node.active=false
				if not preview:
					snapshot.nodes.append({"node":weakref(node),"process":node.is_processing(),"physics":node.is_physics_processing(),"input":node.is_processing_unhandled_input()})
					node.set_process(false);node.set_physics_process(false);node.set_process_unhandled_input(false)
			actors[actor.get_instance_id()]=snapshot

func start_plan(plan: Resource) -> void:
	cues.clear()
	for data in actors.values():
		var target: Node3D=data.actor.get_ref()
		if target:
			data.base=target.global_transform;data.plan_visible=target.visible;data.plan_poses=[];data.plan_transforms=[];data.plan_shapes=[]
			for state in data.skeletons:
				var skeleton: Skeleton3D=state.node.get_ref();var poses: Array[Transform3D]=[]
				if skeleton:
					for bone in skeleton.get_bone_count():poses.append(skeleton.get_bone_pose(bone))
				data.plan_poses.append(poses)
			for state in data.transforms:
				var node: Node3D=state.node.get_ref()
				data.plan_transforms.append({"transform":node.transform,"visible":node.visible} if node else {})
			for state in data.shapes:
				var node: MeshInstance3D=state.node.get_ref();var values := PackedFloat32Array()
				if node:
					for shape in node.get_blend_shape_count():values.append(node.get_blend_shape_value(shape))
				data.plan_shapes.append(values)
	for cue in plan.actors:
		var target: Node3D=cue.actor(sequence)
		if target and actors.has(target.get_instance_id()):
			var item: Dictionary={"cue":cue,"actor_id":target.get_instance_id(),"clip":cue.clip(sequence),"length":cue.length(sequence)}
			cues.append(item);_use_clip(actors[target.get_instance_id()],item)
	cues.sort_custom(func(a: Dictionary,b: Dictionary):return a.cue.start_time<b.cue.start_time)
	sample(0)

func _use_clip(data: Dictionary,item: Dictionary) -> void:
	var target: Node3D=data.actor.get_ref();var cue: Resource=item.cue
	if data.players.has(cue.get_instance_id()):return
	var animation_root: Node=cue.animation_root(sequence)
	if not target or not animation_root:return
	var clip: Animation=item.clip.duplicate(true)
	# Cinematic actor tracks are pose tracks. Embedded gameplay events cannot fire
	# when scrubbing, jumping to the end, repeating or skipping the cinematic.
	for track in range(clip.get_track_count()-1,-1,-1):
		if clip.track_get_type(track) in [Animation.TYPE_METHOD,Animation.TYPE_AUDIO,Animation.TYPE_ANIMATION]:clip.remove_track(track)
		elif clip.track_get_type(track)==Animation.TYPE_VALUE:
			var property := String(clip.track_get_path(track).get_concatenated_subnames())
			if property not in ["transform","position","rotation","rotation_degrees","quaternion","scale","visible"] and not property.begins_with("blend_shapes/"):clip.remove_track(track)
		elif clip.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
			var path := clip.track_get_path(track)
			var skeleton := animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
			if skeleton and path.get_subname_count()>0 and skeleton.find_bone(String(path.get_subname(0)))<0:clip.remove_track(track)
	clip.loop_mode=Animation.LOOP_NONE
	var mixer := AnimationPlayer.new();mixer.name="CinematicActorPreview";target.add_child(mixer)
	mixer.root_node=mixer.get_path_to(animation_root);mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var original: AnimationPlayer=cue.player(sequence)
	mixer.root_motion_track=original.root_motion_track if original else NodePath()
	if mixer.root_motion_track.is_empty() and animation_root.get_node_or_null("rig/Skeleton3D"):mixer.root_motion_track=NodePath("rig/Skeleton3D:RootMotion")
	var library := AnimationLibrary.new();library.add_animation(&"pose",clip);mixer.add_animation_library(&"",library)
	mixer.play(&"pose",0);mixer.seek(cue.source_offset,true,true)
	var state: Dictionary={"player":mixer,"clip":clip,"position_track":clip.find_track(mixer.root_motion_track,Animation.TYPE_POSITION_3D),"rotation_track":clip.find_track(mixer.root_motion_track,Animation.TYPE_ROTATION_3D),"root_basis":target.global_basis.inverse()*animation_root.global_basis}
	state.initial=_root_pose(state,cue.source_offset);data.players[cue.get_instance_id()]=state

func _root_pose(state: Dictionary,time: float) -> Transform3D:
	var position: Vector3=state.clip.position_track_interpolate(state.position_track,time) if state.position_track>=0 else Vector3.ZERO
	var rotation: Quaternion=state.clip.rotation_track_interpolate(state.rotation_track,time) if state.rotation_track>=0 else Quaternion.IDENTITY
	return Transform3D(Basis(rotation),position)

func _root_delta(state: Dictionary,time: float) -> Transform3D:
	var pose := _root_pose(state,time);var initial: Transform3D=state.initial
	return Transform3D(pose.basis*initial.basis.inverse(),pose.origin-initial.origin)

func sample(time: float) -> void:
	for id in actors:
		var data: Dictionary=actors[id];var target: Node3D=data.actor.get_ref()
		if not target:continue
		target.global_transform=data.base;target.visible=data.plan_visible
		for index in data.skeletons.size():
			var skeleton: Skeleton3D=data.skeletons[index].node.get_ref()
			if skeleton:
				for bone in mini(skeleton.get_bone_count(),data.plan_poses[index].size()):skeleton.set_bone_pose(bone,data.plan_poses[index][bone])
		for index in data.transforms.size():
			var node: Node3D=data.transforms[index].node.get_ref();var pose: Dictionary=data.plan_transforms[index]
			if node and not pose.is_empty():node.transform=pose.transform;node.visible=pose.visible
		for index in data.shapes.size():
			var node: MeshInstance3D=data.shapes[index].node.get_ref()
			if node:
				for shape in mini(node.get_blend_shape_count(),data.plan_shapes[index].size()):node.set_blend_shape_value(shape,data.plan_shapes[index][shape])
		var items: Array=[]
		for item in cues:
			if item.actor_id==id:items.append(item)
		for index in items.size():
			var item: Dictionary=items[index];var cue: Resource=item.cue
			if time+.000001<cue.start_time:break
			if not data.players.has(cue.get_instance_id()):continue
			var state: Dictionary=data.players[cue.get_instance_id()];var mixer: AnimationPlayer=state.player
			var end_time: float=minf(time,items[index+1].cue.start_time) if index+1<items.size() else time
			var elapsed: float=clampf(end_time-cue.start_time,0,item.length)*cue.speed
			var span := maxf(item.clip.length-cue.source_offset,.000001)
			var loops := floori(elapsed/span) if cue.loop else 0
			var at: float=cue.source_offset+fmod(elapsed,span) if cue.loop else minf(cue.source_offset+elapsed,item.clip.length)
			mixer.seek(at,true,true)
			if not cue.apply_root_motion:continue
			var partial := _root_delta(state,at)
			var full_delta := Transform3D.IDENTITY
			if loops>0:
				var full := _root_delta(state,item.clip.length)
				# Transform powers compose both facing and translation across loops.
				var count := loops
				while count>0:
					if count&1:full_delta=full_delta*full
					full=full*full;count=count>>1
			var local := full_delta*partial
			var root_space: Basis=target.global_basis*state.root_basis
			var root_rotation := root_space.orthonormalized()
			var base: Transform3D=target.global_transform
			target.global_transform=Transform3D(root_rotation*local.basis*root_rotation.inverse()*base.basis,base.origin+root_space*local.origin)

func valid() -> bool:
	for data in actors.values():
		var target: Node=data.actor.get_ref()
		if not target or not target.is_inside_tree():return false
	return true

func restore() -> void:
	for data in actors.values():
		var target: Node3D=data.actor.get_ref()
		for state in data.players.values():
			if is_instance_valid(state.player):state.player.free()
		if not target:continue
		if editor_preview:target.transform=data.transform
		target.visible=data.visible
		for state in data.transforms:
			var node: Node3D=state.node.get_ref()
			if node:node.transform=state.transform;node.visible=state.visible
		for state in data.shapes:
			var node: MeshInstance3D=state.node.get_ref()
			if node:
				for shape in mini(node.get_blend_shape_count(),state.values.size()):node.set_blend_shape_value(shape,state.values[shape])
		for state in data.skeletons:
			var skeleton: Skeleton3D=state.node.get_ref()
			if skeleton:
				for bone in mini(skeleton.get_bone_count(),state.poses.size()):skeleton.set_bone_pose(bone,state.poses[bone])
		for state in data.mixers:
			var mixer: Node=state.node.get_ref()
			if mixer:mixer.active=state.active
		for state in data.nodes:
			var node: Node=state.node.get_ref()
			if node:node.set_process(state.process);node.set_physics_process(state.physics);node.set_process_unhandled_input(state.input)
		if not editor_preview and target.has_method("reset_camera_follow"):target.reset_camera_follow()
	actors.clear();cues.clear();sequence=null
