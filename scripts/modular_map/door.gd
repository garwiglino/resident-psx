@tool
extends "res://scripts/world_events/world_door_3d.gd"
## Both leaves share one world-event identity and one interaction.
var right_pivot: Node3D
var right_closed := Transform3D.IDENTITY

func _enter_tree() -> void:
	super._enter_tree()
	add_to_group("psx_door_leaf_lighting")
func _ready() -> void:
	right_pivot = get_node_or_null("RightPivot")
	if right_pivot: right_closed = right_pivot.transform
	super._ready()
func _apply_weight(value: float) -> void:
	super._apply_weight(value)
	if right_pivot:
		var rotation := Basis.from_euler(-open_rotation_degrees*_swing_sign*PI/180)
		right_pivot.transform = Transform3D(right_closed.basis*Basis.IDENTITY.slerp(rotation,value),right_closed.origin)
