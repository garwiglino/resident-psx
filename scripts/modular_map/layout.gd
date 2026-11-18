@tool
extends Resource
## Sparse plan. Coordinates are grid cells, never rounded world positions.
const CELL := 2.0
const STOREY_HEIGHT := 3.0
const DOUBLE_DOORS := ["double", "double_02", "double_03"]
enum Kind { PASSAGE, WALL, DOOR, WINDOW }
@export_storage var cells: Dictionary = {}
@export_storage var edges: Dictionary = {}
@export_storage var rooms: Dictionary = {}
@export_storage var next_room := 1
## Floor zero keeps its original serialized keys and door identities.
@export_storage var floor_only: Dictionary = {}
@export_storage var floor_holes: Dictionary = {}
@export_storage var ceiling_tiles: Dictionary = {}
@export_storage var ceiling_holes: Dictionary = {}
@export_storage var storeys: Dictionary = {}

func _init() -> void: resource_local_to_scene=true

func _ensure_state() -> void:
	for field in ["cells","edges","rooms","floor_only","floor_holes","ceiling_tiles","ceiling_holes","storeys"]:
		if typeof(get(field))!=TYPE_DICTIONARY:set(field,{})
func level_ids() -> Array[int]:
	_ensure_state();var result: Array[int]=[0]
	for id in storeys:
		if int(id)!=0:result.append(int(id))
	result.sort();return result
static func level_name(level: int) -> String:
	return "RDC" if level==0 else ("Etage %d" % level if level>0 else "Sous-sol %d" % -level)
func add_level(level: int) -> void:
	_ensure_state()
	if level!=0 and not storeys.has(level):storeys[level]={"cells":{},"edges":{},"floor_only":{},"floor_holes":{},"ceiling_tiles":{},"ceiling_holes":{}}
func layer(level := 0,create := false) -> Dictionary:
	_ensure_state()
	if level==0:return {"cells":cells,"edges":edges,"floor_only":floor_only,"floor_holes":floor_holes,"ceiling_tiles":ceiling_tiles,"ceiling_holes":ceiling_holes}
	if create:add_level(level)
	var data: Dictionary=storeys.get(level,{})
	for field in ["cells","edges","floor_only","floor_holes","ceiling_tiles","ceiling_holes"]:
		if typeof(data.get(field))!=TYPE_DICTIONARY:data[field]={}
	return data
func cells_at(level := 0) -> Dictionary:return layer(level).cells
func edges_at(level := 0) -> Dictionary:return layer(level).edges
func has_floor(cell: Vector2i,level := 0) -> bool:
	var data := layer(level);return data.cells.has(cell) and not data.floor_holes.has(cell)
func has_ceiling(cell: Vector2i,level := 0) -> bool:
	var data := layer(level)
	if data.ceiling_holes.has(cell) or layer(level+1).floor_holes.has(cell):return false
	return data.ceiling_tiles.has(cell) or (data.cells.has(cell) and not data.floor_only.has(cell))
func surface_cells(level := 0) -> Array[Vector2i]:
	var data := layer(level);var result: Array[Vector2i]=[]
	for cell: Vector2i in data.cells:result.append(cell)
	for cell: Vector2i in data.ceiling_tiles:
		if not cell in result:result.append(cell)
	return result
func first_floor() -> Dictionary:
	var ids := level_ids();ids.erase(0);ids.push_front(0)
	for level in ids:
		for cell: Vector2i in cells_at(level):
			if has_floor(cell,level):return {"cell":cell,"level":level}
	return {}
func plan_bounds(level := 0) -> Rect2:
	var data := layer(level);var points: Array[Vector2]=[]
	for field in ["cells","floor_holes","ceiling_tiles"]:
		for cell: Vector2i in data[field]:points.append(Vector2(cell));points.append(Vector2(cell)+Vector2.ONE)
	for key: String in data.edges:
		var info := edge_info(key);points.append(Vector2(info.a));points.append(Vector2(info.b))
	if points.is_empty():return Rect2()
	var low := points[0];var high := low
	for point in points:low=low.min(point);high=high.max(point)
	return Rect2(low,(high-low).max(Vector2.ONE))

