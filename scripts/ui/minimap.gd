extends Control

const Layout = preload("res://scripts/modular_map/layout.gd")
const MenuTheme = preload("res://scripts/ui/menu_theme.gd")
const WALL := Color(0xf2f0e7ff)
const WINDOW := Color(0xa4aabbff)
const FLOOR := Color(0x242c3adc)
const PLAYER := Color(0xb4d7e6ff)
const LOCKED := Color(0xe0b86dff)
const SEALED := Color(0xcd615bff)
const DISC_COLOR := Color(0x121822eb)
const RIM_PADDING := 5.0
const HEADER_BOTTOM := 19.0
const PLAN_OFFSET := Vector2(0, 4)
const LANDING_TOLERANCE := 0.25

var _map: ModularMap3D
var _levels: Array[int] = []
var _plans: Dictionary = {}
var _level := 0
var _origin := Vector2.ZERO
var _pixels_per_cell := 1.0
var _marker: Control
var _marker_position := Vector2.INF
var _marker_angle := 0.0

func bind(map: ModularMap3D) -> void:
	_map = map
	_map.construction_rebuilt.connect(_rebuild_plans)
	_rebuild_plans()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.draw.connect(_draw_marker)
	resized.connect(_fit_plan)
	WorldEvents.state_changed.connect(_door_changed)
	WorldEvents.run_reset.connect(queue_redraw)
	_fit_plan()

func _rebuild_plans() -> void:
	_levels.clear()
	_plans.clear()
	if _map.layout:
		var layout: Resource = _map.layout
		for level: int in layout.level_ids():
			var floors: Array[Vector2i] = []
			var bounds := Rect2()
			for cell: Vector2i in layout.cells_at(level):
				if layout.has_floor(cell, level):
					var tile := Rect2(Vector2(cell), Vector2.ONE)
					bounds = tile if floors.is_empty() else bounds.merge(tile)
					floors.append(cell)
			var edges: Array[Dictionary] = []
			var effective: Dictionary = layout.effective_edges(level)
			for key: String in effective:
				var config: Dictionary = effective[key]
				var end: String = Layout.footprint(key, config)[-1]
				var a := Vector2(Layout.edge_info(key).a)
				var b := Vector2(Layout.edge_info(end).b)
				if floors.is_empty() and edges.is_empty():
					bounds = Rect2(a, Vector2.ZERO)
				bounds = bounds.expand(a).expand(b)
				edges.append({
					"a": a,
					"b": b,
					"kind": int(config.kind),
					"door": _map.door_at_edge(level, key) if config.kind == Layout.Kind.DOOR else null,
				})
			if floors.is_empty() and edges.is_empty():
				continue
			bounds.size = bounds.size.max(Vector2.ONE)
			_levels.append(level)
			_plans[level] = { "floors": floors, "edges": edges, "bounds": bounds }
	if not _level in _levels and not _levels.is_empty():
		_level = _levels[0]
	_fit_plan()

func _fit_plan() -> void:
	_marker_position = Vector2.INF
	if _plans.has(_level):
		var bounds: Rect2 = _plans[_level].bounds
		var center := size * 0.5 + PLAN_OFFSET
		var half_extent := bounds.size * 0.5
		var fit_radius := minf(size.x, size.y) * 0.5 - RIM_PADDING - PLAN_OFFSET.length()
		_pixels_per_cell = minf(fit_radius / half_extent.length(), (center.y - HEADER_BOTTOM) / half_extent.y)
		_origin = center - bounds.get_center() * _pixels_per_cell
	queue_redraw()
	if _marker:
		_marker.queue_redraw()

