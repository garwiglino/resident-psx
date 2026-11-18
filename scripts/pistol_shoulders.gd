extends RefCounted

const LIFT_METRES := 0.013
const MAX_SWING := deg_to_rad(14.0)

var skeleton: Skeleton3D
var root_bone := -1
var arms: Array[PackedInt32Array] = []
var original_poses: Dictionary[int, Transform3D] = {}
var weight := 0.0

func setup(target: Skeleton3D) -> void:
	skeleton = target
	root_bone = skeleton.find_bone("RootMotion")
	if root_bone < 0:
		return
	for side in ["L", "R"]:
		var arm := PackedInt32Array()
		for name in ["DEF-shoulder.%s", "DEF-upper_arm.%s", "DEF-upper_arm.%s.001", "DEF-forearm.%s"]:
			var bone := skeleton.find_bone(name % side)
			if bone < 0 or skeleton.get_bone_parent(bone) != root_bone:
				break
			arm.append(bone)
		if arm.size() == 4:
			arms.append(arm)

func restore() -> void:
	for bone in original_poses:
		skeleton.set_bone_pose(bone, original_poses[bone])
	original_poses.clear()

func apply(delta: float, active: bool, blend_time: float) -> void:
	var target := 1.0 if active else 0.0
	weight = move_toward(weight, target, delta / blend_time) if blend_time > 0.0 else target
	if weight <= 0.0 or arms.is_empty():
		return
	var up := skeleton.get_bone_global_pose(root_bone).basis.orthonormalized().inverse() * Vector3.UP
	var lift := LIFT_METRES * smoothstep(0.0, 1.0, weight)
	for arm in arms:
		_lift_arm(arm, up, lift)

func _lift_arm(arm: PackedInt32Array, up: Vector3, lift: float) -> void:
	var clavicle := skeleton.get_bone_pose(arm[0])
	var upper := skeleton.get_bone_pose(arm[1])
	var upper_tip := skeleton.get_bone_pose(arm[2])
	var elbow := skeleton.get_bone_pose_position(arm[3])

	# The shoulder moves on a circle around the clavicle-to-elbow line.
	# Both lengths are preserved and the elbow stays in its animated position.
	var axis := (elbow - clavicle.origin).normalized()
	var offset := upper.origin - clavicle.origin
	var radial := offset.slide(axis)
	var plane_up := up.slide(axis)
	var capacity := radial.length() * plane_up.length()
	if capacity < 0.00001:
		return
	var alignment := clampf(radial.dot(plane_up) / capacity, -1.0, 1.0)
	var angle := acos(alignment)
	var tangent := axis.dot(radial.normalized().cross(plane_up.normalized()))
	# Ease the direction change if the shoulder passes directly below the axis.
	var limit := MAX_SWING * smoothstep(0.0, 0.15, absf(tangent))
	var sweep := minf(angle - acos(minf(alignment + lift / capacity, 1.0)), limit)
	if sweep < 0.00001:
		return
	var shoulder := upper.origin + radial.rotated(axis, signf(tangent) * sweep) - radial
	var collar_swing := Basis(Quaternion(offset.normalized(), (shoulder - clavicle.origin).normalized()))
	var arm_swing := Basis(Quaternion((upper.origin - elbow).normalized(), (shoulder - elbow).normalized()))
	var from_elbow := Transform3D(arm_swing, elbow - arm_swing * elbow)

	# The exported upper arm has two anchors, each with its own skin segments.
	# Rotate them together around the elbow, leaving the forearm and grip intact.
	_set_pose(arm[0], clavicle, Transform3D(collar_swing * clavicle.basis, clavicle.origin))
	_set_pose(arm[1], upper, from_elbow * upper)
	_set_pose(arm[2], upper_tip, from_elbow * upper_tip)

func _set_pose(bone: int, original: Transform3D, pose: Transform3D) -> void:
	original_poses[bone] = original
	skeleton.set_bone_pose(bone, pose)
