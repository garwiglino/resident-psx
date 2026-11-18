@tool
extends EditorNode3DGizmoPlugin
const Lamp=preload("res://scripts/lighting/psx_lamp_3d.gd")

func _init() -> void:
	create_material("bounds",Color(.95,.8,.35,.7))

func _has_gizmo(node: Node3D) -> bool:return node is Lamp
func _get_gizmo_name() -> String:return "Lampe PSX"
func _get_priority() -> int:return 1
func _is_selectable_when_hidden() -> bool:return true

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var lamp: Node3D=gizmo.get_node_3d()
	var faces: PackedVector3Array=lamp.get_editor_pick_faces()
	if not faces.is_empty():
		var triangles := TriangleMesh.new()
		if triangles.create_from_faces(faces):gizmo.add_collision_triangles(triangles)
	# Generated meshes have no scene owner. Their picking geometry belongs to
	# the authorable lamp root, so normal editor transform tools work on it.
	var bounds := AABB(Vector3(-.1,-.1,-.1),Vector3(.2,.2,.2))
	if not faces.is_empty():
		bounds=AABB(faces[0],Vector3.ZERO)
		for point in faces:bounds=bounds.expand(point)
	var lines := PackedVector3Array()
	for axis in 3:
		for corner in 8:
			if corner & (1<<axis):continue
			lines.append(bounds.get_endpoint(corner));lines.append(bounds.get_endpoint(corner | (1<<axis)))
	if faces.is_empty():gizmo.add_collision_segments(lines)
	if lamp in EditorInterface.get_selection().get_selected_nodes():gizmo.add_lines(lines,get_material("bounds",gizmo))
