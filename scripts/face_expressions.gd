@tool
class_name FaceExpressions
extends Node
const Textures=preload("res://scripts/face_texture_pages.gd")
const Materials=preload("res://scripts/psx_materials.gd")
@export var enabled := true:
	set(value):enabled=value;_apply()
@export_enum("Neutre","Mi-clignement","Ferme","Alerte","Colere","Inquietude","Regard haut","Regard bas") var top_frame := 0:
	set(value):top_frame=clampi(value,0,7);_apply()
@export_enum("Repos","A-AA","E-I","O-OU","M-B-P","F-V","Sourire","Dents serrees") var bottom_frame := 0:
	set(value):bottom_frame=clampi(value,0,7);_apply()
@export_node_path("Node3D") var model_path := NodePath("../Visual/CharacterMotion/cop")
var _surfaces: Array[Dictionary]=[]

func _ready() -> void:refresh()

func refresh() -> void:
	_surfaces.clear()
	var model := get_node_or_null(model_path)
	if model:_find_surfaces(model)
	_apply()

func _find_surfaces(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var part := Textures.part(node.mesh.surface_get_material(surface))
			if not part:continue
			var source: Material=node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := Materials.character_material(source)
				# 3D materials sample the whole texture RID: AtlasTexture.region
				# only crops 2D drawing. Select the facial tile through UV1 instead.
				material.albedo_texture=Textures.TOP if part==1 else Textures.BOTTOM
				material.uv1_scale=Vector3(.25,.5,1)
				material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
				node.set_surface_override_material(surface,material)
				_surfaces.append({"node":node,"part":part,"material":material})
	for child in node.get_children():_find_surfaces(child)

func _apply() -> void:
	# Replace materials cached by the previous tool-script version on hot reload.
	if not _surfaces.is_empty() and not _surfaces[0].has("material"):refresh();return
	for surface in _surfaces:
		if not is_instance_valid(surface.node):continue
		var frame: int=(top_frame if surface.part==1 else bottom_frame) if enabled else 0
		surface.node.set_meta("psx_face_top_frame" if surface.part==1 else "psx_face_bottom_frame",frame)
		surface.material.uv1_offset=Vector3((frame%4)*.25,(frame/4)*.5,0)

func set_expression(eyes: int,mouth: int) -> void:
	top_frame=eyes;bottom_frame=mouth

func set_preset(id: StringName) -> bool:
	var presets: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/face/expressions.json")).get("presets",{})
	if not presets.has(String(id)):return false
	set_expression(int(presets[String(id)][0]),int(presets[String(id)][1]));return true
