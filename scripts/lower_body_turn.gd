extends RefCounted
## Whole authored turn pose. Root yaw is consumed by the character controller.
## Aim/look are layered above the torso; pelvis and legs remain fully authored.
var skeleton: Skeleton3D
var bones := PackedInt32Array()
var frames: Array[Array]=[]
var root_yaws := PackedFloat64Array()
var fps := 30.0
var length := 0.0
var total_rotation := 0.0
var time := 0.0
var weight := 0.0
var blend_time := .12
var active := false
var rotation_delta := 0.0
var applied := false
var base_poses: Array[Transform3D]=[]
var protected_indices := PackedInt32Array()
var all_indices := PackedInt32Array()
var pelvis := -1
var chest := -1
## Chest motion relative to pelvis translation, before aim/look. This keeps the
## animated torso connected while an aiming/fire/reload pose replaces the arms.
var upper_motion := Transform3D.IDENTITY

static func is_waist(name: String) -> bool:
	var deform := name.trim_prefix("SEG-")
	return deform=="DEF-spine.001" or deform.begins_with("DEF-spine.001-")

static func includes_bone(name: String) -> bool:
	var deform := name.trim_prefix("SEG-")
	if is_waist(name):return true
	if deform=="DEF-spine" or deform.begins_with("DEF-spine-"):return true
	for prefix in ["DEF-pelvis.","DEF-thigh.","DEF-shin.","DEF-foot.","DEF-toe."]:
		if deform.begins_with(prefix):return true
	return false

func setup(target: Skeleton3D,clip: Animation,source_fps := 30.0) -> void:
	skeleton=target;bones.clear();frames.clear();root_yaws.clear();base_poses.clear();protected_indices.clear();all_indices.clear()
	pelvis=skeleton.find_bone("DEF-spine");chest=skeleton.find_bone("DEF-spine.003")
	if not clip:return
	fps=maxf(source_fps,1);length=clip.length
	var tracks: Array[Dictionary]=[]
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone)==&"RootMotion":continue
		var path := NodePath("rig/Skeleton3D:"+skeleton.get_bone_name(bone))
		var position := clip.find_track(path,Animation.TYPE_POSITION_3D)
		var rotation := clip.find_track(path,Animation.TYPE_ROTATION_3D)
		var scale := clip.find_track(path,Animation.TYPE_SCALE_3D)
		if position<0 and rotation<0 and scale<0:continue
		if includes_bone(String(skeleton.get_bone_name(bone))):protected_indices.append(bones.size())
		all_indices.append(bones.size())
		bones.append(bone);tracks.append({"position":position,"rotation":rotation,"scale":scale})
	var root := clip.find_track(NodePath("rig/Skeleton3D:RootMotion"),Animation.TYPE_ROTATION_3D)
	var root_initial: Quaternion=clip.rotation_track_interpolate(root,0) if root>=0 else Quaternion.IDENTITY
	var root_space := skeleton.global_basis.orthonormalized()
	for index in roundi(length*fps)+1:
		var at := minf(index/fps,length);var poses: Array=[]
		for item in bones.size():
			var pose := skeleton.get_bone_rest(bones[item]);var track := tracks[item]
			if track.position>=0:pose.origin=clip.position_track_interpolate(track.position,at)
			var rotation: Quaternion=clip.rotation_track_interpolate(track.rotation,at) if track.rotation>=0 else pose.basis.get_rotation_quaternion()
			var scale: Vector3=clip.scale_track_interpolate(track.scale,at) if track.scale>=0 else pose.basis.get_scale()
			pose.basis=Basis(rotation).scaled_local(scale);poses.append(pose)
		frames.append(poses)
		# Imported bone poses include the armature's 90-degree rest orientation.
		# Convert the relative root rotation through the actual skeleton space.
		var delta: Quaternion=(clip.rotation_track_interpolate(root,at)*root_initial.inverse()).normalized() if root>=0 else Quaternion.IDENTITY
		var facing: Vector3=(root_space*Basis(delta)*root_space.inverse())*Vector3.BACK
		root_yaws.append(atan2(facing.x,facing.z))
	if not root_yaws.is_empty():total_rotation=wrapf(root_yaws[-1]-root_yaws[0],-PI,PI)
	base_poses.resize(bones.size())

func available() -> bool:return not bones.is_empty() and length>0 and total_rotation>.00001
func can_start() -> bool:return available() and not active and weight<=.00001
func start() -> bool:
	if not can_start():return false
	time=0;weight=0;rotation_delta=0;active=true;return true
func cancel() -> void:active=false;rotation_delta=0

func _yaw(at: float) -> float:
	var frame := clampf(at*fps,0,root_yaws.size()-1);var first := floori(frame);var last := mini(first+1,root_yaws.size()-1)
	return lerp_angle(root_yaws[first],root_yaws[last],frame-first)

func advance(delta: float,speed := 1.0) -> void:
	rotation_delta=0
	if not available() or (not active and weight<=0):return
	var was_active := active;var previous := time
	time=minf(time+maxf(delta,0)*maxf(speed,.001),length)
	if was_active:
		if time>=length-.000001:time=length;active=false
		rotation_delta=wrapf(_yaw(time)-_yaw(previous),-PI,PI)
	weight=move_toward(weight,1.0 if was_active else 0.0,delta/maxf(blend_time,.00001)) if blend_time>0 else (1.0 if was_active else 0.0)

func restore() -> void:
	if not applied:return
	for index in bones.size():skeleton.set_bone_pose(bones[index],base_poses[index])
	applied=false

func apply() -> void:
	upper_motion=Transform3D.IDENTITY
	if weight<=0 or frames.is_empty():return
	var neutral_chest := skeleton.get_bone_global_pose(chest) if chest>=0 else Transform3D.IDENTITY
	if pelvis>=0:neutral_chest.origin-=skeleton.get_bone_global_pose(pelvis).origin
	for index in bones.size():
		base_poses[index]=skeleton.get_bone_pose(bones[index])
	applied=true
	_sample_pose(false)
	if chest>=0 and pelvis>=0:
		var turned := skeleton.get_bone_global_pose(chest)
		turned.origin-=skeleton.get_bone_global_pose(pelvis).origin
		# Carry the chest as a rigid assembly for aim/actions. A spine B-bone's
		# length scaling must not stretch the arms, fingers or attached pistol.
		var rotation := turned.basis.orthonormalized()*neutral_chest.basis.orthonormalized().inverse()
		upper_motion=Transform3D(rotation,turned.origin-rotation*neutral_chest.origin)

func enforce() -> void:
	if not applied:return
	_sample_pose(true)

func _sample_pose(protect_lower: bool) -> void:
	var frame := clampf(time*fps,0,frames.size()-1);var first := floori(frame);var last := mini(first+1,frames.size()-1)
	# Re-enforcement after aim/look protects only the original lower mask.
	# The torso must retain those layers rather than being overwritten again.
	var indices: PackedInt32Array=protected_indices if protect_lower else all_indices
	for index in indices:
		var pose: Transform3D=frames[first][index].interpolate_with(frames[last][index],frame-first)
		skeleton.set_bone_pose(bones[index],base_poses[index].interpolate_with(pose,weight))
