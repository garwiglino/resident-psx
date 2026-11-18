extends SceneTree
const Visuals=preload("res://scripts/inventory/item_visuals.gd")
const PSX=preload("res://scripts/psx_materials.gd")
func _initialize() -> void: call_deferred("run")
func own(root_node: Node,node: Node) -> void:
	for child in node.get_children(): child.owner=root_node; own(root_node,child)
func save_model(node: Node3D,path: String) -> void:
	if not FileAccess.file_exists(path):
		own(node,node); var packed := PackedScene.new(); assert(packed.pack(node)==OK); assert(ResourceSaver.save(packed,path)==OK)
	node.free()
func run() -> void:
	var base := "res://assets/inventory/models/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var source: Node3D=load("res://scenes/inventory/valve_mechanism.tscn").instantiate()
	var wheel: Node3D=source.get_node("RoueInstallee").duplicate(); wheel.name="RoueDeVanne"; wheel.transform=Transform3D.IDENTITY; wheel.visible=true; source.free()
	save_model(wheel,base+"valve_wheel.tscn")
	var lever := Node3D.new(); lever.name="PoigneeLevier"
	var metal := PSX.make(Color(.5,.53,.48)); var red := PSX.make(Color(.45,.16,.11))
	Visuals.part(lever,"Tige",Visuals.cylinder(.014,.28),metal,Vector3(0,-.02,0))
	Visuals.part(lever,"Embase",Visuals.cylinder(.026,.025),metal,Vector3(0,-.16,0))
	Visuals.part(lever,"Poignee",Visuals.cylinder(.025,.15),red,Vector3(0,.13,0),Vector3(0,0,PI/2))
	save_model(lever,base+"lever_handle.tscn")
	for id: String in ["valve_wheel","lever_handle"]:
		var path: String="res://assets/inventory/items/"+id+".tres"
		var item: Resource=load(path)
		if not item.world_model: item.world_model=load(base+id+".tscn")
		if id=="lever_handle": item.essential=true
		assert(ResourceSaver.save(item,path)==OK)
	print("FOUND_ITEM_MODELS_OK"); quit()
