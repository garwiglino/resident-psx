@tool
class_name PSXUnlitMaterial
extends StandardMaterial3D
## Autonomous PSX surface: texture * color, without any light contribution.
## StandardMaterial3D also provides the matching ordinary Godot editor preview.
@export_color_no_alpha var color := Color.WHITE:
	set(value):color=Color(value.r,value.g,value.b,1);albedo_color=color;emit_changed()
@export var texture: Texture2D:
	set(value):
		if texture and texture.changed.is_connected(_texture_changed):texture.changed.disconnect(_texture_changed)
		texture=value;albedo_texture=value
		if texture and not texture.changed.is_connected(_texture_changed):texture.changed.connect(_texture_changed)
		emit_changed()
func _init() -> void:
	shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	metallic=0;metallic_specular=0;roughness=1
	texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;alpha_scissor_threshold=.5
	albedo_color=color;albedo_texture=texture
func _texture_changed() -> void:emit_changed()
func is_psx_unlit() -> bool:return true
func _validate_property(property: Dictionary) -> void:
	# Keep an ordinary draggable Material resource with only meaningful controls.
	if property.name not in ["color","texture","resource_name","resource_local_to_scene","script"]:property.usage&=~PROPERTY_USAGE_EDITOR
