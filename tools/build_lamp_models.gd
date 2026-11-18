extends SceneTree
const OUT="res://assets/lighting/models/"
func _initialize() -> void:call_deferred("run")
func mat(name: String,color: Color) -> Material:
	var value := StandardMaterial3D.new();value.resource_name=name;value.albedo_color=color
	value.specular_mode=BaseMaterial3D.SPECULAR_DISABLED;value.metallic_specular=0;value.roughness=1
	value.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST;return value
func part(root: Node3D,name: String,mesh: Mesh,material: Material,at: Vector3) -> MeshInstance3D:
	mesh.material=material
	var node := MeshInstance3D.new();node.name=name;node.mesh=mesh;node.position=at;root.add_child(node);node.owner=root;return node
func box(root: Node3D,name: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size=size;return part(root,name,mesh,material,at)
func cylinder(root: Node3D,name: String,radius: float,height: float,at: Vector3,material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=8;mesh.rings=1
	return part(root,name,mesh,material,at)
func save_model(root: Node3D,path: String) -> void:
	var packed := PackedScene.new();packed.pack(root);var error := ResourceSaver.save(packed,OUT+path+".tscn")
	assert(error==OK,"Cannot save lamp model: "+path);root.free()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var metal := mat("M_metal",Color(.32,.35,.36));var dark := mat("M_dark",Color(.09,.105,.11));var light := mat("M_light",Color.WHITE)
	var neon := Node3D.new();neon.name="NeonModele"
	box(neon,"Rail",Vector3(1.24,.055,.2),Vector3(0,.075,0),metal)
	box(neon,"Interieur",Vector3(1.12,.012,.17),Vector3(0,.041,0),dark)
	for side in [-1,1]:
		box(neon,"Support"+str(side),Vector3(.065,.075,.2),Vector3(side*.58,.045,0),metal)
		var tube := cylinder(neon,"Tube"+str(side),.022,1.07,Vector3(0,.025,side*.05),light);tube.rotation.z=PI/2
	save_model(neon,"neon")
	var wall := Node3D.new();wall.name="AppliqueModele"
	box(wall,"Platine",Vector3(.24,.4,.045),Vector3(0,0,.105),dark)
	box(wall,"Diffuseur",Vector3(.19,.3,.08),Vector3(0,0,.044),light)
	for side in [-1,1]:
		box(wall,"Montant"+str(side),Vector3(.027,.36,.11),Vector3(side*.11,0,.06),metal)
		box(wall,"Bord"+str(side),Vector3(.25,.04,.12),Vector3(0,side*.17,.06),metal)
	box(wall,"Grille",Vector3(.225,.018,.022),Vector3(0,0,-.004),metal)
	save_model(wall,"applique")
	var ceiling := Node3D.new();ceiling.name="PlafonnierModele"
	cylinder(ceiling,"Socle",.21,.06,Vector3(0,.065,0),dark)
	cylinder(ceiling,"Couronne",.195,.045,Vector3(0,.03,0),metal)
	cylinder(ceiling,"Diffuseur",.16,.022,Vector3(0,.006,0),light)
	save_model(ceiling,"plafonnier")
	print("LAMP_MODELS_OK: three low-poly fixture models with separate M_light surfaces");quit()
