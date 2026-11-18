extends Control
const Style=preload("res://scripts/ui/cursor_style.gd")
var at := Vector2(160,120)
var style: Resource
var hovering := false
func _draw() -> void:
	if style:style.draw(self,Style.Kind.POINT if hovering else Style.Kind.POINTER,at)
