@tool
class_name InventoryUseTarget3D
extends "res://scripts/interactions/interactive_part.gd"
const Pose=preload("res://scripts/inventory/placement_pose.gd")
const Access=preload("res://scripts/inventory/mechanism_access.gd")
const AccessSettings=preload("res://scripts/inventory/mechanism_access_settings.gd")
const Visuals=preload("res://scripts/inventory/item_visuals.gd")
const Materials=preload("res://scripts/psx_materials.gd")
## Deposer ici la definition .tres de la piece attendue. Son Id prime sur Required Item Id.
@export var required_item: InventoryItemDefinition
@export var required_item_id: StringName
@export_range(1,999,1) var required_quantity := 1
## Retirer la piece uniquement apres insertion et animation reussies. Desactiver pour un outil reutilisable.
@export var consume_item := true
@export_group("Modele du mecanisme")
## Racine de la piece deja alignee dans la scene. Vide : utiliser le World Model de Required Item au point de fixation.
@export_node_path("Node3D") var installed_visual_path: NodePath
@export_group("Interaction avec choix d'objet")
## E ouvre la camera fixe et tous les objets placables possedes. Faux : ancienne utilisation directe.
@export var use_selection_view := true
@export var inspect_when_complete := false
@export var hide_player_in_view := true
## D'abord survoler/cliquer le socle dans la vue fixe, puis choisir l'objet.
@export var select_part_first := true
## Camera fixe utilisee uniquement pour une cible autonome.
@export_node_path("Camera3D") var camera_path: NodePath
## Marker3D, ou Marker3D sous un BoneAttachment3D pour suivre un os.
@export_node_path("Node3D") var placement_socket_path: NodePath
## Point d'apparition de la piece, puis deplacement doux jusqu'a sa position installee.
@export_node_path("Node3D") var placement_start_path: NodePath
## Decalage local utilise si la piece est creee depuis le World Model de l'objet.
@export var placement_offset := Transform3D.IDENTITY
@export_range(.05,5,.05,"suffix:s") var placement_duration := .6
## Une seule ligne aleatoire de cette sequence par mauvais choix, sans repetition consecutive.
@export var wrong_item_dialogue: DialogueSequence=preload("res://assets/audio/dialogs/wrong_item/wrong_item.tres")
@export_group("Animation du mecanisme apres insertion")
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
## Nom exact du clip, joue apres insertion. Pose finale conservee ; gameplay via Actions, pas via pistes de methodes.
@export var installation_animation: StringName
@export_range(.1,4,.05) var installation_animation_speed := 1.0
@export_group("Sons du mecanisme")
@export var insertion_sound: AudioStream
@export var installed_sound: AudioStream
@export_range(-40,0,.5,"suffix:dB") var mechanism_volume_db := -12.0
@export_group("Ouverture et fermeture physiques - racine seule")
@export var access_settings: MechanismAccessSettings=AccessSettings.new()
var _access: Node
var _piece: Node3D
var _piece_final := Transform3D.IDENTITY
var _detached_meshes: Array[Dictionary]=[]
var _initial_pose: RefCounted

func _init() -> void:selection_label="EMPLACEMENT"
func is_item_socket() -> bool:return true
func placement_targets() -> Array[Node3D]:return [self]
func all_installed() -> bool:return WorldEvents.interaction_used(_id())
func access_configuration_error() -> String:return access_settings.validation_error(self) if access_settings and not placement_owner() else ""
func get_mechanism_access() -> Node:
	var root := placement_owner()
	if root:return root.get_mechanism_access()
	if Engine.is_editor_hint() or not access_settings or not access_settings.enabled:return null
	if not is_instance_valid(_access):
		_access=Access.new();_access.name="OuvertureFermeture";_access.settings=access_settings;_access.state_id=_id();add_child(_access)
	return _access
func can_select_part(ignore_busy := false) -> bool:
	return super.can_select_part(ignore_busy) and not WorldEvents.interaction_used(_id())
func _enter_tree() -> void:
	super._enter_tree(); add_to_group("psx_dynamic_geometry")
	for state in _detached_meshes:
		var mesh=state.node.get_ref()
		if mesh:mesh.mesh=state.geometry
	_detached_meshes.clear()
	if is_node_ready() and not Engine.is_editor_hint(): call_deferred("_sync")
func _exit_tree() -> void:
	if Engine.is_editor_hint():return
	# Detach render instances before their private materials are released. Keep the
	# geometry for level reparenting, which exits the tree without freeing the map.
	for mesh: MeshInstance3D in find_children("*","MeshInstance3D",true,false):
		if mesh.mesh:
			_detached_meshes.append({"node":weakref(mesh),"geometry":mesh.mesh});mesh.mesh=null
