@tool
class_name WorldEventZone3D
extends Area3D
const Volume=preload("res://scripts/trigger_volume.gd")
signal entered
@export var zone_id: StringName
@export var enter_event: StringName
@export var enabled := true
@export var once := true
@export var conditions: Array[WorldCondition]=[]
@export var actions: Array[WorldAction]=[]
@export var player_group: StringName=&"player"
func _init() -> void:collision_layer=0;collision_mask=2
func _ready() -> void:
	Volume.ensure_box(self)
	if not Engine.is_editor_hint():body_entered.connect(_entered)
func _entered(body: Node3D) -> void:
	if body.is_in_group(player_group):trigger()
func trigger() -> bool:
	if Engine.is_editor_hint() or not enabled:return false
	var id := zone_id if not zone_id.is_empty() else WorldEvents.stable_id(self)
	if once and WorldEvents.zone_visited(id):return false
	if not WorldCondition.all_match(conditions):return false
	WorldEvents.mark_zone(id)
	if not enter_event.is_empty():WorldEvents.raise_event(enter_event)
	WorldEvents.execute(actions,self);entered.emit();return true
func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray(["Renseigner Zone Id pour pouvoir utiliser cette visite dans une condition d'objectif."]) if zone_id.is_empty() else PackedStringArray()
