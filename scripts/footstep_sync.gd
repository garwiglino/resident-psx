extends RefCounted
## Observe the displayed foot poses, including crossfades. Never changes a bone.
var skeleton: Skeleton3D
var feet: Array[Dictionary]=[]
var initialized := false
var cooldown := 0.0

func setup(target: Skeleton3D) -> void:
	skeleton=target;feet.clear();initialized=false;cooldown=0
	for side in ["L","R"]:
		var heel := target.find_bone("DEF-foot."+side)
		var toe := target.find_bone("DEF-toe."+side)
		if heel<0 or toe<0:continue
		var offsets: Array[Vector3]=[]
		for bone in [heel,toe]:
			var rest := target.get_bone_global_rest(bone)
			var sole := rest.origin;sole.y=0
			offsets.append(rest.affine_inverse()*sole)
		feet.append({"side":StringName(side),"heel":heel,"toe":toe,"offsets":offsets,
		 "armed":false,"height":0.0,"position":Vector3.ZERO})

func advance(delta: float,audible: bool,contact_height: float,lift_height: float,min_interval: float) -> int:
	cooldown=maxf(cooldown-delta,0)
	var contact := -1
	var strongest := -INF
	for index in feet.size():
		var foot := feet[index]
		var heel: Vector3=skeleton.get_bone_global_pose(foot.heel)*foot.offsets[0]
		var toe: Vector3=skeleton.get_bone_global_pose(foot.toe)*foot.offsets[1]
		var point := heel if heel.y<toe.y else toe
		var previous: float=foot.height
		foot.height=point.y;foot.position=point
		if point.y>maxf(lift_height,contact_height+.005):foot.armed=true
		# A planted foot must visibly lift again before it can make another sound.
		# Consume contacts even when silent (wall, air, disabled), so none are queued.
		if initialized and foot.armed and point.y<=contact_height and point.y<=previous:
			foot.armed=false
			var descent := previous-point.y
			if audible and cooldown<=0 and descent>strongest:
				contact=index;strongest=descent
	initialized=true
	if contact>=0:cooldown=maxf(min_interval,0)
	return contact
