extends CanvasLayer
const Style=preload("res://scripts/ui/cursor_style.gd")
var game: Node
var canvas: Control
var kind := Style.Kind.POINTER
var at := Vector2(160,120)
var _native_hidden := false
var _inside := true
func _ready() -> void:
	layer=100;process_mode=Node.PROCESS_MODE_ALWAYS;process_priority=120
	canvas=Control.new();canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;add_child(canvas)
	canvas.draw.connect(_draw_cursor)
	get_window().mouse_entered.connect(_mouse_entered)
	get_window().mouse_exited.connect(_mouse_exited)
	# Keep existing mouse modes and GUI hit testing; draw one cursor in the 320x240 canvas.
	if DisplayServer.get_name()!="headless":
		var empty := Image.create(1,1,false,Image.FORMAT_RGBA8);empty.fill(Color.TRANSPARENT)
		for shape in range(Input.CURSOR_ARROW,Input.CURSOR_HELP+1):Input.set_custom_mouse_cursor(empty,shape)
		_native_hidden=true
	canvas.hide()
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:at=event.position;_inside=true
func _mouse_entered() -> void:_inside=true
func _mouse_exited() -> void:_inside=false;canvas.hide()
func _exit_tree() -> void:
	if _native_hidden:
		for shape in range(Input.CURSOR_ARROW,Input.CURSOR_HELP+1):Input.set_custom_mouse_cursor(null,shape)
func _process(_delta: float) -> void:
	canvas.visible=_inside and Input.mouse_mode in [Input.MOUSE_MODE_VISIBLE,Input.MOUSE_MODE_CONFINED] and get_viewport().get_visible_rect().has_point(at)
	if not canvas.visible:return
	kind=cursor_kind();canvas.queue_redraw()
func cursor_kind() -> int:
	if get_viewport().gui_is_dragging():return Style.Kind.BLOCKED if Input.get_current_cursor_shape()==Input.CURSOR_FORBIDDEN else Style.Kind.GRAB
	var control := get_viewport().gui_get_hovered_control()
	var shape: int=Input.get_current_cursor_shape()
	while control:
		if control.has_method("game_cursor_shape"):shape=control.game_cursor_shape();break
		if control is BaseButton:
			shape=Input.CURSOR_ARROW if control.disabled else Input.CURSOR_POINTING_HAND;break
		control=control.get_parent() as Control
	match shape:
		Input.CURSOR_POINTING_HAND:return Style.Kind.POINT
		Input.CURSOR_DRAG,Input.CURSOR_HSIZE,Input.CURSOR_VSIZE:return Style.Kind.OPEN_HAND
		Input.CURSOR_CAN_DROP:return Style.Kind.GRAB
		Input.CURSOR_FORBIDDEN:return Style.Kind.BLOCKED
	return Style.Kind.POINTER
func _draw_cursor() -> void:
	if game and game.cursor_style:game.cursor_style.draw(canvas,kind,at)
