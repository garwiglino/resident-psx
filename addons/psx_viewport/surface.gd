@tool
extends Control
var texture: Texture2D

func frame_rect() -> Rect2:
	var factor := minf(size.x/320.0,size.y/240.0)
	var extent := Vector2(320,240)*factor
	return Rect2((size-extent)*.5,extent)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color.BLACK)
	if texture:draw_texture_rect(texture,frame_rect(),false)