static func edge_key(axis: String, x: int, z: int) -> String:
	return "%s:%d:%d" % [axis, x, z]

static func edge_info(key: String) -> Dictionary:
	var values := key.split(":")
	var point := Vector2i(int(values[1]), int(values[2]))
	var horizontal := values[0] == "h"
	return {"a":point, "b":point + (Vector2i.RIGHT if horizontal else Vector2i.DOWN),
		"center": Vector3(point.x*CELL + (1.0 if horizontal else 0.0), 0,
		point.y*CELL + (0.0 if horizontal else 1.0)), "yaw":0.0 if horizontal else -PI/2,
		"cells":[point - (Vector2i.DOWN if horizontal else Vector2i.RIGHT), point]}

static func cell_edges(cell: Vector2i) -> Array[String]:
	return [edge_key("h",cell.x,cell.y), edge_key("h",cell.x,cell.y+1),
		edge_key("v",cell.x,cell.y), edge_key("v",cell.x+1,cell.y)]

static func nearest_edge(point: Vector3) -> String:
	var grid := Vector2(point.x,point.z) / CELL
	var cell := Vector2i(floori(grid.x),floori(grid.y))
	var local := grid - Vector2(cell)
	var distances := [local.y, 1-local.y, local.x, 1-local.x]
	return cell_edges(cell)[distances.find(distances.min())]

func snapshot() -> Dictionary:
	_ensure_state()
	return {"cells":cells.duplicate(true), "edges":edges.duplicate(true),
		"rooms":rooms.duplicate(true), "next_room":next_room,"floor_only":floor_only.duplicate(true),"floor_holes":floor_holes.duplicate(true),"ceiling_tiles":ceiling_tiles.duplicate(true),"ceiling_holes":ceiling_holes.duplicate(true),"storeys":storeys.duplicate(true)}

func restore(state: Dictionary) -> void:
	cells=state.cells.duplicate(true); edges=state.edges.duplicate(true)
	rooms=state.rooms.duplicate(true); next_room=state.next_room
	for field in ["floor_only","floor_holes","ceiling_tiles","ceiling_holes","storeys"]:set(field,state.get(field,{}).duplicate(true))
	emit_changed()

func add_room() -> int:
	_ensure_state()
	var id := next_room; next_room += 1
	rooms[id] = "Piece %d" % id
	return id

func paint_cell(cell: Vector2i, room: int,level := 0) -> void:
	var data := layer(level,true)
	if room > 0:data.cells[cell]=room;data.floor_only.erase(cell);data.floor_holes.erase(cell)
	else:
		for field in ["cells","floor_only","floor_holes","ceiling_tiles","ceiling_holes"]:data[field].erase(cell)
func paint_floor(cell: Vector2i,room := 0,level := 0,erase := false) -> void:
	var data := layer(level,true)
	if erase:
		if data.cells.has(cell):data.floor_holes[cell]=true
	else:
		if not data.cells.has(cell):data.cells[cell]=room;data.floor_only[cell]=true
		data.floor_holes.erase(cell)
func paint_ceiling(cell: Vector2i,level := 0,erase := false) -> void:
	var data := layer(level,true)
	if erase:data.ceiling_tiles.erase(cell);data.ceiling_holes[cell]=true
	else:data.ceiling_tiles[cell]=true;data.ceiling_holes.erase(cell)
func paint_opening(cell: Vector2i,level := 0,erase := false) -> void:
	var data := layer(level,true)
	if erase:data.floor_holes.erase(cell)
	else:data.floor_holes[cell]=true
func erase_cell(cell: Vector2i,level := 0) -> void:
	paint_cell(cell,0,level)
	for key in cell_edges(cell):paint_edge(key,Kind.PASSAGE,"",level)
func _enclosure(data: Dictionary,cell: Vector2i) -> int:
	return 0 if data.floor_only.has(cell) else int(data.cells.get(cell,0))

