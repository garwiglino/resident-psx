@tool
extends RefCounted
## Generates index masks in the shared rig's rest space. Source meshes are shared
## resources, so only the equipped character receives the filtered mesh.
const Skinning=preload("res://scripts/character_skinning.gd")
const FacePages=preload("res://scripts/face_texture_pages.gd")
const SOURCE_META := &"psx_clothing_source_mesh"
const COVER_DISTANCE := .12
const INTERSECTION_MARGIN := .008

var _sources: Dictionary={}
var _coverage: Dictionary={}

func register_mesh(node: MeshInstance3D, protect_face: bool, mask_bind_transforms: Array[Transform3D]=[]) -> void:
	if _sources.has(node) or not node.mesh is ArrayMesh:
		return
	var source: ArrayMesh=node.mesh
	node.set_meta(SOURCE_META,source)
	_sources[node]={"mesh":source,"visible":node.visible,"protect_face":protect_face,"surfaces":[],
		"signature":null,"mask_bind_transforms":mask_bind_transforms}

func clear() -> void:
	for node: MeshInstance3D in _sources:
		if is_instance_valid(node):
			var source: Dictionary=_sources[node]
			_set_mesh(node,source.mesh)
			node.visible=source.visible
			node.remove_meta(SOURCE_META)
	_sources.clear()
	_coverage.clear()

func apply(node: MeshInstance3D, covers: Array[MeshInstance3D], hidden_by_name: bool) -> void:
	if not _sources.has(node):
		return
	var source: Dictionary=_sources[node]
	var signature: Array=[hidden_by_name]
	for cover in covers:
		signature.append(cover.get_instance_id())
	if signature==source.signature:
		return
	source.signature=signature
	node.visible=source.visible and not hidden_by_name
	if covers.is_empty() or hidden_by_name:
		_set_mesh(node,source.mesh)
		return
	var geometry := _geometry(node)
	var masks: Array=[]
	for cover in covers:
		masks.append(_covered_triangles(node,cover))
	var filtered: Array[PackedInt32Array]=[]
	var removed := 0
	for surface in geometry.size():
		var indices: PackedInt32Array=geometry[surface].indices
		var visible := PackedInt32Array()
		for triangle in indices.size()/3:
			var covered := false
			for mask: Array in masks:
				if mask[surface][triangle]:
					covered=true
					break
			if covered:
				removed+=1
			else:
				visible.append(indices[triangle*3])
				visible.append(indices[triangle*3+1])
				visible.append(indices[triangle*3+2])
		filtered.append(visible)
	_set_mesh(node,_filtered_mesh(source.mesh,filtered) if removed else source.mesh)

func _set_mesh(node: MeshInstance3D, mesh: ArrayMesh) -> void:
	if node.mesh==mesh:
		return
	var materials: Array[Material]=[]
	if node.mesh:
		for surface in node.mesh.get_surface_count():
			materials.append(node.get_surface_override_material(surface))
	node.mesh=mesh
	for surface in mini(materials.size(),mesh.get_surface_count()):
		node.set_surface_override_material(surface,materials[surface])

func _filtered_mesh(source: ArrayMesh, indices: Array[PackedInt32Array]) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.blend_shape_mode=source.blend_shape_mode
	for index in source.get_blend_shape_count():
		result.add_blend_shape(source.get_blend_shape_name(index))
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		# Keep surface numbers and material overrides even when a layer covers a
		# whole surface. A degenerate triangle contributes no visible pixels.
		arrays[Mesh.ARRAY_INDEX]=indices[surface] if not indices[surface].is_empty() else PackedInt32Array([0,0,0])
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays,source.surface_get_blend_shape_arrays(surface),{},source.surface_get_format(surface))
		result.surface_set_material(surface,source.surface_get_material(surface))
	return result

