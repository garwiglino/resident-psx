extends RefCounted
## Keep the factory standalone: the Blender bridge also loads this script in a
## minimal project. Custom runtime materials identify themselves without preloads.

static var snap_enabled := true
static var affine_enabled := true

static func initialize() -> void:
	snap_enabled=true
	affine_enabled=true

static func make(color: Color, texture: Texture2D = null, tiling := Vector2.ONE, glow := Color.BLACK) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	# Lighting is computed by the native PSX geometry path, like the level.
	# Also disable all specular sources in the ordinary Godot editor viewport.
	mat.diffuse_mode=BaseMaterial3D.DIFFUSE_LAMBERT
	mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	mat.metallic=0.0
	mat.metallic_specular=0.0
	mat.roughness=1.0
	mat.albedo_color=color
	mat.albedo_texture=texture
	mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale=Vector3(tiling.x,tiling.y,1)
	mat.emission_enabled=glow!=Color.BLACK
	mat.emission=glow
	return mat

static func character_material(source: Material,tint := Color.WHITE) -> StandardMaterial3D:
	if source is StandardMaterial3D and source.has_method("is_psx_unlit") and source.call("is_psx_unlit"):
		var custom := source.duplicate() as StandardMaterial3D
		custom.set("color",source.get("color")*tint)
		return custom
	if source is StandardMaterial3D and source.has_method("is_psx_reflective"):
		var reflective := source.duplicate() as StandardMaterial3D
		reflective.albedo_color*=tint
		return reflective
	var texture: Texture2D
	var color := Color.WHITE
	if source is StandardMaterial3D:
		texture=source.albedo_texture;color=source.albedo_color
	# Fresh materials discard imported normal/PBR maps, clearcoat and extra passes.
	var material := make(color*tint,texture)
	if source:material.resource_name=source.resource_name
	if source is StandardMaterial3D:
		material.uv1_scale=source.uv1_scale;material.uv1_offset=source.uv1_offset
		material.cull_mode=source.cull_mode
		material.transparency=source.transparency
		material.alpha_scissor_threshold=source.alpha_scissor_threshold
	return material

static func apply_character(node: Node, tint := Color.WHITE) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			node.set_surface_override_material(i,character_material(node.get_active_material(i),tint))
	for child in node.get_children():
		apply_character(child, tint)