func effective_edges(level := 0) -> Dictionary:
	var data := layer(level);var level_cells: Dictionary=data.cells;var level_edges: Dictionary=data.edges
	var result: Dictionary = {}
	for cell: Vector2i in level_cells:
		for key: String in cell_edges(cell):
			var pair: Array = edge_info(key).cells
			if _enclosure(data,pair[0]) != _enclosure(data,pair[1]):
				result[key] = {"kind":Kind.WALL,"variant":"wall_loop"}
	for key: String in level_edges:
		if level_edges[key].kind == Kind.PASSAGE: result.erase(key)
		else: result[key] = level_edges[key].duplicate(true)
	for key: String in level_edges:
		if not result.has(key): continue
		var slots := footprint(key,level_edges[key])
		if slots.size() == 2:
			# Repainting rooms may invalidate a former 4 m opening. Show complete
			# walls until the plan fits again, rather than intersecting the frame.
			if _double_fits(key,result,level): result.erase(slots[1])
			else:
				result[key]={"kind":Kind.WALL,"variant":"wall_loop"}
				result[slots[1]]={"kind":Kind.WALL,"variant":"wall_loop"}
	return result

func _double_fits(key: String, effective: Dictionary,level := 0) -> bool:
	var data := layer(level)
	var slots := footprint(key,{"variant":"double"})
	var pair: Array=edge_info(key).cells; var next_pair: Array=edge_info(slots[1]).cells
	if _enclosure(data,pair[0])!=_enclosure(data,next_pair[0]) or _enclosure(data,pair[1])!=_enclosure(data,next_pair[1]): return false
	var midpoint: Vector2i=edge_info(key).b
	for other: String in effective:
		if other[0]==key[0]: continue
		var info := edge_info(other)
		if info.a==midpoint or info.b==midpoint: return false
	return true

func invalid_double_doors(level := 0) -> PackedStringArray:
	var level_edges := edges_at(level)
	var invalid := PackedStringArray()
	var effective := effective_edges(level)
	for key: String in level_edges:
		if level_edges[key].get("variant","") in DOUBLE_DOORS and not _double_fits(key,effective,level): invalid.append(key)
	return invalid

static func footprint(key: String, config: Dictionary) -> Array[String]:
	if not config.get("variant","") in DOUBLE_DOORS: return [key]
	var info := edge_info(key)
	var next: Vector2i = info.b
	return [key, edge_key("h" if key.begins_with("h:") else "v",next.x,next.y)]

func paint_edge(key: String, kind: int, variant: String,level := 0) -> String:
	var data := layer(level,true);var level_edges: Dictionary=data.edges
	var pair: Array = edge_info(key).cells
	var config := {"kind":kind,"variant":variant}
	if kind==Kind.DOOR and level_edges.get(key,{}).get("kind",-1)==Kind.DOOR:
		config=level_edges[key].duplicate(true); config.kind=kind; config.variant=variant
	if kind!=Kind.PASSAGE:
		var target := edge_info(key)
		for owner: String in level_edges:
			if not level_edges[owner].get("variant","") in DOUBLE_DOORS or key[0]==owner[0]: continue
			var midpoint: Vector2i=edge_info(owner).b
			if target.a==midpoint or target.b==midpoint: return "Cette cloison couperait une porte double."
	if variant in DOUBLE_DOORS and kind == Kind.DOOR:
		var slots := footprint(key,config)
		var second: Array = edge_info(slots[1]).cells
		if _enclosure(data,pair[0]) != _enclosure(data,second[0]) or _enclosure(data,pair[1]) != _enclosure(data,second[1]):
			return "Porte double : il faut deux bords alignes entre les memes pieces."
		var midpoint: Vector2i = edge_info(key).b
		var current := effective_edges(level)
		for other: String in current:
			if other[0] == key[0]: continue
			var info := edge_info(other)
			if info.a == midpoint or info.b == midpoint:
				return "Porte double : une cloison coupe le milieu de l'ouverture."
	for other: String in level_edges.keys():
		if key in footprint(other,level_edges[other]) or other in footprint(key,config): level_edges.erase(other)
	level_edges[key] = config
	return ""

func reset_edge(key: String,level := 0) -> void:
	var level_edges := edges_at(level)
	for other: String in level_edges.keys():
		if key in footprint(other,level_edges[other]): level_edges.erase(other)
