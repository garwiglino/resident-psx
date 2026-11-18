extends SceneTree
## Static, editable map assembled from the seven modules in scene.blend.
const KIT := "res://assets/environment/scene_kit.glb"
const SIDES := {"N":Vector2i(0,-1),"E":Vector2i(1,0),"S":Vector2i(0,1),"W":Vector2i(-1,0)}
const YAWS := {"N":0.0,"E":-PI/2,"S":PI,"W":PI/2}
var level := Node3D.new()
var meshes: Dictionary={}
var cells: Dictionary={}
var edges: Dictionary={}
var used_edges: Dictionary={}
var modules := 0

func _initialize() -> void:call_deferred("build")

func build() -> void:
	level.name="CouloirPieces"
	root.add_child(level)
	var kit: Node=load(KIT).instantiate()
	for name in ["wall_straight","floor_tile","ceiling_tile","corner_inner","corner_outer","wall_door_frame","door"]:
		var source: MeshInstance3D=kit.find_child(name,true,false)
		assert(source!=null,"Missing Blender module: "+name)
		meshes[name]=source.mesh
	kit.free()
	# Each rectangle is specified on the two-metre grid, with open joins.
	_rect(-4,4,2,8)       # Entry, 8 x 6 m.
	_rect(-2,2,-22,4)     # Corridor, 4 m wide.
	_rect(-8,-2,-8,-2)    # Left room, 6 x 6 m.
	_rect(2,8,-16,-10)    # Right room, 6 x 6 m.
	_rect(-4,4,-28,-20)   # End room, 8 x 8 m.
	for cell: Vector2i in cells:
		var pos := _center(cell)
		var floor_node := _module("floor_tile",pos,0)
		_box(floor_node,Vector3(0,-.06,0),Vector3(2,.12,2))
		var ceiling := _module("ceiling_tile",pos+Vector3.UP*3,0)
		_box(ceiling,Vector3(0,.05,0),Vector3(2,.1,2))
		for side in SIDES:
			if cells.has(cell+SIDES[side]):continue
			var offset: Vector2i=SIDES[side]
			var position := pos+Vector3(offset.x,0,offset.y)
			edges[_key(cell,side)]={"cell":cell,"side":side,"position":position}
	# Reserve two end-wall panels for the exit doorway and its short fillers.
	for cell in [Vector2i(-1,-14),Vector2i(0,-14)]:used_edges[_key(cell,"N")]=true
	_convex_corners()
	_concave_corners()
	for key in edges:
		if used_edges.has(key):continue
		var edge: Dictionary=edges[key]
		_wall(edge.position,YAWS[edge.side],2,false)
	# Interior partitions separate the side rooms from the corridor.
	_partition(Vector3(-2,0,-5),PI/2,6)
	_partition(Vector3(2,0,-13),-PI/2,6)
	_doorway(Vector3(0,0,-28),0,false,false)
	_wall(Vector3(-1.75,0,-28),0,.5,false)
	_wall(Vector3(1.75,0,-28),0,.5,false)
	_markers()
	_power_panel()
	_assign_owners(level)
	var packed := PackedScene.new()
	assert(packed.pack(level)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/couloir_pieces.tscn")==OK)
	var report := {"source":KIT,"floor_tiles":cells.size(),"modules":modules,"doorway_clearance":1.5,"ceiling_height":3.0,
		"rooms":["Entry 8x6","Left 6x6","Right 6x6","End 8x8"],"corridor_width":4.0}
	FileAccess.open("res://docs/simple-map-build.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SIMPLE_MAP_BUILD_OK ",JSON.stringify(report))
	level.queue_free()
	await process_frame
	quit()

func _rect(x0: int,x1: int,z0: int,z1: int) -> void:
	for x in range(x0,x1,2):
		for z in range(z0,z1,2):cells[Vector2i(x/2,z/2)]=true

func _center(cell: Vector2i) -> Vector3:return Vector3(cell.x*2+1,0,cell.y*2+1)
func _key(cell: Vector2i,side: String) -> String:return "%d,%d,%s" % [cell.x,cell.y,side]

func _module(part: String,position: Vector3,yaw: float,width_scale := 1.0,parent: Node3D=null) -> Node3D:
	var node := Node3D.new()
	node.name="%s_%03d" % [part,modules]
	modules+=1
	(parent if parent else level).add_child(node)
	node.position=position
	node.rotation.y=yaw
	node.set_meta("source_module",part)
	var mesh := MeshInstance3D.new()
	mesh.name="Mesh"
	mesh.mesh=meshes[part]
	mesh.scale.x=width_scale
	node.add_child(mesh)
	return node

func _box(parent: Node3D,position: Vector3,size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name="Collision"
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape=BoxShape3D.new()
	shape.shape.size=size
	shape.position=position
	body.add_child(shape)

func _wall(position: Vector3,yaw: float,width: float,both_sides: bool) -> void:
	var node := _module("wall_straight",position,yaw,width/2)
	_box(node,Vector3(0,1.5,-.1),Vector3(width,3,.2))
	if both_sides:_module("wall_straight",position+Basis(Vector3.UP,yaw)*Vector3(0,0,-.2),yaw+PI,width/2)

func _convex_corners() -> void:
	var cases := [["N","E",0.0],["N","W",PI/2],["S","W",PI],["S","E",-PI/2]]
	for cell: Vector2i in cells:
		for pair in cases:
			var a := _key(cell,pair[0])
			var b := _key(cell,pair[1])
			if not edges.has(a) or not edges.has(b) or used_edges.has(a) or used_edges.has(b):continue
			var node := _module("corner_outer",_center(cell),pair[2])
			_box(node,Vector3(1.05,1.5,0),Vector3(.1,3,2.1))
			_box(node,Vector3(0,1.5,-1.05),Vector3(2.1,3,.1))
			used_edges[a]=true
			used_edges[b]=true

func _concave_corners() -> void:
	var missing: Dictionary={}
	for cell: Vector2i in cells:
		for offset: Vector2i in SIDES.values():
			if not cells.has(cell+offset):missing[cell+offset]=true
	var cases := [[Vector2i(-1,0),Vector2i(0,1),"E","N",0.0],
		[Vector2i(0,1),Vector2i(1,0),"N","W",PI/2],
		[Vector2i(1,0),Vector2i(0,-1),"W","S",PI],
		[Vector2i(0,-1),Vector2i(-1,0),"S","E",-PI/2]]
	for cell: Vector2i in missing:
		for pair in cases:
			var a: Vector2i=cell+pair[0]
			var b: Vector2i=cell+pair[1]
			if not cells.has(a) or not cells.has(b) or not cells.has(cell+pair[0]+pair[1]):continue
			var ka := _key(a,pair[2])
			var kb := _key(b,pair[3])
			if used_edges.has(ka) or used_edges.has(kb):continue
			var node := _module("corner_inner",_center(cell),pair[4])
			_box(node,Vector3(-.95,1.5,0),Vector3(.1,3,2))
			_box(node,Vector3(0,1.5,.95),Vector3(2,3,.1))
			used_edges[ka]=true
			used_edges[kb]=true

func _partition(position: Vector3,yaw: float,length: float) -> void:
	_doorway(position,yaw,true,true)
	var filler := (length-3.0)*.5
	for side in [-1,1]:
		_wall(position+Basis(Vector3.UP,yaw)*Vector3(side*(1.5+filler*.5),0,0),yaw,filler,true)

func _doorway(position: Vector3,yaw: float,opened: bool,both_sides: bool) -> void:
	var node := _module("wall_door_frame",position,yaw,1.5)
	for x in [-1.125,1.125]:_box(node,Vector3(x,1.5,-.1),Vector3(.75,3,.2))
	_box(node,Vector3(0,2.6,-.1),Vector3(1.5,.8,.2))
	if both_sides:_module("wall_door_frame",position+Basis(Vector3.UP,yaw)*Vector3(0,0,-.202),yaw+PI,1.5)
	var hinge := Node3D.new()
	hinge.name="OpenDoor" if opened else "ExitDoor"
	node.add_child(hinge)
	hinge.position=Vector3(-.75,0,-.1)
	hinge.rotation.y=deg_to_rad(100) if opened else 0.0
	_module("door",Vector3(.75,0,.1),0,1.5,hinge)
	_box(hinge,Vector3(.75,1.1,0),Vector3(1.5,2.2,.12))

func _markers() -> void:
	var lights := Node3D.new();lights.name="Lumieres";level.add_child(lights)
	var markers := Node3D.new()
	markers.name="Gameplay"
	level.add_child(markers)
	var positions := {"PlayerSpawn":Vector3(0,.05,6.2),"Fuse":Vector3(-6,.16,-5),"AmmoA":Vector3(6,.16,-14),
		"Medkit":Vector3(-2.7,.16,5.5),"AmmoB":Vector3(-2.5,.16,-25),"Power":Vector3(7.5,1.25,-13),"Exit":Vector3(0,1,-27.5)}
	for name in positions:
		var marker := Marker3D.new()
		marker.name=name
		marker.position=positions[name]
		markers.add_child(marker)

func _power_panel() -> void:
	# Keep the existing fuse interaction visible, using the supplied atlas.
	var panel := MeshInstance3D.new()
	panel.name="PowerPanel"
	level.add_child(panel)
	panel.position=Vector3(7.94,1.25,-13)
	panel.rotation.y=-PI/2
	var material := StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/environment/surfaces_panel.png")
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var points := [Vector3(-.28,-.4,0),Vector3(.28,-.4,0),Vector3(.28,.4,0),Vector3(-.28,.4,0)]
	var uvs := [Vector2(0,.5),Vector2(.5,.5),Vector2(.5,0),Vector2(0,0)]
	for index in [0,2,1,0,3,2]:
		surface.set_normal(Vector3.BACK)
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])
	panel.mesh=surface.commit()

func _assign_owners(node: Node) -> void:
	for child in node.get_children():
		child.owner=level
		_assign_owners(child)