func _ready() -> void:
	if not Engine.is_editor_hint():
		var inventory := get_node_or_null("/root/InventoryState")
		if inventory and required_item:inventory.register_item(required_item)
		prepare_piece()
		selection_area()
		_initial_pose=Pose.new();_initial_pose.capture(self,false)
		WorldEvents.state_changed.connect(_world_changed)
		WorldEvents.run_reset.connect(_defer_sync)
	_sync()
	if not Engine.is_editor_hint() and not placement_owner():get_mechanism_access()
	if not placement_owner():refresh_render_geometry(self)
func _defer_sync() -> void: call_deferred("_sync")
func _world_changed(key: StringName,_value: Variant) -> void:
	if key==&"world.restored" or key==StringName("interaction.%s.used" % _id()): _sync()
func _sync() -> void:
	if not is_inside_tree() or Engine.is_editor_hint() or _busy:return
	prepare_piece()
	var installed := WorldEvents.interaction_used(_id())
	if not installed and _initial_pose:_initial_pose.restore()
	if is_instance_valid(_piece):_piece.transform=_piece_final
	_show_installed(installed)
	if installed and animation_source() and not installation_animation.is_empty() and animation_source().has_animation(installation_animation):
		var pose := Pose.new();pose.capture(self);pose.begin(animation_source(),installation_animation,self,installation_animation_speed)
		pose.advance(pose.length);pose.finish(true)
	sync_socket()
	if not placement_owner():
		var access := get_mechanism_access()
		if access:access.restore_saved_state()
	else:
		# Children become ready before their root; never add a sibling component from here.
		var access: Node=placement_owner()._access
		if is_instance_valid(access):access.reapply_pose()
func _show_installed(value: bool) -> void:
	var installed: Node3D=_piece if is_instance_valid(_piece) else null
	if not installed and not installed_visual_path.is_empty():installed=get_node_or_null(installed_visual_path) as Node3D
	if installed: installed.visible=value
	if installed:
		var bodies: Array[Node]=installed.find_children("*","CollisionObject3D",true,false)
		if installed is CollisionObject3D:bodies.append(installed)
		for body in bodies:
			if not body.has_meta("placement_collision_layer"):
				body.set_meta("placement_collision_layer",body.collision_layer);body.set_meta("placement_collision_mask",body.collision_mask)
			body.collision_layer=int(body.get_meta("placement_collision_layer")) if value else 0
			body.collision_mask=int(body.get_meta("placement_collision_mask")) if value else 0
			if body is RigidBody3D:body.freeze=true

func required_id() -> StringName:return required_item.id if required_item else required_item_id
func item_definition() -> Resource:
	if required_item:return required_item
	var inventory := get_node_or_null("/root/InventoryState")
	if inventory:return inventory.resolve_item(required_id())
	for item in load("res://assets/inventory/catalogue.tres").items:
		if item and item.id==required_id():return item
	return null
func socket_node() -> Node3D:
	return get_node_or_null(placement_socket_path) as Node3D if not placement_socket_path.is_empty() else self
func animation_source() -> AnimationPlayer:
	return get_node_or_null(animation_player_path) as AnimationPlayer if not animation_player_path.is_empty() else null
func sync_socket() -> void:
	var branch: Node=_piece.get_parent() if is_instance_valid(_piece) else null
	while branch and branch!=self:
		if branch is BoneAttachment3D:branch.on_skeleton_update()
		branch=branch.get_parent()
func prepare_piece() -> Node3D:
	# A placement scene is authored with its real piece visible. Inspection and
	# validation must never create/hide geometry or change the saved editor pose.
	if Engine.is_editor_hint():
		return get_node_or_null(installed_visual_path) as Node3D if not installed_visual_path.is_empty() else null
	if is_instance_valid(_piece):return _piece
	if not installed_visual_path.is_empty():_piece=get_node_or_null(installed_visual_path) as Node3D
	elif item_definition() and socket_node():
		_piece=Node3D.new();_piece.name="PieceInstallee";_piece.transform=placement_offset;_piece.add_to_group("psx_dynamic_geometry")
		var model := Visuals.world(item_definition());Materials.apply_character(model)
		_piece.add_child(model);socket_node().add_child(_piece)
	if _piece:_piece_final=_piece.transform;_show_installed(false)
	return _piece
