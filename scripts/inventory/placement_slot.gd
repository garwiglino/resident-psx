extends "res://scripts/inventory/inventory_slot.gd"
func game_cursor_shape() -> int:return Input.CURSOR_POINTING_HAND if not entry().is_empty() else Input.CURSOR_ARROW
func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
		grab_focus();_entered();menu.choose(String(entry().get("uid","")));accept_event()
func _get_drag_data(_at: Vector2) -> Variant:return null
func _can_drop_data(_at: Vector2,_data: Variant) -> bool:return false
