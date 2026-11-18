@tool
extends Control
signal seek_requested(time: float)
signal delete_requested
signal play_requested
signal actor_selected(index: int)
signal actor_delete_requested(index: int)
var duration := 2.0
var camera_duration := 2.0
var cursor := 0.0
var dialogue_delay := 0.0
var has_dialogue := false
var automatic_dialogue := false
var condition := ""
var keys := PackedFloat32Array()
var actor_rows: Array=[]
var selected_actor := -1
var audio_duration := 0.0
var is_intercom := false
var _dragging := false
var _actor_focus := -1

func resize_rows() -> void:
	custom_minimum_size.y=139+actor_rows.size()*30;queue_redraw()

func _init() -> void:
	custom_minimum_size=Vector2(320,110);focus_mode=Control.FOCUS_ALL;mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND

func _x(time: float) -> float:return 84+(size.x-104)*clampf(time/maxf(duration,.001),0,1)

func _draw() -> void:
	var font := get_theme_default_font();var fs := get_theme_default_font_size()
	draw_style_box(get_theme_stylebox("panel","Tree"),Rect2(Vector2.ZERO,size))
	draw_string(font,Vector2(8,30),"Camera",HORIZONTAL_ALIGNMENT_LEFT,-1,fs)
	draw_string(font,Vector2(8,65),"Dialogue",HORIZONTAL_ALIGNMENT_LEFT,-1,fs)
	draw_rect(Rect2(84,12,maxf(_x(camera_duration)-84,1),25),Color(.22,.42,.65))
	for i in 5:
		var time := duration*i/4.0;var x := _x(time)
		draw_line(Vector2(x,10),Vector2(x,size.y-22),Color(1,1,1,.12))
		draw_string(font,Vector2(x,size.y-5),"%.2fs" % time,HORIZONTAL_ALIGNMENT_LEFT,-1,fs-2)
	if has_dialogue:
		var x := _x(dialogue_delay)
		draw_rect(Rect2(x,48,maxf(_x(duration)-x,3),24),Color(.61,.45,.19))
		draw_string(font,Vector2(x+5,65),"Lecture automatique" if automatic_dialogue else "Lecture / validation",HORIZONTAL_ALIGNMENT_LEFT,maxf(size.x-x-28,1),fs-2)
	else:draw_string(font,Vector2(90,65),"Sans dialogue",HORIZONTAL_ALIGNMENT_LEFT,-1,fs-2,Color(.65,.65,.65))
	draw_string(font,Vector2(8,96),"Audio",HORIZONTAL_ALIGNMENT_LEFT,-1,fs)
	if audio_duration>0:
		var x := _x(dialogue_delay)
		draw_rect(Rect2(x,79,maxf(_x(dialogue_delay+audio_duration)-x,3),24),Color(.40,.32,.55))
		draw_string(font,Vector2(x+5,96),"Intercom / voix" if is_intercom else "Voix de la replique",HORIZONTAL_ALIGNMENT_LEFT,maxf(size.x-x-28,1),fs-2)
	for index in actor_rows.size():
		var item: Dictionary=actor_rows[index];var y := 111+index*30
		draw_string(font,Vector2(8,y+17),String(item.label).left(10),HORIZONTAL_ALIGNMENT_LEFT,73,fs-2)
		var x := _x(item.start);var width := maxf(_x(item.start+item.duration)-x,3)
		draw_rect(Rect2(x,y,width,24),Color(.24,.52,.38) if selected_actor!=index else Color(.35,.66,.47))
		draw_string(font,Vector2(x+5,y+17),item.animation,HORIZONTAL_ALIGNMENT_LEFT,maxf(width-10,1),fs-2)
	for time in keys:
		var x := _x(time);draw_colored_polygon(PackedVector2Array([Vector2(x,13),Vector2(x+5,23),Vector2(x,33),Vector2(x-5,23)]),Color(.93,.85,.46))
	draw_line(Vector2(_x(cursor),6),Vector2(_x(cursor),size.y-23),Color(.95,.5,.35),2)

func _seek(position: Vector2) -> void:
	var time := clampf((position.x-84)/maxf(size.x-104,1),0,1)*duration
	var closest := 7.0
	for key in keys:
		var distance := absf(_x(key)-position.x)
		if distance<closest:time=key;closest=distance
	seek_requested.emit(time)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_dragging=event.pressed
		if _dragging:
			grab_focus();_actor_focus=floori((event.position.y-111)/30) if event.position.y>=111 else -1
			if _actor_focus>=0 and _actor_focus<actor_rows.size():actor_selected.emit(_actor_focus)
			_seek(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:_seek(event.position);accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_DELETE,KEY_BACKSPACE]:
			if _actor_focus>=0 and _actor_focus<actor_rows.size():actor_delete_requested.emit(_actor_focus)
			else:delete_requested.emit()
			accept_event()
		elif event.keycode==KEY_SPACE:play_requested.emit();accept_event()
		elif event.keycode in [KEY_LEFT,KEY_RIGHT]:seek_requested.emit(clampf(cursor+(-1.0 if event.keycode==KEY_LEFT else 1.0)/30.0,0,duration));accept_event()
