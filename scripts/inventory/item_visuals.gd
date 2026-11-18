@tool
extends RefCounted
const Item=preload("res://scripts/inventory/item_definition.gd")
const PSX=preload("res://scripts/psx_materials.gd")

static func part(parent: Node,name: String,mesh: Mesh,material: Material,position := Vector3.ZERO,rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name=name; node.mesh=mesh; node.material_override=material; node.position=position; node.rotation=rotation; parent.add_child(node); return node
static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new(); mesh.size=size; return mesh
static func cylinder(radius: float,height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new(); mesh.top_radius=radius; mesh.bottom_radius=radius; mesh.height=height; mesh.radial_segments=12; mesh.rings=1; return mesh
static func fallback(item: Resource) -> Node3D:
	var root := Node3D.new(); root.name="Objet"
	var metal := PSX.make(Color(.58,.57,.5)); var dark := PSX.make(Color(.2,.24,.23))
	if item and item.kind==Item.Kind.KEY:
		var ring := TorusMesh.new(); ring.inner_radius=.022; ring.outer_radius=.036; ring.rings=12; ring.ring_segments=4
		part(root,"Anneau",ring,metal,Vector3(0,.045,0),Vector3(PI/2,0,0))
		part(root,"Tige",box(Vector3(.012,.1,.009)),metal,Vector3(0,-.025,0))
		for y in [-.05,-.07]: part(root,"Dent_"+str(y),box(Vector3(.028,.011,.009)),metal,Vector3(.01,y,0))
	elif item and item.kind==Item.Kind.ACCESS_CARD:
		part(root,"Badge",box(Vector3(.16,.1,.006)),PSX.make(Color(.7,.7,.61)))
		part(root,"Bande",box(Vector3(.15,.018,.002)),dark,Vector3(0,.02,.004))
		part(root,"Puce",box(Vector3(.025,.02,.002)),metal,Vector3(-.045,-.018,.004))
	elif item and String(item.id).contains("fuse"):
		part(root,"Ceramique",cylinder(.019,.09),PSX.make(Color(.7,.73,.66)))
		for y in [-.053,.053]: part(root,"Contact_"+str(y),cylinder(.021,.025),metal,Vector3(0,y,0))
	else:
		var color := Color(.36,.55,.42) if item and item.kind==Item.Kind.CONSUMABLE else Color(.62,.59,.44)
		part(root,"Corps",box(Vector3(.18,.12,.15)),PSX.make(color))
	return root
static func world(item: Resource) -> Node3D:
	return item.world_model.instantiate() if item and item.world_model else fallback(item)
static func _meshes(node: Node,parent_transform: Transform3D,result: Array[Dictionary]) -> void:
	var transform := parent_transform
	if node is Node3D:
		if not node.visible: return
		transform=parent_transform*node.transform
	if node is MeshInstance3D and node.mesh: result.append({"node":node,"transform":transform})
	for child in node.get_children(): _meshes(child,transform,result)
static func bounds(node: Node3D) -> AABB:
	var meshes: Array[Dictionary]=[]; _meshes(node,Transform3D.IDENTITY,meshes)
	var result := AABB(); var first := true
	for row in meshes:
		var value: AABB=row.transform*row.node.mesh.get_aabb()
		result=value if first else result.merge(value); first=false
	return result
static func inspection(item: Resource) -> Node3D:
	var scene: PackedScene=item.inspection_model if item.inspection_model else item.world_model
	if not scene and item.kind==Item.Kind.WEAPON and item.weapon: scene=item.weapon.scene
	var source: Node3D=scene.instantiate() if scene else fallback(item)
	var meshes: Array[Dictionary]=[]; _meshes(source,Transform3D.IDENTITY,meshes)
	var root := Node3D.new(); root.name="ApercuObjet"
	for row in meshes:
		var mesh := MeshInstance3D.new(); mesh.mesh=row.node.mesh; mesh.transform=row.transform
		for surface in mesh.mesh.get_surface_count(): mesh.set_surface_override_material(surface,PSX.character_material(row.node.get_active_material(surface)))
		root.add_child(mesh)
	source.free()
	if root.get_child_count()==0: root.free(); return fallback(item)
	return root
