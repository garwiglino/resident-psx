@tool
class_name WorldResponse
extends Node
signal triggered
@export var enabled := true
## Vide = identifiant stable derive de cette scene et du chemin du noeud.
@export var response_id: StringName
## Vide : reagit lorsque les conditions deviennent vraies. Sinon attend cet evenement.
@export var listen_event: StringName
@export var conditions: Array[WorldCondition]=[]
@export var require_all := true
@export var actions: Array[WorldAction]=[]
@export var once := true
@export var check_on_ready := true
var _matched := false

func _ready() -> void:
	if Engine.is_editor_hint():return
	WorldEvents.state_changed.connect(_state_changed);WorldEvents.event_raised.connect(_event);WorldEvents.run_reset.connect(_reset)
	if check_on_ready:call_deferred("_evaluate")
	else:_matched=WorldCondition.all_match(conditions,require_all)
func _id() -> StringName:return response_id if not response_id.is_empty() else WorldEvents.stable_id(self)
func _state_changed(_key: StringName,_value: Variant) -> void:
	if listen_event.is_empty():_evaluate()
func _reset() -> void:
	_matched=false
	if check_on_ready:call_deferred("_evaluate")
func _event(id: StringName,_payload: Dictionary) -> void:
	if not listen_event.is_empty() and id==listen_event:trigger()
func _evaluate() -> void:
	if not enabled or not listen_event.is_empty() or conditions.is_empty():return
	var matched := WorldCondition.all_match(conditions,require_all)
	var rising := matched and not _matched;_matched=matched
	if rising:trigger()
func trigger() -> bool:
	if Engine.is_editor_hint() or not enabled or not is_inside_tree():return false
	if once and WorldEvents.was_used(_id()):return false
	if not WorldCondition.all_match(conditions,require_all):return false
	if not WorldEvents.execute(actions,self):return false
	if once:WorldEvents.claim_once(_id())
	triggered.emit();return true
func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray(["Ajouter des conditions ou Listen Event pour une reaction automatique. Sinon connecter un signal a trigger()."]) if conditions.is_empty() and listen_event.is_empty() else PackedStringArray()
