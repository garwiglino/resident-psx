@tool
extends Resource
const Data = preload("res://scripts/modular_map/kit_data.gd")
@export var data: Resource:
	set(value):
		if data and data.changed.is_connected(invalidate): data.changed.disconnect(invalidate)
		data=value
		if data and not data.changed.is_connected(invalidate): data.changed.connect(invalidate)
		invalidate()
## Optional material overrides by source material name (native-resolution pages).
@export var material_overrides: Dictionary[String, Material] = {}:
	set(value):
		material_overrides=value
		_ensure_caches()
		_meshes.clear(); _shapes.clear(); emit_changed()
## Individual modules exported from Blender, retained when rebuilding the base kit.
@export var module_overrides: Dictionary[String, Resource] = {}:
	set(value):
		if typeof(module_overrides)==TYPE_DICTIONARY:
			for source: Resource in module_overrides.values():
				if source and source.changed.is_connected(invalidate):source.changed.disconnect(invalidate)
		module_overrides=value
		for source: Resource in module_overrides.values():
			if source and not source.changed.is_connected(invalidate):source.changed.connect(invalidate)
		invalidate()
var _meshes: Dictionary = {}
var _shapes: Dictionary = {}

func mesh_for(module: String, start_mask := 0, end_mask := 0) -> ArrayMesh:
	_ensure_caches()
	# Resources already open before this property was added can retain Nil after
	# a script hot reload, even though new instances get the dictionary default.
	if typeof(module_overrides)!=TYPE_DICTIONARY:module_overrides={}
	if typeof(material_overrides)!=TYPE_DICTIONARY:material_overrides={}
	var key := "%s:%d:%d" % [module, start_mask, end_mask]
	if _meshes.has(key): return _meshes[key]
	var source: Resource=module_overrides.get(module)
	if not source or not source.get("modules") is Dictionary or not source.modules.has(module):source=data
	if not source or not source.modules.has(module): return null
	var mesh := ArrayMesh.new()
	mesh.resource_name = key
	var half := 2.0 if module == "wall_door_double" else 1.0
	for surface: Dictionary in source.modules[module]:
		var original: PackedVector3Array = surface.vertices
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		var source_uv: PackedVector2Array = surface.uv
		var gradient: PackedVector2Array = surface.uv_dx
		for t in range(0, original.size(), 3):
			var points: Array[Vector3] = []
			var coords: Array[Vector2] = []
			var deformed := false
			for i in range(t, t + 3):
				var p := original[i]
				if start_mask and p.x <= -half + .11001:
					p.x = -half + _cut(start_mask, p.z)
				elif end_mask and p.x >= half - .11001:
					p.x = half - _cut(end_mask, p.z)
				deformed=deformed or not p.is_equal_approx(original[i])
				points.append(p)
				coords.append(source_uv[i] + gradient[i] * (p.x - original[i].x))
			# Godot's front winding is clockwise. Keep both authored wall skins.
			var cross := (points[2] - points[0]).cross(points[1] - points[0])
			if cross.length_squared() < 1e-14: continue
			var normal := cross.normalized()
			for i in 3:
				vertices.append(points[i]); normals.append(normal if deformed else surface.normals[t+i]); uv.append(coords[i])
		if vertices.is_empty(): continue
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: Material = source.materials[surface.material]
		mesh.surface_set_material(mesh.get_surface_count()-1, material_overrides.get(mat.resource_name, mat))
	_meshes[key] = mesh
	return mesh

func shape_for(module: String, start_mask := 0, end_mask := 0) -> Shape3D:
	_ensure_caches()
	var key := "%s:%d:%d" % [module, start_mask, end_mask]
	if not _shapes.has(key):
		var mesh := mesh_for(module, start_mask, end_mask)
		if not mesh or mesh.get_surface_count()==0:return null
		var shape := mesh.create_trimesh_shape()
		if not shape:return null
		shape.backface_collision = true
		_shapes[key] = shape
	return _shapes[key]

func invalidate() -> void:
	_ensure_caches()
	_meshes.clear(); _shapes.clear(); emit_changed()

func _ensure_caches() -> void:
	if typeof(_meshes)!=TYPE_DICTIONARY:_meshes={}
	if typeof(_shapes)!=TYPE_DICTIONARY:_shapes={}

static func _cut(mask: int, depth: float) -> float:
	var result := -INF
	if mask & 1: result = 0.0 # collinear neighbour
	if mask & 2: result = maxf(result, depth)
	if mask & 4: result = maxf(result, -depth)
	return 0.0 if is_inf(result) else result
