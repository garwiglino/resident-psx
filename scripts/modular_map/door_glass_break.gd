@tool
extends StaticBody3D

const AudioRouting = preload("res://scripts/audio/psx_audio_routing.gd")
const SHARD_LIFETIME := 4.0
const DUST_FPS := 24.0
const DUST_FRAMES := 5

var state_key: StringName
var intact: MeshInstance3D
var rim: MeshInstance3D
var pane_shape: CollisionShape3D
var shards: Array[RigidBody3D] = []
var dust: MeshInstance3D
var sound: AudioStreamPlayer3D
var _broken := false
var _age := 0.0
var _random := RandomNumberGenerator.new()

func configure(geometry: Dictionary, fit: Dictionary, material: StandardMaterial3D, dust_atlas: Texture2D,
		stream: AudioStream, volume_db: float) -> void:
	collision_layer = 1
	collision_mask = 0
	var bounds := intact.mesh.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = bounds.size.max(Vector3(.002, .002, .012))
	pane_shape = CollisionShape3D.new()
	pane_shape.shape = shape
	pane_shape.position = bounds.get_center()
	add_child(pane_shape)
	rim = _visual("BordureCassée", _mesh(geometry.rim, material, fit))
	rim.hide()
	add_child(rim)
	if Engine.is_editor_hint():return

	var physics := PhysicsMaterial.new()
	physics.friction = .5
	physics.bounce = .32
	var shard_material := material.duplicate() as StandardMaterial3D
	if shard_material is PSXReflectiveMaterial:
		shard_material.scene_reflection = 0.0
		shard_material.reflection_projection = PSXReflectiveMaterial.ReflectionProjection.ENVIRONMENT
	for piece: Dictionary in geometry.shards:
		var body := RigidBody3D.new()
		body.name = piece.name
		body.top_level = true
		body.freeze = true
		body.mass = .035
		body.collision_layer = 0
		body.collision_mask = 0
		body.continuous_cd = true
		body.physics_material_override = physics
		body.linear_damp = .35
		body.angular_damp = .55
		body.set_meta("glass_home", _fit_point(_point(piece.origin), fit))
		add_child(body)
		# Godot treats Node3D visibility independently of physics. Pre-register
		# the meshes once so a break never rebuilds the PSX atlas.
		var mesh := _mesh(piece, shard_material, fit, true)
		body.add_child(_visual("Éclat", mesh))
		var hull := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			points.append(vertex + Vector3.BACK * .007)
			points.append(vertex - Vector3.BACK * .007)
		hull.points = points
		var collider := CollisionShape3D.new()
		collider.shape = hull
		body.add_child(collider)
		body.hide()
		shards.append(body)

	var quad := QuadMesh.new()
	var sprite_material := StandardMaterial3D.new()
	sprite_material.albedo_texture = dust_atlas
	sprite_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sprite_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = sprite_material
	dust = _visual("PoussièreDeVerre", quad)
	dust.top_level = true
	dust.add_to_group("psx_sprite")
	dust.hide()
	add_child(dust)
	set_break_sound(stream, volume_db)

func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():return
	_random.randomize()
	WorldEvents.state_changed.connect(_state_changed)
	WorldEvents.run_reset.connect(_restore_state)
	_restore_state()

func set_break_sound(stream: AudioStream, volume_db: float) -> void:
	if not sound:
		if not stream:return
		sound = AudioStreamPlayer3D.new()
		sound.name = "SonBrisDeVerre"
		sound.unit_size = 5.0
		sound.max_distance = 26.0
		sound.top_level = true
		add_child(sound)
		AudioRouting.set_category(sound, &"Interactions")
	sound.stream = stream
	sound.volume_db = volume_db

func break_on_impact(point: Vector3, direction: Vector3) -> bool:
	if Engine.is_editor_hint() or _broken or not WorldEvents.set_fact(state_key, true):return false
	_set_broken(true)
	var normal := global_basis.z.normalized()
	var outward := normal if direction.dot(normal) >= 0.0 else -normal
	var burst := (outward * .75 + direction.normalized() * .25).normalized()
	for body in shards:
		var center := to_global(body.get_meta("glass_home"))
		var tangent := (center - point).slide(normal).limit_length(.45)
		var side := -1.0 if _random.randf() < .14 else 1.0
		body.global_transform = Transform3D(global_basis.orthonormalized(), center + outward * side * .035)
		body.collision_mask = 1
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = (burst * side * _random.randf_range(.85, 2.6) + tangent * 3.2
			+ Vector3.UP * _random.randf_range(.2, 1.05))
		body.angular_velocity = Vector3(_random.randf_range(-11, 11), _random.randf_range(-10, 10), _random.randf_range(-12, 12))
		body.show()
	dust.global_position = point - outward * .075
	dust.set_meta("psx_sprite_frame", 0)
	dust.show()
	if sound:
		sound.global_position = point
		AudioRouting.play(sound)
	_age = 0.0
	set_process(true)
	WorldEvents.raise_event(state_key)
	return true

func _process(delta: float) -> void:
	_age += delta
	if dust.visible and _age * DUST_FPS >= DUST_FRAMES:dust.hide()
	if _age >= SHARD_LIFETIME:_stop_effects()

