@tool
class_name WorldDoor3D
extends WorldInteraction3D
const LockedReplies=preload("res://scripts/dialogue/locked_door_replies.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const RequiredItem=preload("res://scripts/inventory/item_definition.gd")
signal opened
signal closed
@export_group("Porte")
@export var door_id: StringName
@export var initially_open := false
@export var initially_locked := false
@export var permanently_locked := false
## Exact inventory definition ID: distinct keys/badges never stack together.
@export var required_item_id: StringName
@export var consume_key_on_unlock := false
@export var open_away_from_player := true
@export_node_path("Node3D") var pivot_path: NodePath=^"Pivot"
@export var open_rotation_degrees := Vector3(0,-95,0)
@export_range(0,4,.05,"suffix:s") var duration := .5
@export var opened_event: StringName
@export var closed_event: StringName
@export_group("Porte verrouillee - repliques")
@export var locked_dialogue_enabled := true
## One authored DialogueSequence: only one random line plays per failed attempt.
@export var locked_dialogue_pool: Sequence=preload("res://assets/audio/dialogs/locked_doors_key/locked_doors_key.tres")
@export var permanent_dialogue_pool: Sequence=preload("res://assets/audio/dialogs/locked_doors/locked_doors.tres")
@export_range(0,30,.5,"suffix:s") var locked_dialogue_cooldown := 4.0
## Le son de serrure commence d'abord, la replique peut suivre sans attendre sa fin.
@export_range(0,.5,.01,"suffix:s") var locked_dialogue_delay := .03
@export var locked_sounds: Array[AudioStream]=[preload("res://assets/audio/interactables/locked_door_1.wav"),preload("res://assets/audio/interactables/locked_door_2.wav")]
@export_range(-40,0,.5,"suffix:dB") var locked_sound_volume_db := -6.0
var is_open := false
var locked := false
var _pivot: Node3D
var _closed := Transform3D.IDENTITY
var _weight := 0.0
var _tween: Tween
var _interactor: Node3D
var _swing_sign := 1.0
var _locked_feedback: Node3D
func _enter_tree() -> void:
	super._enter_tree();add_to_group("psx_dynamic_geometry")
func _id() -> StringName:return door_id if not door_id.is_empty() else super._id()
func _ready() -> void:
	if Engine.is_editor_hint():return
	_pivot=get_node_or_null(pivot_path) if not pivot_path.is_empty() else null
	if _pivot:_closed=_pivot.transform
	var key := StringName("door.%s.open" % _id());var lock_key := StringName("door.%s.locked" % _id())
	if WorldEvents.fact(key,null)==null or permanently_locked:WorldEvents.set_fact(key,initially_open and not permanently_locked)
	if WorldEvents.fact(lock_key,null)==null or permanently_locked:WorldEvents.set_fact(lock_key,permanently_locked or initially_locked or not required_item_id.is_empty())
	WorldEvents.state_changed.connect(_changed);WorldEvents.run_reset.connect(_reset);_sync(false)
func _changed(key: StringName,_value: Variant) -> void:
	if key in [StringName("door.%s.open" % _id()),StringName("door.%s.locked" % _id()),StringName("door.%s.swing" % _id()),&"world.restored"]:_sync(true)
func _reset() -> void:call_deferred("_sync",false)
func _sync(animate: bool) -> void:
	is_open=bool(WorldEvents.fact(StringName("door.%s.open" % _id()),initially_open))
	locked=bool(WorldEvents.fact(StringName("door.%s.locked" % _id()),initially_locked or not required_item_id.is_empty()))
	if permanently_locked:
		is_open=false;locked=true
		WorldEvents.set_fact(StringName("door.%s.open" % _id()),false);WorldEvents.set_fact(StringName("door.%s.locked" % _id()),true)
	_swing_sign=float(WorldEvents.fact(StringName("door.%s.swing" % _id()),1.0))
	if _tween:_tween.kill()
	if animate and duration>0 and _pivot:
		_tween=create_tween();_tween.tween_method(_apply_weight,_weight,1.0 if is_open else 0.0,duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:_apply_weight(1.0 if is_open else 0.0)
func _apply_weight(value: float) -> void:
	_weight=value
	if _pivot:
		var target := Basis.from_euler(open_rotation_degrees*_swing_sign*PI/180)
		_pivot.transform=Transform3D(_closed.basis*Basis.IDENTITY.slerp(target,value),_closed.origin)
func get_interaction_label() -> String:
	if permanently_locked:return "VERROUILLE"
	if is_open: return "FERMER"
	if not locked: return "OUVRIR"
	var inventory := get_node_or_null("/root/InventoryState")
	return "DEVERROUILLER" if inventory and not required_item_id.is_empty() and inventory.has_item(required_item_id) else "VERROUILLE"
func accepts_inventory_item(id: StringName) -> bool: return not permanently_locked and locked and not required_item_id.is_empty() and id==required_item_id
func _locked_response(source: Sequence) -> void:
	if not is_instance_valid(_locked_feedback):
		_locked_feedback=LockedReplies.new();_locked_feedback.name="RetourPorteVerrouillee";add_child(_locked_feedback)
	_locked_feedback.play_for(source if locked_dialogue_enabled else null,locked_dialogue_cooldown,locked_sounds,locked_sound_volume_db,locked_dialogue_delay)
func _perform() -> bool:
	if permanently_locked:_locked_response(permanent_dialogue_pool);return false
	if locked:
		var inventory := get_node_or_null("/root/InventoryState")
		if required_item_id.is_empty() or not inventory or not inventory.has_item(required_item_id):
			var required: Resource=inventory.resolve_item(required_item_id) if inventory and not required_item_id.is_empty() else null
			if required_item_id.is_empty():_locked_response(permanent_dialogue_pool)
			elif required and required.kind==RequiredItem.Kind.KEY:_locked_response(locked_dialogue_pool)
			return false
		if consume_key_on_unlock and not inventory.remove_item(required_item_id): return false
		set_locked(false)
	if not is_open and open_away_from_player and is_instance_valid(_interactor) and _pivot:
		# Test the actual leaf direction, including authored hinge rotations.
		var leaf_axis := _closed.basis*Vector3.RIGHT
		var opened_axis := _closed.basis*Basis.from_euler(open_rotation_degrees*PI/180)*Vector3.RIGHT
		var movement := global_basis*(opened_axis-leaf_axis)
		var side := _interactor.global_position-get_interaction_position()
		WorldEvents.set_fact(StringName("door.%s.swing" % _id()),-1.0 if movement.dot(side)>0 else 1.0)
	return set_open(not is_open)
func interact(player: Node3D=null) -> bool:
	_interactor=player
	var result := super.interact(player)
	_interactor=null
	return result
func set_open(value: bool) -> bool:
	if permanently_locked and value:return false
	if Engine.is_editor_hint() or not WorldEvents.set_door_open(_id(),value):return false
	_sync(true)
	if value:
		opened.emit()
		if not opened_event.is_empty():WorldEvents.raise_event(opened_event)
	else:
		closed.emit()
		if not closed_event.is_empty():WorldEvents.raise_event(closed_event)
	return true
func open() -> bool:return set_open(true)
func close() -> bool:return set_open(false)
func set_locked(value: bool) -> void:
	if permanently_locked and not value:return
	if not Engine.is_editor_hint():WorldEvents.set_fact(StringName("door.%s.locked" % _id()),value);locked=value
