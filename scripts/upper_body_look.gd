extends RefCounted
## Additive look pose on the exported Rigify DEF anchors. Leg poses stay authored.
var skeleton: Skeleton3D
var stages: Array[Dictionary]=[]
var base_poses: Dictionary={}
var affected: Array[int]=[]
var applied := false
var yaw := 0.0
var pitch := 0.0
var base_pivot: StringName
var neck := -1
var head := -1
var neck_segments: Dictionary[int,float]={}

func setup(target: Skeleton3D) -> void:
	skeleton=target
	# Rigify's neck and head are separate anchors in the flattened game rig.
	neck=skeleton.find_bone("DEF-spine.005")
	head=skeleton.find_bone("DEF-spine.006")
	for stage in [[1,.2],[2,.35],[3,.45]]:
		var pivot := skeleton.find_bone("DEF-spine.%03d" % stage[0])
		if pivot<0:continue
		var bones: Array[int]=[]
		for bone in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone)
			var spine := int(name.trim_prefix("DEF-spine.")) if name.begins_with("DEF-spine.") else -1
			var upper_limb := false
			for prefix in ["DEF-shoulder","DEF-upper_arm","DEF-forearm","DEF-hand","DEF-f_","DEF-thumb","DEF-palm","DEF-breast","DEF-neck","DEF-head"]:
				if name.begins_with(prefix):upper_limb=true;break
			var upper_vertex := name.begins_with("VTX-") and skeleton.get_bone_global_rest(bone).origin.y>skeleton.get_bone_global_rest(pivot).origin.y
			if spine>=stage[0] or upper_limb or upper_vertex:
				bones.append(bone)
				if bone not in affected:affected.append(bone)
		stages.append({"pivot":pivot,"weight":stage[1],"bones":bones})
	var segment_end := 1
	for bone in skeleton.get_bone_count():
		var name := String(skeleton.get_bone_name(bone))
		if name.begins_with("SEG-DEF-spine.005-"):
			# These skin segments inherit the neck anchor's motion. Save their
			# local poses so the extra twist at the top can be applied afresh.
			var segment := name.get_slice("-",3).to_int()
			neck_segments[bone]=float(segment)
			segment_end=maxi(segment_end,segment)
			affected.append(bone)
	for bone: int in neck_segments:
		neck_segments[bone]/=segment_end
	set_base_pivot(&"DEF-spine")
	capture()

func set_base_pivot(name: StringName) -> void:
	if not skeleton or stages.is_empty():return
	if name not in [&"DEF-spine",&"DEF-spine.001"]:name=&"DEF-spine"
	if name==base_pivot:return
	var bone := skeleton.find_bone(name)
	if bone<0:bone=skeleton.find_bone("DEF-spine.001")
	if bone<0:return
	# A lower centre of rotation does not add the pelvis or legs to the mask.
	# Their authored transforms, including the turn, remain untouched.
	stages[0].pivot=bone;base_pivot=name

func restore() -> void:
	if not applied:return
	for bone: int in affected:skeleton.set_bone_pose(bone,base_poses[bone])
	applied=false

func capture() -> void:
	for bone: int in affected:base_poses[bone]=skeleton.get_bone_pose(bone)
	applied=false

func apply(view_direction: Vector3,yaw_limit: float,pitch_limit: float,enabled: bool,turn_motion := Transform3D.IDENTITY,run_yaw := 0.0) -> void:
	restore()
	yaw=0
	pitch=0
	if stages.is_empty() or (not enabled and absf(run_yaw)<.000001):return
	var local_direction := (skeleton.global_basis.inverse()*view_direction).normalized()
	# The imported character faces local +Z; positive camera pitch looks upwards.
	# Clamp the authored mouse/body offset in the original character frame,
	# then compensate the run heading separately. A 25-degree torso setting
	# must not truncate a 45-degree diagonal compensation.
	var original_yaw := wrapf(atan2(local_direction.x,local_direction.z)+run_yaw,-PI,PI)
	yaw=(clampf(original_yaw,-yaw_limit,yaw_limit) if enabled else 0.0)-run_yaw
	pitch=clampf(-atan2(local_direction.y,Vector2(local_direction.x,local_direction.z).length()),-pitch_limit,pitch_limit) if enabled else 0.0
	var rotation := Quaternion(Vector3.UP,yaw)*Quaternion(Vector3.RIGHT,pitch)
	# The authored turn already rotates the chest. Steer its forward direction
	# to the mouse target, preserving authored roll/bob instead of adding yaw
	# twice or pinning the complete upper body to an unanimated pose.
	var facing := (turn_motion.basis.orthonormalized()*Vector3.BACK).normalized()
	var turned_yaw := atan2(facing.x,facing.z)
	var turned_pitch := -atan2(facing.y,Vector2(facing.x,facing.z).length())
	var heading := Quaternion(Vector3.UP,turned_yaw)*Quaternion(Vector3.RIGHT,turned_pitch)
	if enabled:rotation=(rotation*heading.inverse()).normalized()
	if rotation.angle_to(Quaternion.IDENTITY)<.00001:return
	for stage in stages:
		var pivot := skeleton.get_bone_global_pose(stage.pivot).origin
		var basis := Basis(Quaternion.IDENTITY.slerp(rotation,stage.weight))
		var transform := Transform3D(basis,pivot-basis*pivot)
		for bone: int in stage.bones:skeleton.set_bone_global_pose(bone,transform*skeleton.get_bone_global_pose(bone))
	applied=true

func apply_head_turn(angle: float) -> void:
	if absf(angle)<.0001 or neck not in affected or head not in affected:return
	var neck_pose := skeleton.get_bone_global_pose(neck)
	var head_pose := skeleton.get_bone_global_pose(head)
	var neck_turn := Basis(Vector3.UP,angle*.28)
	var head_origin := neck_pose.origin+neck_turn*(head_pose.origin-neck_pose.origin)
	skeleton.set_bone_global_pose(neck,Transform3D(neck_turn*neck_pose.basis,neck_pose.origin))
	var neck_basis := neck_pose.basis.orthonormalized()
	for bone: int in neck_segments:
		var local_pose := skeleton.get_bone_pose(bone)
		var twist := Basis(Vector3.UP,angle*.72*neck_segments[bone])
		local_pose.basis=neck_basis.transposed()*twist*neck_basis*local_pose.basis
		skeleton.set_bone_pose(bone,local_pose)
	skeleton.set_bone_global_pose(head,Transform3D(Basis(Vector3.UP,angle)*head_pose.basis,head_origin))
	applied=true
