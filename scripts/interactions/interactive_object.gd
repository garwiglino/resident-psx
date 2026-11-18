@tool
class_name InteractiveObject3D
extends "res://scripts/inventory/placement_scene.gd"
## One close-up scene for any model: action buttons, switches and item sockets.
func _init() -> void:
	once=false;close_when_complete=false
func _validate_property(property: Dictionary) -> void:
	if is_inside_tree() and not placement_targets().any(func(part: Node3D):return part.is_item_socket()):
		if property.name in ["close_when_complete","inspect_when_complete","actions","interaction_event","once"]:property.usage&=~PROPERTY_USAGE_EDITOR