func update_glass_dust(view_basis: Basis) -> void:
	if not is_instance_valid(dust) or not dust.visible:return
	var frame := mini(floori(_age * DUST_FPS), DUST_FRAMES - 1)
	var size := lerpf(.48, 1.0, float(frame) / (DUST_FRAMES - 1))
	dust.global_basis = view_basis.scaled_local(Vector3.ONE * size)
	dust.set_meta("psx_sprite_frame", frame)

func _set_broken(value: bool) -> void:
	_broken = value
	intact.visible = not value
	rim.visible = value
	# Remove the pane from both world collision and subsequent shot queries.
	collision_layer = 0 if value else 1
	pane_shape.set_deferred("disabled", value)

func _stop_effects() -> void:
	set_process(false)
	dust.hide()
	for body in shards:
		body.hide()
		body.freeze = true
		body.collision_mask = 0

func _state_changed(key: StringName, value: Variant) -> void:
	if key == state_key and bool(value) != _broken:_restore_state()

func _restore_state() -> void:
	_set_broken(bool(WorldEvents.fact(state_key)))
	_stop_effects()
	if sound:AudioRouting.stop(sound)

static func _point(row: Array) -> Vector3:
	return Vector3(row[0], row[1], row[2])

static func fit_pane(geometry: Dictionary, pane: ArrayMesh, mirrored: bool, authored_uv: bool) -> Dictionary:
	var target := pane.get_aabb()
	if target.size.x < .05 or target.size.y < .05 or target.size.z > .002:return {}
	var first := _point(geometry.rim.triangles[0][0][0])
	var original := AABB(first, Vector3.ZERO)
	for triangle: Array in geometry.rim.triangles:
		for row: Array in triangle:original=original.expand(_point(row[0]))
	if original.size.x <= 0.0 or original.size.y <= 0.0:return {}
	var arrays := pane.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if indices.is_empty():
		for index in vertices.size():indices.append(index)
	# Check that one face covers the full rectangle, irrespective of which
	# side is present in an individually exported pane.
	var front_area := 0.0
	var back_area := 0.0
	var triangles: Array[Dictionary] = []
	for i in range(0, indices.size(), 3):
		var a := Vector2(vertices[indices[i]].x, vertices[indices[i]].y)
		var b := Vector2(vertices[indices[i+1]].x, vertices[indices[i+1]].y) - a
		var c := Vector2(vertices[indices[i+2]].x, vertices[indices[i+2]].y) - a
		var det := b.cross(c)
		if absf(det) <= .000001:continue
		if det < 0.0:front_area -= det * .5
		else:back_area += det * .5
		if not uvs.is_empty():
			triangles.append({"origin":a, "b":b, "c":c, "det":det,
				"uvs":[uvs[indices[i]], uvs[indices[i+1]], uvs[indices[i+2]]]})
	if absf(maxf(front_area, back_area) - target.size.x * target.size.y) > .001:return {}
	var scale := Vector3(target.size.x / original.size.x, target.size.y / original.size.y, 1.0)
	if mirrored:scale.x *= -1.0
	return {"scale":scale, "offset":target.get_center() - original.get_center() * scale,
		"triangles":triangles, "authored_uv":authored_uv}

static func _fit_point(point: Vector3, fit: Dictionary) -> Vector3:
	return point * fit.scale + fit.offset

static func _sample_uv(point: Vector3, fit: Dictionary) -> Vector2:
	for triangle: Dictionary in fit.triangles:
		var delta := Vector2(point.x, point.y) - (triangle.origin as Vector2)
		var u := delta.cross(triangle.c) / float(triangle.det)
		var v := (triangle.b as Vector2).cross(delta) / float(triangle.det)
		if u >= -.001 and v >= -.001 and u + v <= 1.001:
			var uv: Array = triangle.uvs
			return uv[0] * (1.0-u-v) + uv[1] * u + uv[2] * v
	return Vector2.ZERO

static func _visual(label: String, mesh: Mesh) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	return visual

static func _mesh(piece: Dictionary, material: StandardMaterial3D, fit: Dictionary, fragment := false) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var scale: Vector3 = fit.scale
	var origin := _point(piece.origin) if fragment else Vector3.ZERO
	var mirrored := scale.x < 0.0
	# Blender's pieces are flat. Duplicate the opposite side for the PSX
	# renderer, which uses explicit winding rather than material cull mode.
	for triangle: Array in piece.triangles:
		for back in [false, true]:
			for index in ([0, 2, 1] if back != mirrored else [0, 1, 2]):
				var row: Array = triangle[index]
				var point := _point(row[0])
				var fitted := _fit_point(point + origin, fit)
				vertices.append(point * scale if fragment else fitted)
				normals.append((_point(row[1]) / scale).normalized() * (-1.0 if back else 1.0))
				if fit.authored_uv:
					var uv: Array = row[2]
					# The original fracture's atlas page starts at (256,256).
					uvs.append(Vector2(uv[0] * 8.0 - 4.0, 3.0 - uv[1] * 4.0))
				else:
					uvs.append(_sample_uv(fitted, fit))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
