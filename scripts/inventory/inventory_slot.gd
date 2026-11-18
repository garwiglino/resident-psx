extends Control
const Icons=preload("res://scripts/inventory/icon_painter.gd")
var menu: CanvasLayer
var section: StringName=&"items"
var index := 0
var card: Resource
var slot_size := Vector2.ZERO
var preview_entry: Dictionary={}
var _hover := false
func _ready() -> void:
	custom_minimum_size=slot_size if slot_size!=Vector2.ZERO else (Vector2(32,32) if not card else Vector2(28,40))
	focus_mode=Control.FOCUS_ALL
	mouse_entered.connect(_entered); mouse_exited.connect(func(): _hover=false; queue_redraw())
	focus_entered.connect(_entered); focus_exited.connect(queue_redraw)
func entry() -> Dictionary: return preview_entry if not preview_entry.is_empty() else menu.manager.model.slot(section,index)
func game_cursor_shape() -> int:
	if card:return Input.CURSOR_POINTING_HAND
	return Input.CURSOR_DRAG if not entry().is_empty() else Input.CURSOR_ARROW
func _entered() -> void:
	_hover=true
	if card: menu.select_card(card)
	else: menu.select_slot(section,index)
	queue_redraw()
func _draw() -> void:
	if not menu or not menu.slot_font: return
	var active := _hover or has_focus()
	var rim: Color=menu.slot_highlight if active else menu.slot_rim
	var frame: StyleBox=menu.canvas.theme.get_stylebox("selected" if active else "panel","MenuInset")
	draw_style_box(frame,Rect2(Vector2.ZERO,size))
	if card:
		var found: bool=menu.manager.owns_card(card.id)
		draw_texture_rect(card.image if found else menu.manager.catalogue.card_mystery,Rect2(Vector2(2,2),size-Vector2(4,4)),false,Color.WHITE if found else Color(.5,.5,.5))
		return
	var item := entry()
	if item.is_empty(): return
	Icons.draw_icon(self,item.item,Rect2(Vector2(4,3),size-Vector2(8,8)))
	if item.item.kind==6 and item.uid==menu.manager.active_weapon_uid(): draw_colored_polygon(PackedVector2Array([Vector2(2,2),Vector2(8,2),Vector2(2,8)]),rim)
	if int(item.quantity)>1:
		var font: Font=menu.slot_font; var text := str(item.quantity); var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		var at := Vector2(maxf(3,size.x-width-3),size.y-3)
		var available := size.x-at.x-2
		draw_string(font,at+Vector2.ONE,text,HORIZONTAL_ALIGNMENT_LEFT,available,16,Color.BLACK)
		draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,available,16,menu.text_color)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return
		grab_focus(); _entered()
		if not card and event.button_index==MOUSE_BUTTON_RIGHT and not entry().is_empty(): menu.show_context(entry().uid,get_global_mouse_position())
		accept_event()
	elif event.is_action_pressed("ui_accept") and not card and not entry().is_empty(): menu.show_context(entry().uid,global_position+size*.5); accept_event()
func _get_drag_data(_at: Vector2) -> Variant:
	if card or entry().is_empty() or not preview_entry.is_empty(): return null
	var data := {"inventory":menu.manager.get_instance_id(),"uid":entry().uid}
	var preview: Control=get_script().new(); preview.menu=menu; preview.preview_entry=entry().duplicate(true); preview.size=Vector2(32,32); preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview); return data
func _can_drop_data(_at: Vector2,data: Variant) -> bool:
	if card or not data is Dictionary or data.get("inventory",0)!=menu.manager.get_instance_id(): return false
	var source: Dictionary=menu.manager.model.locate(String(data.get("uid","")))
	return not source.is_empty() and source.entry.item.section()==section
func _drop_data(_at: Vector2,data: Variant) -> void:
	if _can_drop_data(_at,data): menu.move_slot(data.uid,section,index)