func update_marker(player: Node3D) -> bool:
	if _levels.is_empty() or not is_instance_valid(_map):
		return false
	var local := _map.to_local(player.global_position)
	var level := _levels[0]
	for candidate in _levels:
		if candidate * Layout.STOREY_HEIGHT > local.y + LANDING_TOLERANCE:
			break
		level = candidate
	if level != _level:
		_level = level
		_fit_plan()
	var plan_position := Vector2(local.x, local.z) / Layout.CELL
	var bounds: Rect2 = _plans[_level].bounds
	var position_on_map := _pixel(plan_position)
	if not bounds.grow(0.2).has_point(plan_position) or position_on_map.distance_to(size * 0.5) > minf(size.x, size.y) * 0.5 - RIM_PADDING:
		position_on_map = Vector2.INF
	var forward := _map.global_basis.inverse() * -player.global_basis.z
	var angle := snappedf(Vector2(forward.x, forward.z).angle(), TAU / 16.0)
	if position_on_map != _marker_position or not is_equal_approx(angle, _marker_angle):
		_marker_position = position_on_map
		_marker_angle = angle
		_marker.queue_redraw()
	return true

func _door_changed(key: StringName, _value: Variant) -> void:
	if key == &"world.restored" or (key.begins_with("door.") and (key.ends_with(".open") or key.ends_with(".locked"))):
		queue_redraw()

func _pixel(point: Vector2) -> Vector2:
	return (_origin + point * _pixels_per_cell).round()

func _draw() -> void:
	if not _plans.has(_level):
		return
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(size * 0.5, radius, MenuTheme.LINE)
	draw_circle(size * 0.5, radius - 1.0, DISC_COLOR)
	var heading := Layout.level_name(_level).to_upper()
	draw_string(MenuTheme.BODY, Vector2(0, 15), heading, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, WALL)
	var plan: Dictionary = _plans[_level]
	for cell: Vector2i in plan.floors:
		var point := Vector2(cell)
		draw_rect(Rect2(_pixel(point), _pixel(point + Vector2.ONE) - _pixel(point)), FLOOR)
	for edge: Dictionary in plan.edges:
		var a := _pixel(edge.a)
		var b := _pixel(edge.b)
		match int(edge.kind):
			Layout.Kind.DOOR:
				_draw_door(a, b, edge.door)
			Layout.Kind.WINDOW:
				_draw_opening(a, b)
				_line(a.lerp(b, 0.29), a.lerp(b, 0.71), WINDOW)
			Layout.Kind.WALL:
				_line(a, b, WALL)

func _line(a: Vector2, b: Vector2, color: Color) -> void:
	draw_line(a.round() + Vector2(0.5, 0.5), b.round() + Vector2(0.5, 0.5), color, 1.0)

func _draw_opening(a: Vector2, b: Vector2) -> void:
	_line(a, a.lerp(b, 0.25), WALL)
	_line(a.lerp(b, 0.75), b, WALL)

func _draw_door(a: Vector2, b: Vector2, door: WorldDoor3D) -> void:
	_draw_opening(a, b)
	if not is_instance_valid(door):
		return
	var start := a.lerp(b, 0.25)
	var finish := a.lerp(b, 0.75)
	var middle := (a + b) * 0.5
	var axis := (b - a).normalized()
	var normal := axis.orthogonal()
	if door.permanently_locked:
		_line(start, finish, SEALED)
		_line(middle - axis * 2 - normal * 2, middle + axis * 2 + normal * 2, SEALED)
		_line(middle - axis * 2 + normal * 2, middle + axis * 2 - normal * 2, SEALED)
	elif door.is_open:
		_line(start - normal, start + normal, WALL)
		_line(finish - normal, finish + normal, WALL)
	elif door.locked:
		_line(start, finish, LOCKED)
		_line(middle - normal * 2, middle + normal * 2, LOCKED)
	else:
		_line(start + normal, finish + normal, WALL)

func _draw_marker() -> void:
	if not _marker_position.is_finite():
		return
	var forward := Vector2.from_angle(_marker_angle)
	var side := forward.orthogonal()
	var center := _marker_position
	_marker.draw_colored_polygon(PackedVector2Array([
		(center + forward * 4).round(),
		(center - forward * 3 + side * 2.5).round(),
		(center - forward * 3 - side * 2.5).round(),
	]), PLAYER)
