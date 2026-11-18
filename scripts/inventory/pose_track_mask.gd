extends RefCounted
## Shared channel mask for covers, buttons and switches on the same exported rig.
var context: Node
var scope_path: NodePath
var bone_names := PackedStringArray()
var changing: Dictionary={}
func configure(root: Node,source: AnimationPlayer,names: Array,scope := NodePath(),bones := PackedStringArray()) -> void:
	context=root;scope_path=scope;bone_names=bones;changing.clear();var first: Dictionary={}
	for name in names:
		if String(name).is_empty() or not source.has_animation(name):continue
		var clip := source.get_animation(name)
		for track in clip.get_track_count():
			var key := "%s|%s" % [clip.track_get_type(track),clip.track_get_path(track)]
			for index in clip.track_get_key_count(track):
				var value: Variant=clip.track_get_key_value(track,index)
				if not first.has(key):first[key]=value
				elif not _same(first[key],value):changing[key]=true;break
func _same(a: Variant,b: Variant) -> bool:
	if typeof(a)!=typeof(b):return false
	if a is Quaternion:return absf(a.dot(b))>1.0-.000001
	if a is Vector3:return a.is_equal_approx(b)
	if a is float:return is_equal_approx(a,b)
	return a==b
func allows(source: AnimationPlayer,clip: Animation,track: int) -> bool:
	if not clip.track_is_enabled(track):return false
	var path := clip.track_get_path(track)
	if scope_path.is_empty():return changing.has("%s|%s" % [clip.track_get_type(track),path])
	var scope := context.get_node_or_null(scope_path);var root := source.get_node_or_null(source.root_node)
	var target := root.get_node_or_null(NodePath(path.get_concatenated_names())) if root else null
	if not scope or not target or (target!=scope and not scope.is_ancestor_of(target)):return false
	if scope is Skeleton3D and target==scope and not bone_names.is_empty():
		if path.get_subname_count()==0:return false
		var index: int=scope.find_bone(path.get_subname(0))
		while index>=0:
			if scope.get_bone_name(index) in bone_names:return true
			index=scope.get_bone_parent(index)
		return false
	return true
