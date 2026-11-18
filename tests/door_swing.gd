extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: failures.append(message); push_error(message)
func run() -> void:
	var Map=load("res://scripts/modular_map/map_3d.gd"); var Layout=load("res://scripts/modular_map/layout.gd")
	var actor := Node3D.new(); root.add_child(actor)
	for style in ["solid","glass","door_03","double","double_02","double_03"]:
		var map: Node3D=Map.new(); map.layout=Layout.new(); map.kit=load("res://assets/environment/modular_2m/default_kit.tres"); map.event_namespace="swing_"+style
		var id: int=map.layout.add_room()
		for x in 2:
			for z in 2: map.layout.paint_cell(Vector2i(x,z),id)
		map.layout.paint_edge("h:0:0",Layout.Kind.DOOR,style); root.add_child(map)
		var door: Node3D=map.generated.get_node("Bord_h_0_0/Porte"); door.duration=0
		for yaw in [0.0,PI/2]:
			map.rotation.y=yaw
			for side in [-1.0,1.0]:
				actor.global_position=door.to_global(Vector3(0,0,side*1.5))
				var pivots: Array[Node3D]=[door.get_node("Pivot")]
				if door.has_node("RightPivot"): pivots.append(door.get_node("RightPivot"))
				var free_edges: Array[Vector3]=[]
				for pivot in pivots:
					var leaf: MeshInstance3D=pivot.get_child(0)
					free_edges.append(Vector3(leaf.mesh.get_aabb().get_center().x,1.1,0))
				var closed: Array[Vector3]=[]
				for index in pivots.size(): closed.append(pivots[index].to_global(free_edges[index]))
				check(door.interact(actor),"Door opens from either side")
				for index in pivots.size():
					var movement: Vector3=pivots[index].to_global(free_edges[index])-closed[index]
					check(movement.dot(actor.global_position-door.global_position)<-.05,"Each leaf swings away from the player for both orientations")
				check(door.interact(actor),"Door closes using its previous swing")
				for index in pivots.size(): check(pivots[index].to_global(free_edges[index]).distance_to(closed[index])<.0001,"Closed hinge transform is restored exactly")
		map.free()
	actor.free()
	FileAccess.open("res://docs/door-swing-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("DOOR_SWING_OK" if failures.is_empty() else "DOOR_SWING_FAILED "+str(failures)); quit(0 if failures.is_empty() else 1)
