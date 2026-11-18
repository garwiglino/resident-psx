@tool
class_name PSXLightShaftMaterial
extends StandardMaterial3D
## PSX ABR=3: B + F/4. The texture stores intensity in RGB, with binary cutout.
@export_color_no_alpha var color := Color(.82,.86,1):
	set(value):color=Color(value.r,value.g,value.b,1);_sync()
@export_range(0,2,.025) var strength := .8:
	set(value):strength=clampf(value,0,2);_sync()
@export var texture: Texture2D:
	set(value):
		if texture and texture.changed.is_connected(_texture_changed):texture.changed.disconnect(_texture_changed)
		texture=value;albedo_texture=value
		if texture and not texture.changed.is_connected(_texture_changed):texture.changed.connect(_texture_changed)
		emit_changed()
func _init() -> void:
	resource_local_to_scene=true
	shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	metallic=0;metallic_specular=0;roughness=1;texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;blend_mode=BaseMaterial3D.BLEND_MODE_ADD;depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	_sync()
func _sync() -> void:
	# Matching ordinary Godot preview. Native PSX reads color/strength before its integer F/4.
	albedo_color=Color(color.r*strength*.25,color.g*strength*.25,color.b*strength*.25,1);emit_changed()
func _texture_changed() -> void:emit_changed()
func is_psx_unlit() -> bool:return true
func _validate_property(property: Dictionary) -> void:
	if not Engine.is_editor_hint():return
	if property.name not in ["color","texture","strength","resource_name","resource_local_to_scene","script"]:property.usage&=~PROPERTY_USAGE_EDITOR
