@tool
class_name InteractivePart3D
extends "res://scripts/world_events/world_interaction_3d.gd"
## Shared picking/unlit-hover contract. Inventory placement is one specialization.
@export_group("Partie visible et survol")
@export_node_path("Node3D") var visual_path: NodePath
@export var require_visible_model := true
@export var selection_label := "INTERAGIR"
@export_node_path("Area3D") var selection_area_path: NodePath
## Meshes ou branches qui passent en unlit au survol, en gardant leurs textures.
## Chemins relatifs a cette partie.
@export var highlight_paths: Array[NodePath]=[]
@export_storage var outline_color := Color(.87,.84,.67)
## Decoche pour un bouton exterieur utilisable meme si le couvercle reste ferme.
@export var requires_open := true
const SELECTION_LAYER := 1<<19
var _busy := false
var _selection_area: Area3D
func is_item_socket() -> bool:return false
func get_selection_label() -> String:return selection_label
func _world_available() -> bool:return super.can_interact()
func placement_owner() -> Node3D:
	var parent := get_parent()
	while parent:
		if parent.has_method("is_placement_scene"):return parent as Node3D
		parent=parent.get_parent()
	return null
func _id() -> StringName:
	var root := placement_owner()
	return StringName("%s.%s" % [root._id(),root.get_path_to(self)]) if root and interaction_id.is_empty() else super._id()
func can_select_part(ignore_busy := false) -> bool:
	return (ignore_busy or not _busy) and _world_available() and (not require_visible_model or has_visible_model()) and WorldCondition.all_match(requirements)
func can_interact() -> bool:return not placement_owner() and not _busy and _world_available() and WorldCondition.all_match(requirements)
func selection_area() -> Area3D:
	if not selection_area_path.is_empty():return get_node_or_null(selection_area_path) as Area3D
	if Engine.is_editor_hint():return null
	if not is_instance_valid(_selection_area):
		_selection_area=Area3D.new();_selection_area.name="SelectionAutomatique";_selection_area.position=interaction_offset
		_selection_area.collision_layer=SELECTION_LAYER;_selection_area.collision_mask=0;_selection_area.monitoring=false;_selection_area.monitorable=false;_selection_area.input_ray_pickable=false
		var volume := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(.4,.4,.3);volume.shape=box;_selection_area.add_child(volume);add_child(_selection_area)
	return _selection_area
func highlight_roots() -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for path in highlight_paths:
		var node := get_node_or_null(path) as Node3D
		if node:result.append(node)
	if result.is_empty():
		var visual := get_node_or_null(visual_path) as Node3D if not visual_path.is_empty() else self
		if visual:result.append(visual)
	return result
func has_visible_model() -> bool:
	var visual := get_node_or_null(visual_path) as Node3D if not visual_path.is_empty() else self
	if not visual or not visual.is_visible_in_tree():return false
	if visual is MeshInstance3D and visual.mesh:return true
	return visual.find_children("*","MeshInstance3D",true,false).any(func(mesh: Node):return mesh.mesh!=null and mesh.is_visible_in_tree())
func configuration_error() -> String:
	if not visual_path.is_empty() and not get_node_or_null(visual_path) is Node3D:return "Visual Path doit viser le modele visible."
	for path in highlight_paths:
		if not get_node_or_null(path) is Node3D:return "Mesh de survol introuvable : "+String(path)
	if not selection_area_path.is_empty():
		var area := selection_area()
		if not area:return "Selection Area Path doit viser la ZoneSelection de cette partie."
		if (area.collision_layer&SELECTION_LAYER)==0:return "ZoneSelection doit utiliser la couche physique 20."
		if not area.find_children("*","CollisionShape3D",true,false).any(func(shape: Node):return shape.shape!=null and not shape.disabled):return "Ajouter une CollisionShape3D active dans ZoneSelection."
	return ""
func _get_configuration_warnings() -> PackedStringArray:
	if not is_inside_tree():return []
	var result := PackedStringArray();var error := configuration_error()
	if not error.is_empty():result.append(error)
	if require_visible_model and not has_visible_model():result.append("Choisir un modele visible ou ajouter ses meshes sous cette partie.")
	return result
