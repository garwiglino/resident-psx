@tool
class_name ItemPlacementScene3D
extends "res://scripts/world_events/world_interaction_3d.gd"
const Pose=preload("res://scripts/inventory/placement_pose.gd")
const Access=preload("res://scripts/inventory/mechanism_access.gd")
const AccessSettings=preload("res://scripts/inventory/mechanism_access_settings.gd")
## One authored scene, one inspection camera, several independent sockets.
@export_node_path("Camera3D") var camera_path: NodePath=NodePath("CameraFixe")
@export var hide_player_in_view := true
@export var close_when_complete := true
## Permettre une nouvelle inspection meme apres la pose de toutes les pieces.
@export var inspect_when_complete := false
@export_group("Ouverture et fermeture physiques")
## Clips et chemins relatifs a cette racine. Enabled active le couvercle independamment des pieces.
@export var access_settings: MechanismAccessSettings=AccessSettings.new()
var _access: Node
var _busy := false
var _initial_pose: RefCounted
var _detached_meshes: Array[Dictionary]=[]
func is_placement_scene() -> bool:return true
func _enter_tree() -> void:
	super._enter_tree();add_to_group("psx_dynamic_geometry")
	for state in _detached_meshes:
		var mesh=state.node.get_ref()
		if mesh:mesh.mesh=state.geometry
	_detached_meshes.clear()
	if not Engine.is_editor_hint() and not _initial_pose:_initial_pose=Pose.new();_initial_pose.capture(self,false)
	if is_node_ready() and not Engine.is_editor_hint():call_deferred("_restore")
func _exit_tree() -> void:
	if Engine.is_editor_hint():return
	for mesh: MeshInstance3D in find_children("*","MeshInstance3D",true,false):
		if mesh.mesh:_detached_meshes.append({"node":weakref(mesh),"geometry":mesh.mesh});mesh.mesh=null
func _ready() -> void:
	if not Engine.is_editor_hint():WorldEvents.run_reset.connect(func():call_deferred("_restore"));call_deferred("_restore")
	if not Engine.is_editor_hint():get_mechanism_access()
	refresh_render_geometry(self)
func access_configuration_error() -> String:return access_settings.validation_error(self) if access_settings else ""
func get_mechanism_access() -> Node:
	if Engine.is_editor_hint() or not access_settings or not access_settings.enabled:return null
	if not is_instance_valid(_access):
		_access=Access.new();_access.name="OuvertureFermeture";_access.settings=access_settings;_access.state_id=_id();add_child(_access)
	return _access
func _restore() -> void:
	if _busy or not is_inside_tree() or not _initial_pose:return
	_initial_pose.restore()
	for part in placement_targets():part._sync()
	var access := get_mechanism_access()
	if access:access.restore_saved_state()
func placement_targets() -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for node in find_children("*","Node3D",true,false):
		if node.has_method("placement_owner") and node.placement_owner()==self:result.append(node)
	return result
func all_installed() -> bool:
	var parts := placement_targets().filter(func(part: Node3D):return part.is_item_socket())
	return not parts.is_empty() and parts.all(func(part: Node3D):return WorldEvents.interaction_used(part._id()))
func can_interact() -> bool:
	var allowed := enabled and is_visible_in_tree() if inspect_when_complete else super.can_interact()
	return not _busy and allowed and (inspect_when_complete or placement_targets().any(func(part: Node3D):return part.can_select_part()))
func accepts_inventory_item(id: StringName) -> bool:
	return placement_targets().any(func(part: Node3D):return part.is_item_socket() and part.required_id()==id and part.can_select_part())
func configuration_error() -> String:
	var access_error := access_configuration_error()
	if not access_error.is_empty():return access_error
	if not get_node_or_null(camera_path) is Camera3D:return "Choisir la CameraFixe de cette scene de placement."
	if placement_targets().is_empty():return "Ajouter une partie interactive : bouton, interrupteur ou emplacement."
	# Each part is validated when selected; an unfinished sibling must not block inspection.
	for action in actions:
		if not action:return "Action de fin vide."
		var error: String=action.validation_error(self)
		if not error.is_empty():return error
	return ""
func interact(player: Node3D=null) -> bool:
	if Engine.is_editor_hint() or not can_interact() or not WorldCondition.all_match(requirements):return false
	var game := WorldEvents.game_for(self)
	if not game or not is_instance_valid(game.item_placement):return false
	if game.inventory_menu.opened:game.inventory_menu.close()
	return game.item_placement.begin(self,player)
func publish_installation(player: Node3D) -> void:
	if not interaction_event.is_empty():WorldEvents.raise_event(interaction_event)
	WorldEvents.execute(actions,self);interacted.emit(player)
func _get_configuration_warnings() -> PackedStringArray:
	if not is_inside_tree():return []
	var warnings := PackedStringArray();var error := configuration_error()
	if not error.is_empty():warnings.append(error)
	for part in placement_targets():
		var part_error: String=part.configuration_error()
		if not part_error.is_empty():warnings.append("%s : %s" % [part.name,part_error])
	if interaction_id.is_empty():warnings.append("Donner un Interaction Id unique sur chaque instance dans la carte. Les emplacements heritent de cet Id.")
	return warnings
