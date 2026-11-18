extends Control
var style: Resource
var corner := 4.0
func _ready() -> void: mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	if not style: return
	var w := size.x-1; var h := size.y-1; var cut := minf(corner,minf(w,h)*.25)
	for y in int(h)+1:
		var inset := maxf(cut-y,cut-(h-y)) if y<cut or y>h-cut else 0.0
		draw_line(Vector2(inset,y),Vector2(w-inset,y),style.top_color.lerp(style.bottom_color,float(y)/maxf(h,1)),1)
	var points := PackedVector2Array([Vector2(cut,0),Vector2(w-cut,0),Vector2(w,cut),Vector2(w,h-cut),Vector2(w-cut,h),Vector2(cut,h),Vector2(0,h-cut),Vector2(0,cut),Vector2(cut,0)])
	draw_polyline(points,style.border_color,1)
	if style.inner_border_color.a>0: draw_rect(Rect2(Vector2(2,2),size-Vector2(4,4)),style.inner_border_color,false,1)
