extends SceneTree
const PSX=preload("res://scripts/psx_materials.gd")
func _initialize() -> void: call_deferred("run")
func attach(parent: Node,name: String,mesh: Mesh,position: Vector3,material: Material,rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name=name; node.mesh=mesh; node.material_override=material; node.position=position; node.rotation=rotation; parent.add_child(node); return node
func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new(); mesh.size=size; return mesh
func cylinder(radius: float,height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new(); mesh.top_radius=radius; mesh.bottom_radius=radius; mesh.height=height; mesh.radial_segments=12; mesh.rings=1; return mesh
func own(root_node: Node,node: Node) -> void:
	for child in node.get_children(): child.owner=root_node; own(root_node,child)
func run() -> void:
	var path := "res://scenes/inventory/valve_mechanism.tscn"
	if FileAccess.file_exists(path): push_error("Refusing to overwrite an authored valve scene."); quit(1); return
	var model := Node3D.new(); model.name="Mecanisme"
	var metal := PSX.make(Color(.28,.31,.29)); var dark := PSX.make(Color(.14,.17,.16)); var red := PSX.make(Color(.42,.14,.10))
	attach(model,"Socle",box(Vector3(.35,.08,.32)),Vector3(0,.04,0),dark)
	attach(model,"Conduite",cylinder(.055,.9),Vector3(0,.53,0),metal)
	for at in [.13,.93]: attach(model,"Bride_"+str(at),cylinder(.09,.035),Vector3(0,at,0),dark)
	attach(model,"Flasque",cylinder(.105,.08),Vector3(0,.73,.07),metal,Vector3(PI/2,0,0))
	attach(model,"Axe",box(Vector3(.055,.055,.14)),Vector3(0,.73,.14),dark)
	var wheel := Node3D.new(); wheel.name="RoueInstallee"; wheel.position=Vector3(0,.73,.2); wheel.visible=false; model.add_child(wheel)
	var rim := TorusMesh.new(); rim.inner_radius=.15; rim.outer_radius=.21; rim.rings=12; rim.ring_segments=4
	attach(wheel,"Cercle",rim,Vector3.ZERO,red,Vector3(PI/2,0,0))
	for index in 3: attach(wheel,"Rayon_"+str(index),box(Vector3(.33,.025,.025)),Vector3.ZERO,red,Vector3(0,0,index*PI/3))
	attach(wheel,"Moyeu",cylinder(.04,.055),Vector3.ZERO,metal,Vector3(PI/2,0,0))
	var body := StaticBody3D.new(); body.name="Collision"; body.collision_layer=1; body.collision_mask=0; model.add_child(body)
	var collision := CollisionShape3D.new(); collision.name="Volume"; var shape := BoxShape3D.new(); shape.size=Vector3(.24,1,.24); collision.shape=shape; collision.position=Vector3(0,.5,0); body.add_child(collision)
	own(model,model); var packed := PackedScene.new(); var error := packed.pack(model)
	if error==OK: error=ResourceSaver.save(packed,path)
	model.free(); print("VALVE_MECHANISM_OK " if error==OK else "VALVE_MECHANISM_FAILED ",error); quit(0 if error==OK else 1)
