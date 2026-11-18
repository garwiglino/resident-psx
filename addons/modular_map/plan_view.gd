@tool
extends Control
var controller
var zoom := 32.0
var pan := Vector2.ZERO
var panning := false

func _ready() -> void:
	custom_minimum_size=Vector2(270,250)
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	focus_mode=Control.FOCUS_ALL
	mouse_default_cursor_shape=Control.CURSOR_CROSS
	tooltip_text="Glisser : peindre. Maj ou clic droit : effacer. Molette : zoom. Milieu : deplacer le plan."

func to_plan(point: Vector2) -> Vector3:
	var grid := (point-size*.5-pan)/zoom
	return Vector3(grid.x*2,controller.current_level()*3,grid.y*2)

func to_screen(point: Vector2) -> Vector2: return point*zoom+size*.5+pan

func fit() -> void:
	if not controller.map: pan=Vector2.ZERO; queue_redraw(); return
	var bounds: Rect2=controller.map.layout.plan_bounds(controller.current_level())
	if not bounds.has_area():pan=Vector2.ZERO;queue_redraw();return
	var low := bounds.position;var high := bounds.end
	var extent := high-low+Vector2(2,2)
	zoom=clampf(minf(size.x/extent.x,size.y/extent.y),8,90)
	pan=-(low+high)*.5*zoom; queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var anchor: Vector2 = (event.position-size*.5-pan)/zoom
			zoom=clampf(zoom*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.15),8,100)
			pan=event.position-size*.5-anchor*zoom; queue_redraw(); accept_event()
		elif event.button_index==MOUSE_BUTTON_MIDDLE:
			panning=event.pressed; accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			grab_focus()
			if event.pressed: controller.begin_stroke(to_plan(event.position),event.shift_pressed or event.button_index==MOUSE_BUTTON_RIGHT)
			else: controller.end_stroke()
			accept_event()
	elif event is InputEventMouseMotion:
		if panning: pan+=event.relative; queue_redraw()
		else: controller.move_stroke(to_plan(event.position))
	elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		controller.cancel_stroke(); accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.09,.105,.12))
	var start := Vector2i(floori(to_plan(Vector2.ZERO).x/2),floori(to_plan(Vector2.ZERO).z/2))
	var finish := Vector2i(ceili(to_plan(size).x/2),ceili(to_plan(size).z/2))
	for x in range(start.x,finish.x+1):
		draw_line(to_screen(Vector2(x,start.y)),to_screen(Vector2(x,finish.y)),Color(.17,.19,.21))
	for z in range(start.y,finish.y+1):
		draw_line(to_screen(Vector2(start.x,z)),to_screen(Vector2(finish.x,z)),Color(.17,.19,.21))
	if not controller or not is_instance_valid(controller.map) or not controller.map.layout: return
	var layout: Resource = controller.map.layout
	var level: int=controller.current_level();var data: Dictionary=layout.layer(level)
	for cell: Vector2i in layout.cells_at(level-1):draw_rect(Rect2(to_screen(Vector2(cell))+Vector2.ONE,Vector2.ONE*(zoom-2)),Color(.18,.21,.23),false,1)
	for cell: Vector2i in data.cells:
		var color := Color(.3,.33,.36) if data.floor_only.has(cell) else Color.from_hsv(fmod(float(data.cells[cell])*.213,1),.22,.48)
		if data.floor_holes.has(cell):color=Color(.15,.16,.18)
		draw_rect(Rect2(to_screen(Vector2(cell))+Vector2.ONE,Vector2.ONE*(zoom-2)),color)
		if zoom>=26 and int(data.cells[cell])>0 and not data.floor_holes.has(cell):
			draw_string(get_theme_default_font(),to_screen(Vector2(cell)+Vector2(.12,.68)),str(data.cells[cell]),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(.85,.85,.78))
	for cell: Vector2i in data.ceiling_tiles:
		draw_rect(Rect2(to_screen(Vector2(cell))+Vector2.ONE*4,Vector2.ONE*(zoom-8)),Color(.45,.7,.9),false,1)
	for cell: Vector2i in data.floor_holes:
		var a := to_screen(Vector2(cell))+Vector2.ONE*3;var b := to_screen(Vector2(cell)+Vector2.ONE)-Vector2.ONE*3
		draw_line(a,b,Color(.9,.47,.2),2);draw_line(Vector2(a.x,b.y),Vector2(b.x,a.y),Color(.9,.47,.2),2)
	for key: String in data.edges:
		if int(data.edges[key].kind)==layout.Kind.PASSAGE:
			var info: Dictionary=layout.edge_info(key);draw_line(to_screen(Vector2(info.a)),to_screen(Vector2(info.b)),Color(.2,.6,.45),1)
	var edges: Dictionary = layout.effective_edges(level)
	for key: String in edges:
		var config: Dictionary = edges[key]
		var slots: Array = layout.footprint(key,config)
		var a: Vector2i = layout.edge_info(key).a
		var b: Vector2i = layout.edge_info(slots[-1]).b
		var color := Color(.83,.83,.74)
		if config.kind==layout.Kind.DOOR: color=Color(.95,.62,.22)
		elif config.kind==layout.Kind.WINDOW: color=Color(.27,.7,.85)
		draw_line(to_screen(Vector2(a)),to_screen(Vector2(b)),color,3)
		if config.kind in [layout.Kind.DOOR,layout.Kind.WINDOW]:
			var midpoint := (Vector2(a)+Vector2(b))*.5
			draw_circle(to_screen(midpoint),4,Color(.08,.1,.12))
	if not controller.selected_edge.is_empty():
		var info: Dictionary = layout.edge_info(controller.selected_edge)
		draw_line(to_screen(Vector2(info.a)),to_screen(Vector2(info.b)),Color.WHITE,5)
	if controller.painting and controller.mode==0:
		var low: Vector2i = controller.first.min(controller.last)
		var extent: Vector2i = controller.first.max(controller.last)-low+Vector2i.ONE
		draw_rect(Rect2(to_screen(Vector2(low)),Vector2(extent)*zoom),Color(.4,.8,.7,.25))
		draw_rect(Rect2(to_screen(Vector2(low)),Vector2(extent)*zoom),Color(.5,.9,.8),false,2)
