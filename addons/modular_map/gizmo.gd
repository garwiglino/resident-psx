@tool
extends EditorNode3DGizmoPlugin
const Map = preload("res://scripts/modular_map/map_3d.gd")
func _init() -> void: create_material("grid_2m",Color(.35,.78,.68,.7))
func _get_gizmo_name() -> String: return "Carte 2m"
func _has_gizmo(node: Node3D) -> bool: return node is Map
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var map: Node3D=gizmo.get_node_3d()
	if not map.layout:return
	var level := int(map.editor_storey);var bounds: Rect2=map.layout.plan_bounds(level)
	if not bounds.has_area():return
	var y := level*3.0
	var lines := PackedVector3Array()
	var low := Vector2i(bounds.position); var high := Vector2i(bounds.end)
	for cell: Vector2i in map.layout.cells_at(level):
		if map in EditorInterface.get_selection().get_selected_nodes():
			for key: String in map.layout.cell_edges(cell):
				var info: Dictionary=map.layout.edge_info(key)
				lines.append(Vector3(info.a.x*2,y+.015,info.a.y*2)); lines.append(Vector3(info.b.x*2,y+.015,info.b.y*2))
	var corners: Array[Vector3]=[Vector3(low.x*2,y,low.y*2),Vector3(high.x*2,y,low.y*2),Vector3(high.x*2,y,high.y*2),Vector3(low.x*2,y,high.y*2)]
	for i in 4:
		lines.append(corners[i]); lines.append(corners[(i+1)%4])
		lines.append(corners[i]+Vector3(0,3,0)); lines.append(corners[(i+1)%4]+Vector3(0,3,0))
		lines.append(corners[i]); lines.append(corners[i]+Vector3(0,3,0))
	gizmo.add_lines(lines,get_material("grid_2m",gizmo))
	gizmo.add_collision_segments(lines)