func _geometry(node: MeshInstance3D) -> Array:
	var source: Dictionary=_sources[node]
	if not source.surfaces.is_empty():
		return source.surfaces
	var skeleton := node.get_node_or_null(node.skeleton) as Skeleton3D
	# A previously exported garment keeps its original rest shape for masking,
	# even when the live skeleton has a new bind pose.
	var transforms: Array[Transform3D]=source.mask_bind_transforms
	var has_authored_rest := not transforms.is_empty()
	var bones := PackedInt32Array()
	for bind in node.skin.get_bind_count():
		var bone := node.skin.get_bind_bone(bind)
		if bone<0:
			bone=skeleton.find_bone(node.skin.get_bind_name(bind))
		bones.append(bone)
		if not has_authored_rest:
			transforms.append(skeleton.get_bone_global_rest(bone)*node.skin.get_bind_pose(bind))
	for surface in source.mesh.get_surface_count():
		var arrays: Array=source.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		var skin := Skinning.restore(node,arrays,bones,skeleton)
		var stride: int=skin.bones.size()/positions.size()
		for vertex in positions.size():
			var point := Vector3.ZERO
			for influence in stride:
				var index := vertex*stride+influence
				if skin.weights[index]>0:
					point+=(transforms[skin.bones[index]]*positions[vertex])*skin.weights[index]
			positions[vertex]=point
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for vertex in positions.size():
				indices.append(vertex)
		var protected: bool=source.protect_face and (node.name==&"cop_hair" or FacePages.part(source.mesh.surface_get_material(surface))!=0)
		source.surfaces.append({"positions":positions,"indices":indices,"protected":protected})
	return source.surfaces

func _cover_tree(node: MeshInstance3D) -> Dictionary:
	var source: Dictionary=_sources[node]
	if source.has("tree"):
		return source
	var faces := PackedVector3Array()
	for surface: Dictionary in _geometry(node):
		for index: int in surface.indices:
			faces.append(surface.positions[index])
	var tree := TriangleMesh.new()
	source.tree=tree if tree.create_from_faces(faces) else null
	var bounds := AABB(faces[0],Vector3.ZERO) if not faces.is_empty() else AABB()
	for point in faces:
		bounds=bounds.expand(point)
	source.bounds=bounds.grow(COVER_DISTANCE)
	return source

func _covered_triangles(target: MeshInstance3D, cover: MeshInstance3D) -> Array:
	var key := "%d:%d" % [target.get_instance_id(),cover.get_instance_id()]
	if _coverage.has(key):
		return _coverage[key]
	var outer := _cover_tree(cover)
	var allow_corner: bool=cover.get_meta(&"clothing_mask_allow_one_corner",false)
	var result: Array=[]
	for surface: Dictionary in _geometry(target):
		var flags := PackedByteArray()
		var indices: PackedInt32Array=surface.indices
		flags.resize(indices.size()/3)
		if outer.tree and not surface.protected:
			for triangle in flags.size():
				var a: Vector3=surface.positions[indices[triangle*3]]
				var b: Vector3=surface.positions[indices[triangle*3+1]]
				var c: Vector3=surface.positions[indices[triangle*3+2]]
				var center := (a+b+c)/3.0
				if not outer.bounds.has_point(center):
					continue
				var normal := (c-a).cross(b-a).normalized()
				if normal.is_zero_approx():
					continue
				# Test across each triangle, so a garment opening or cuff leaves
				# the exposed skin intact. Open garments need no virtual caps.
				var samples := [center,a.lerp(center,.04),b.lerp(center,.04),c.lerp(center,.04),
					(a+b).lerp(center*2,.04)*.5,(b+c).lerp(center*2,.04)*.5,(c+a).lerp(center*2,.04)*.5]
				var covered := true
				var unused_corner := allow_corner
				for i in samples.size():
					var point: Vector3=samples[i]
					if not outer.tree.intersect_segment(point-normal*INTERSECTION_MARGIN,point+normal*COVER_DISTANCE).is_empty():
						continue
					if unused_corner and i in [1,2,3]:
						unused_corner=false
						continue
					covered=false
					break
				flags[triangle]=int(covered)
		result.append(flags)
	_coverage[key]=result
	return result
