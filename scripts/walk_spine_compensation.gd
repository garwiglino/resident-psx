extends RefCounted
## Redistribute the authored diagonal counter-twist across the waist.
## Pelvis/legs, chest/arms, all anchor positions and root tracks stay authored.
const CLIPS := ["forward_left","forward_right","backward_left","backward_right"]
var enabled := true
var strength := 1.0
var response := .10
var weight := 0.0
var skeleton: Skeleton3D
var pelvis := -1
var chest := -1
var entries: Array[Dictionary]=[]
var reference: Dictionary={}
var applied := false
func setup(target: Skeleton3D) -> void:
	entries.clear();reference.clear();weight=0;applied=false
	skeleton=target;pelvis=skeleton.find_bone("DEF-spine");chest=skeleton.find_bone("DEF-spine.003")
	if pelvis<0 or chest<0:return
	# CharacterMotion has sampled the authored idle before setup. Use that
	# common facing frame rather than the differently oriented bone-rest axes.
	for bone in [pelvis,chest]:reference[bone]=skeleton.get_bone_global_pose(bone).basis.orthonormalized().inverse()
	# Same cumulative 20% / 55% / 100% distribution as the jog look layer.
	for stage in [["DEF-spine.001",.2],["DEF-spine.002",.55]]:
		var bone := skeleton.find_bone(stage[0])
		if bone<0:continue
		reference[bone]=skeleton.get_bone_global_pose(bone).basis.orthonormalized().inverse()
		entries.append({"bone":bone,"fraction":stage[1],"pose":Transform3D.IDENTITY})
func advance(delta: float,clip: String,turning: bool) -> void:
	var target := clampf(strength,0,1) if enabled and clip in CLIPS and not turning else 0.0
	var alpha := 1.0-exp(-maxf(delta,0)/response) if response>.00001 else 1.0
	weight=lerpf(weight,target,alpha)
	if absf(weight-target)<.00001:weight=target
func _heading(bone: int,pose: Transform3D) -> float:
	var facing: Vector3=pose.basis.orthonormalized()*reference[bone]*Vector3.BACK
	return atan2(facing.x,facing.z)
func restore() -> void:
	if not applied:return
	for entry in entries:skeleton.set_bone_pose(entry.bone,entry.pose)
	applied=false
func apply(turning: bool) -> void:
	if weight<=.00001 or turning or entries.is_empty():return
	var from := _heading(pelvis,skeleton.get_bone_global_pose(pelvis))
	var to := _heading(chest,skeleton.get_bone_global_pose(chest))
	for entry in entries:
		entry.pose=skeleton.get_bone_pose(entry.bone)
		var pose := skeleton.get_bone_global_pose(entry.bone)
		var target := lerp_angle(from,to,float(entry.fraction))
		var delta := wrapf(target-_heading(entry.bone,pose),-PI,PI)*weight
		pose.basis=Basis(Vector3.UP,delta)*pose.basis
		skeleton.set_bone_global_pose(entry.bone,pose)
	applied=true
func reset() -> void:restore();weight=0