func configuration_error() -> String:
	var common := super.configuration_error()
	if not common.is_empty():return common
	var access_error := access_configuration_error()
	if not access_error.is_empty():return access_error
	if required_id().is_empty():return "Choisir l'objet a installer."
	if not item_definition() or not item_definition().can_place():return "L'objet requis doit etre un mecanisme ou avoir Placeable coche."
	if not camera_path.is_empty() and not get_node_or_null(camera_path) is Camera3D:return "Camera Path doit viser une Camera3D."
	if not placement_socket_path.is_empty() and not socket_node():return "Point de fixation introuvable."
	if not selection_area_path.is_empty():
		var area := selection_area()
		if not area:return "Selection Area Path doit viser la ZoneSelection de cet emplacement."
		if not area.find_children("*","CollisionShape3D",true,false).any(func(shape: Node):return (shape as CollisionShape3D).shape!=null and not (shape as CollisionShape3D).disabled):return "Ajouter une CollisionShape3D active dans ZoneSelection."
		if (area.collision_layer&SELECTION_LAYER)==0:return "ZoneSelection doit utiliser la couche physique 20."
	if not installation_animation.is_empty() and (not animation_source() or not animation_source().has_animation(installation_animation)):return "Animation d'installation introuvable dans Animation Player Path."
	for action in actions:
		if not action:return "Action de fin vide."
		var error: String=action.validation_error(self)
		if not error.is_empty():return error
	var piece: Node3D
	if not Engine.is_editor_hint():piece=prepare_piece()
	elif not installed_visual_path.is_empty():piece=get_node_or_null(installed_visual_path) as Node3D
	if not Engine.is_editor_hint() and not piece:return "Piece installee introuvable."
	if not installed_visual_path.is_empty() and not piece:return "Installed Visual Path doit viser la racine de la piece dans cette scene."
	if piece:
		var meshes: Array[Node]=piece.find_children("*","MeshInstance3D",true,false)
		if piece is MeshInstance3D:meshes.append(piece)
		if not meshes.any(func(mesh: Node):return (mesh as MeshInstance3D).mesh!=null):return "Deposer le modele 3D de la piece sous PieceInstallee."
		for mesh in meshes:
			var skeleton=mesh.get_node_or_null(mesh.skeleton) if mesh.skin else null
			if skeleton and skeleton!=piece and not piece.is_ancestor_of(skeleton):return "La piece mobile doit etre independante du skin du socle : utiliser son World Model et un point de fixation sous BoneAttachment3D."
	return ""
func can_interact() -> bool:
	var allowed := enabled and is_visible_in_tree() if inspect_when_complete else super.can_interact()
	return not placement_owner() and not _busy and allowed and (not require_visible_model or has_visible_model()) and (inspect_when_complete or not use_selection_view or Engine.is_editor_hint() or not WorldEvents.interaction_used(_id()))
func accepts_inventory_item(id: StringName) -> bool: return enabled and not required_id().is_empty() and id==required_id()
func interact(player: Node3D=null) -> bool:
	if not use_selection_view:return super.interact(player)
	if Engine.is_editor_hint() or not can_interact() or not WorldCondition.all_match(requirements):return false
	var game := WorldEvents.game_for(self)
	if not game or not is_instance_valid(game.item_placement):return false
	if is_instance_valid(game.inventory_menu) and game.inventory_menu.opened:game.inventory_menu.close()
	return game.item_placement.begin(self,player)
func commit_piece(uid: String) -> bool:
	var inventory := get_node_or_null("/root/InventoryState")
	if not enabled or WorldEvents.interaction_used(_id()) or not WorldCondition.all_match(requirements):return false
	if not configuration_error().is_empty() or not inventory:return false
	var location: Dictionary=inventory.model.locate(uid)
	if location.is_empty() or location.entry.item.id!=required_id() or inventory.count(required_id())<required_quantity:return false
	if consume_item and not inventory.remove_item(required_id(),required_quantity):return false
	WorldEvents.mark_interaction(_id());return true
func publish_installation(player: Node3D) -> void:
	if not interaction_event.is_empty():WorldEvents.raise_event(interaction_event)
	WorldEvents.execute(actions,self);interacted.emit(player)
func _perform() -> bool:
	var inventory := get_node_or_null("/root/InventoryState")
	if not inventory or not inventory.has_item(required_id(),required_quantity):
		var game := WorldEvents.game_for(self)
		if game: game.hud.toast("Il manque l'objet necessaire.")
		return false
	var item: Resource=inventory.resolve_item(required_id())
	if consume_item and (not item or item.consumed_on_use) and not inventory.remove_item(required_id(),required_quantity): return false
	_show_installed(true); return true

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if required_id().is_empty(): warnings.append("Choisir l'identifiant de l'objet a installer.")
	if is_inside_tree() and use_selection_view:
		var error := configuration_error()
		if not error.is_empty():warnings.append(error)
		if interaction_id.is_empty() and not placement_owner():warnings.append("Donner un Interaction Id unique et stable pour conserver l'installation entre visites.")
	if is_inside_tree() and require_visible_model and not has_visible_model(): warnings.append("Ajouter un modele visible ou renseigner Visual Path. Sans modele, aucune interaction n'est proposee.")
	return warnings
func _validate_property(property: Dictionary) -> void:
	if is_inside_tree() and placement_owner() and property.name in ["use_selection_view","inspect_when_complete","hide_player_in_view","select_part_first","camera_path","access_settings","once","interaction_label"]:property.usage&=~PROPERTY_USAGE_EDITOR
