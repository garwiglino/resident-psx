extends SceneTree
const World = preload("res://scripts/world.gd")
const Materials = preload("res://scripts/psx_materials.gd")

func _initialize() -> void:
	Materials.initialize()
	var level := World.new()
	root.add_child(level)
	level.build()
	assign_owners(level,level)
	level.set_script(null)
	var packed := PackedScene.new()
	var result := packed.pack(level)
	if result==OK:
		result=ResourceSaver.save(packed,"res://scenes/annexe.tscn")
	print("LEVEL_SAVE ",result)
	level.queue_free()
	quit(result)

func assign_owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner=owner_node
		assign_owners(child,owner_node)
