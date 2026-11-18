@tool
extends Button
## Explicit drag targets on the visible buttons, not only on their container.
func _can_drop_data(position: Vector2,data: Variant) -> bool:
	return get_parent()._can_drop_data(position,data)

func _drop_data(position: Vector2,data: Variant) -> void:
	get_parent()._drop_data(position,data)
