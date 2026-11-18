@tool
class_name CinematicTrigger3D
extends Area3D
const Volume=preload("res://scripts/trigger_volume.gd")
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
@export_node_path("CinematicSequence3D") var sequence_path: NodePath
@export var enabled := true
@export var automatic_on_enter := true
@export var once := true
@export var player_group: StringName=&"player"
var used := false
func _init() -> void:collision_layer=0;collision_mask=2
func _ready() -> void:
	Volume.ensure_box(self)
	if not Engine.is_editor_hint():body_entered.connect(_entered)
func _entered(body: Node3D) -> void:
	if automatic_on_enter and body.is_in_group(player_group):trigger()
func trigger() -> bool:
	if Engine.is_editor_hint() or not enabled or (once and used):return false
	var sequence := get_node_or_null(sequence_path) as Sequence
	if not sequence:return false
	for manager in get_tree().get_nodes_in_group("cinematic_managers"):
		if manager.get_parent().is_ancestor_of(self) and manager.play(sequence):used=true;return true
	return false
func reset() -> void:used=false
