@tool
class_name CharacterAppearance
extends Node
const Materials=preload("res://scripts/psx_materials.gd")
const FaceTextures=preload("res://scripts/face_texture_pages.gd")
@export_node_path("Node3D") var model_path := NodePath("../Visual/CharacterMotion/cop")
## Texture du corps. Vide = texture Blender.
## Le visage, les cheveux et les vetements ont leurs propres textures.
@export var texture_corps: Texture2D:
	set(value):
		if texture_corps==value:return
		if texture_corps and texture_corps.changed.is_connected(_apply):texture_corps.changed.disconnect(_apply)
		texture_corps=value
		if texture_corps:texture_corps.changed.connect(_apply)
		if is_node_ready():_apply()
var _model: Node3D
var _surfaces: Array[Dictionary]=[]
var _signature: Array=[]
var _editor_clock := 0.0

func _ready() -> void:
	refresh();set_process(Engine.is_editor_hint())

func _process(delta: float) -> void:
	_editor_clock+=delta
	if _editor_clock<.3:return
	_editor_clock=0
	if get_node_or_null(model_path)!=_model or _mesh_signature()!=_signature:refresh();return
	for surface in _surfaces:
		if not is_instance_valid(surface.node) or surface.node.get_active_material(surface.index)!=surface.material:refresh();return

func _body_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D]=[]
	if not is_instance_valid(_model):return result
	for node in _model.find_children("*","MeshInstance3D",true,false):
		if node.mesh and String(node.name) in ["cop_char","cop_coat_mask","cop_hair"]:result.append(node)
	return result

func _mesh_signature() -> Array:
	var result: Array=[]
	for node in _body_meshes():
		var source: Mesh=node.get_meta(&"psx_clothing_source_mesh",node.mesh)
		result.append_array([node.get_instance_id(),source.get_rid()])
		for index in source.get_surface_count():result.append(source.surface_get_material(index))
	return result

func refresh() -> void:
	_surfaces.clear();_model=get_node_or_null(model_path)
	for node in _body_meshes():
		for index in node.mesh.get_surface_count():
			var source: Material=node.mesh.surface_get_material(index)
			if FaceTextures.part(source):continue
			var material := Materials.character_material(source)
			node.set_surface_override_material(index,material)
			_surfaces.append({"node":node,"index":index,"material":material,"original_texture":material.albedo_texture,"body_texture":node.name!=&"cop_hair"})
	_signature=_mesh_signature();_apply()

func _apply() -> void:
	for surface in _surfaces:
		if is_instance_valid(surface.node):surface.material.albedo_texture=texture_corps if texture_corps and surface.body_texture else surface.original_texture
	if Engine.is_editor_hint() or not is_instance_valid(_model):return
	var ancestor := get_parent()
	while ancestor:
		var renderer := ancestor.get_node_or_null("PSXRenderer")
		if renderer and renderer.get("raster")!=null:
			renderer.refresh_materials(_model);return
		if ancestor is Viewport:break
		ancestor=ancestor.get_parent()
