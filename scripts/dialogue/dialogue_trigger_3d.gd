@tool
class_name DialogueTrigger3D
extends Area3D
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Controller=preload("res://scripts/dialogue/dialogue_controller.gd")
const Volume=preload("res://scripts/trigger_volume.gd")
@export var sequence: Sequence
@export var enabled := true:
	set(value):
		enabled=value
		if Engine.is_editor_hint() and is_inside_tree():Volume.ensure_box(self)
@export var automatic_on_enter := true
@export var once := true
@export var enqueue_when_busy := false
@export var player_group: StringName=&"player"
var used := false

func _init() -> void:collision_layer=0;collision_mask=2
func _ready() -> void:
	Volume.ensure_box(self)
	set_process(Engine.is_editor_hint())
	if not Engine.is_editor_hint():body_entered.connect(_entered)
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():Volume.ensure_box(self)
	set_process(false)
func _entered(body: Node3D) -> void:
	if automatic_on_enter and body.is_in_group(player_group):trigger()
func trigger() -> bool:
	if Engine.is_editor_hint() or not enabled or (once and used):return false
	var controller := Controller.find_for(self,sequence)
	if not controller or not controller.play(sequence,enqueue_when_busy):return false
	used=true;return true
func reset() -> void:used=false
