extends SceneTree
const Layout = preload("res://scripts/modular_map/layout.gd")
var Map: Script
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)
func run() -> void:
	Map=load("res://scripts/modular_map/map_3d.gd")
	var kit=load("res://assets/environment/modular_2m/default_kit.tres")
	check(kit.data.modules.size()>=15,"All original source modules remain available alongside new authored meshes")
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/modular_2m/kit_source.json"))
	var atlases := {}
	for index in metadata.pages.size():
		var page: Dictionary=metadata.pages[index]; var rect: Array=page.rect
		if not atlases.has(page.atlas_file):
			var source := Image.new()
			check(source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://exports/modular/"+page.atlas_file))==OK,"Source atlas loads: "+page.atlas_file)
			atlases[page.atlas_file]=source
		var atlas: Image=atlases[page.atlas_file]
		var material_index: int=metadata.materials.find_custom(func(material: Dictionary): return int(material.page)==index)
		check(material_index>=0,"Every page has a material: "+page.name)
		if material_index<0 or atlas.is_empty():continue
		var image: Image=kit.data.materials[material_index].albedo_texture.get_image()
		check(image.get_width()<=256 and image.get_height()<=256,"Native PSX page dimensions")
		var exact := true
		for y in image.get_height():
			for x in image.get_width():
				var sx := posmod(x+int(rect[0]),atlas.get_width())
				var sy := posmod(y+atlas.get_height()-int(rect[1])-int(rect[3]),atlas.get_height())
				if image.get_pixel(x,y)!=atlas.get_pixel(sx,sy): exact=false
		check(exact,"Every exported texel matches the original atlas: "+page.name)
	for name in ["wall_loop","wall_door","wall_door_double","wall_loop_window"]:
		var positive := 0; var negative := 0
		for surface: Dictionary in kit.data.modules[name]:
			for i in range(0,surface.vertices.size(),3):
				var p: Vector3=surface.vertices[i]; var n: Vector3=surface.normals[i]
				if absf(p.z)<.00001 and p.y>=.9999 and absf(n.z)>.99:
					if n.z>0: positive+=1
					else: negative+=1
		check(positive>0 and positive==negative,"Upper wallpaper renders from both sides: "+name)
	for name in ["wall_loop","wall_loop_simple","wall_door","wall_loop_window"]:
		var bounds: AABB=kit.mesh_for(name).get_aabb()
		check(is_equal_approx(bounds.size.x,2),name+" has an exact 2 m reference")
	check(is_equal_approx(kit.mesh_for("wall_door_double").get_aabb().size.x,4),"Double door spans exactly 4 m")
	check(kit.mesh_for("door_01").get_aabb().position.is_equal_approx(Vector3(0,0,-.0603299)),"Door hinge origin and authored handle depth retained")
	var ceiling_normal: Vector3=kit.mesh_for("ceiling").surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]
	check(ceiling_normal.dot(Vector3.DOWN)>.9999,"Ceiling faces down in the game")
	for variant in ["01","02","03"]:
		var l: AABB=kit.mesh_for("double_door_left_"+variant).get_aabb()
		var r: AABB=kit.mesh_for("double_door_right_"+variant).get_aabb()
		check(is_zero_approx(l.position.x) and is_equal_approx(l.end.x,1.0) and is_equal_approx(r.position.x,-1.0) and is_zero_approx(r.end.x),"Both authored leaves fit their opposite hinges: "+variant)
	var meshes := 0
	for name in ["wall_loop","wall_loop_simple","wall_door","wall_door_double","wall_loop_window"]:
		for start in 8:
			for finish in 8:
				var mesh: Mesh=kit.mesh_for(name,start,finish)
				check(mesh.get_surface_count()>0,"Joint variant has geometry")
				for surface in mesh.get_surface_count():
					var a: Array=mesh.surface_get_arrays(surface)
					for normal: Vector3 in a[Mesh.ARRAY_NORMAL]:
						check(is_finite(normal.x) and absf(normal.length()-1)<.0001,"Finite unit normals after mitre")
				meshes+=1
	# A right-angle pair must meet at the same 45-degree profile, not overlap.
	var corner: Mesh=kit.mesh_for("wall_loop",2,0)
	var checked := 0
	for s in corner.get_surface_count():
		for p: Vector3 in corner.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if p.x < -.8:
				check(absf(p.x+1-p.z)<.00002,"Corner end strip flattened to exact mitre plane")
				checked+=1
	check(checked>10,"Miter test includes profiled lower panels")
	var layout := Layout.new(); var left := layout.add_room(); var right := layout.add_room()
	for x in 4:
		for z in 3: layout.paint_cell(Vector2i(x,z),left if x<2 else right)
	var edges: Dictionary=layout.effective_edges()
	check(edges.size()==17,"Two adjacent 2x3 rooms share one 3-edge partition")
	check(edges.has("v:2:1") and not edges.has("v:1:1"),"Walls between rooms, open space within a room")
	check(layout.paint_edge("v:2:1",Layout.Kind.DOOR,"solid").is_empty(),"Single door paints on a partition")
	layout.edges["v:2:1"]["opened_event"]="door.custom_event"
	layout.paint_edge("v:2:1",Layout.Kind.DOOR,"glass")
	check(layout.edges["v:2:1"].get("opened_event","")=="door.custom_event","Changing a door model retains its events")
	check(layout.paint_edge("h:0:0",Layout.Kind.DOOR,"double").is_empty(),"Double door fits two exterior slots")
	check(not layout.effective_edges().has("h:1:0"),"Double door consumes the second slot, no wall through its opening")
	for variant in ["double_02","double_03"]:
		check(layout.paint_edge("h:0:0",Layout.Kind.DOOR,variant).is_empty() and not layout.effective_edges().has("h:1:0"),"Alternate double door reserves both cells: "+variant)
	check(not layout.paint_edge("h:1:0",Layout.Kind.DOOR,"double").is_empty(),"Double door rejects a partition through its midpoint")
	check(not layout.paint_edge("v:1:0",Layout.Kind.WALL,"wall_loop").is_empty(),"A new partition cannot cut an existing double door")
	var modified := Layout.new(); modified.restore(layout.snapshot())
	modified.paint_cell(Vector2i(1,0),right)
	check(not modified.invalid_double_doors().is_empty(),"Room repaint exposes invalid double-door warning")
	check(modified.effective_edges()["h:0:0"].kind==Layout.Kind.WALL,"An invalid double opening falls back to complete walls")
	layout.paint_edge("v:4:1",Layout.Kind.WINDOW,"boarded")
	var map: Node3D = Map.new(); map.layout=layout; map.kit=kit; map.event_namespace="test_modular"
	root.add_child(map)
	await process_frame; await physics_frame; await physics_frame
	check(map.generated.get_children().size()>12,"Runtime builds floors, ceilings and walls")
	check(map.generated.find_children("Porte","",true,false).size()==2,"Doors generated as world interactions")
	var world=root.get_node("WorldEvents"); world.reset_run()
	var door=map.generated.get_node("Bord_v_2_1/Porte")
	check(door.interact(),"Painted door responds to existing interaction system")
	check(world.fact(&"door.test_modular.v_2_1.open",false),"Painted door writes a stable world fact")
	# Rays through the top of the portal stay clear; neighbouring solid wall blocks.
	map.generated.get_node("Bord_h_0_0/Porte").open()
	await create_timer(.6).timeout
	await physics_frame
	var space := root.world_3d.direct_space_state
	var open_ray := PhysicsRayQueryParameters3D.create(Vector3(2,1.5,-.5),Vector3(2,1.5,.5))
	check(space.intersect_ray(open_ray).is_empty(),"Double frame opening has no invisible rectangular wall")
	var wall_ray := PhysicsRayQueryParameters3D.create(Vector3(3,1.5,5.5),Vector3(3,1.5,6.5))
	check(not space.intersect_ray(wall_ray).is_empty(),"Authored two-sided wall collision works")
	var packed := PackedScene.new(); packed.pack(map)
	var path := "res://exports/modular/runtime_roundtrip.tscn"
	ResourceSaver.save(packed,path)
	check(FileAccess.get_file_as_string(path).length()<12000,"Saved scene stores plan, not generated binary geometry")
	var restored: Node3D=load(path).instantiate(); root.add_child(restored)
	check(restored.layout.cells==layout.cells and restored.layout.edges==layout.edges,"Layout survives save/load")
	check(restored.generated.find_children("Porte","",true,false).size()==2,"Runtime regeneration survives save/load")
	var nested := Node3D.new(); nested.name="LevelContainer"
	root.remove_child(restored); nested.add_child(restored); restored.owner=nested; root.add_child(nested)
	var state: Dictionary=restored.layout.snapshot(); state.cells[Vector2i(8,1)]=left
	restored.apply_plan(state)
	var nested_scene := PackedScene.new(); nested_scene.pack(nested)
	ResourceSaver.save(nested_scene,"res://exports/modular/instance_roundtrip.tscn")
	var loaded_nested: Node3D=load("res://exports/modular/instance_roundtrip.tscn").instantiate()
	check(loaded_nested.get_child(0).layout.cells.has(Vector2i(8,1)),"Painted layout override persists on an instanced map")
	check(not map.layout.cells.has(Vector2i(8,1)),"Instanced map edit leaves source layout independent")
	loaded_nested.free(); map.free(); nested.free()
	var result := {"ok":failures.is_empty(),"joint_variants":meshes,"corner_vertices":checked,"errors":failures}
	var file := FileAccess.open("res://docs/modular-map-validation.json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	print("MODULAR_MAP_OK " if failures.is_empty() else "MODULAR_MAP_FAILED ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
