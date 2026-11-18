@tool
class_name PSXReflectiveMaterial
extends StandardMaterial3D
## A vertex-projected reflection texture for the PSX renderer.

enum ReflectionProjection { UV, PLANAR_XY, PLANAR_XZ, ENVIRONMENT }

@export_group("Reflet PSX")
## Bandes et aplats dessines. Alpha progressif sur le verre, decoupe a 50 % sur les surfaces opaques.
@export var reflection_texture: Texture2D:
	set(value):
		if reflection_texture and reflection_texture.changed.is_connected(emit_changed):
			reflection_texture.changed.disconnect(emit_changed)
		reflection_texture=value
		if reflection_texture and not reflection_texture.changed.is_connected(emit_changed):
			reflection_texture.changed.connect(emit_changed)
		emit_changed()
@export var reflection_projection: ReflectionProjection = ReflectionProjection.PLANAR_XY:
	set(value): reflection_projection=value;emit_changed()
@export_range(0,2,.025) var reflection_strength := .8:
	set(value): reflection_strength=clampf(value,0,2);emit_changed()
## Part du decor reflete en direct. Disponible sur une surface plane XY ou XZ.
@export_range(0,1,.025) var scene_reflection := 0.0:
	set(value): scene_reflection=clampf(value,0,1);emit_changed()
## 1 = reflet direct des lampes PSX. 0 = reflet peint module par l'eclairage ambiant.
@export_range(0,1,.025) var reflection_light_response := .85:
	set(value): reflection_light_response=clampf(value,0,1);emit_changed()
## Glissement du reflet peint de secours avec le point de vue.
@export_range(0,.75,.005) var reflection_motion := .13:
	set(value): reflection_motion=clampf(value,0,.75);emit_changed()
## Largeur de l'image d'une lampe sur la surface (en metres pour XY et XZ).
@export_range(.15,8,.05,"suffix:m") var reflection_width := 1.15:
	set(value): reflection_width=clampf(value,.15,8);emit_changed()
@export_range(.25,4,.025) var reflection_scale := 1.0:
	set(value): reflection_scale=clampf(value,.25,4);emit_changed()
@export_range(-180,180,1,"suffix:deg") var reflection_angle := 0.0:
	set(value): reflection_angle=value;emit_changed()
@export var reflection_offset := Vector2.ZERO:
	set(value): reflection_offset=value;emit_changed()

func _init() -> void:
	shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	metallic=0.0
	metallic_specular=0.0
	roughness=1.0

func is_psx_reflective() -> bool:
	return true

## Apply the reflection settings to an existing modular surface, preserving the
## authored albedo page, transparency and UVs.
func with_base(base: StandardMaterial3D) -> StandardMaterial3D:
	var material := duplicate() as StandardMaterial3D
	material.resource_name=base.resource_name
	material.albedo_color=base.albedo_color
	material.albedo_texture=base.albedo_texture
	material.uv1_scale=base.uv1_scale
	material.uv1_offset=base.uv1_offset
	material.transparency=base.transparency
	material.alpha_scissor_threshold=base.alpha_scissor_threshold
	material.cull_mode=base.cull_mode
	material.emission_enabled=base.emission_enabled
	material.emission=base.emission
	return material
