@tool
extends RefCounted
## Retain the rare >8-influence vertices instead of importing a truncated skin.
static var _sources: Dictionary={}
static var _stamps: Dictionary={}
static func restore(node: MeshInstance3D,arrays: Array,bind_indices: PackedInt32Array,skeleton: Skeleton3D) -> Dictionary:
	var result := {"bones":arrays[Mesh.ARRAY_BONES],"weights":arrays[Mesh.ARRAY_WEIGHTS]}
	if not skeleton:return result
	var path: String=node.get_meta("psx_skin_metadata","")
	if path.is_empty():
		if String(node.name) not in ["cop_char","cop_coat_mask","cop_hair"]:return result
		path="res://assets/character/cop_player.json"
	if not FileAccess.file_exists(path):return result
	var stamp := FileAccess.get_modified_time(path)
	if stamp!=_stamps.get(path,-1):
		_stamps[path]=stamp;_sources[path]=JSON.parse_string(FileAccess.get_file_as_string(path))
	var overflow: Array=_sources[path].get("overflow_skin",[])
	if overflow.is_empty():return result
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var stride: int=arrays[Mesh.ARRAY_BONES].size()/vertices.size()
	for row in overflow:stride=maxi(stride,row.weights.size())
	var old_stride: int=arrays[Mesh.ARRAY_BONES].size()/vertices.size()
	var bones := PackedInt32Array();var weights := PackedFloat32Array()
	bones.resize(vertices.size()*stride);weights.resize(vertices.size()*stride)
	for vertex in vertices.size():
		var authored: Array=[]
		for row in overflow:
			var p: Array=row.position
			if vertices[vertex].distance_squared_to(Vector3(p[0],p[1],p[2]))<.0000000001:authored=row.weights;break
		if authored.is_empty():
			for index in old_stride:
				bones[vertex*stride+index]=arrays[Mesh.ARRAY_BONES][vertex*old_stride+index]
				weights[vertex*stride+index]=arrays[Mesh.ARRAY_WEIGHTS][vertex*old_stride+index]
		else:
			for index in authored.size():
				var bind := bind_indices.find(skeleton.find_bone(String(authored[index][0])))
				assert(bind>=0,"Missing B-Bone skin binding: "+String(authored[index][0]))
				bones[vertex*stride+index]=bind;weights[vertex*stride+index]=float(authored[index][1])
	result.bones=bones;result.weights=weights
	return result
