@tool
class_name WorldObjective
extends Node
signal completed
@export var objective_id: StringName
@export var enabled := true
@export var conditions: Array[WorldCondition]=[]
@export var require_all := true
@export var completion_event: StringName
@export var actions: Array[WorldAction]=[]

func _ready() -> void:
	if Engine.is_editor_hint():return
	WorldEvents.state_changed.connect(_changed);WorldEvents.run_reset.connect(_reset);call_deferred("_evaluate")
func _changed(_key: StringName,_value: Variant) -> void:_evaluate()
func _reset() -> void:call_deferred("_evaluate")
func _evaluate() -> void:
	if not enabled or objective_id.is_empty() or conditions.is_empty() or WorldEvents.objective_done(objective_id):return
	if WorldCondition.all_match(conditions,require_all):complete()
func complete() -> bool:
	if Engine.is_editor_hint() or not enabled or not WorldEvents.complete_objective(objective_id):return false
	if not completion_event.is_empty():WorldEvents.raise_event(completion_event)
	WorldEvents.execute(actions,self);completed.emit();return true
func is_completed() -> bool:return false if Engine.is_editor_hint() else WorldEvents.objective_done(objective_id)
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if objective_id.is_empty():warnings.append("Renseigner Objective Id, unique et stable dans le jeu.")
	if conditions.is_empty():warnings.append("Ajouter les conditions d'accomplissement, ou appeler complete() par signal.")
	return warnings
