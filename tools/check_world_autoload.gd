extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	print("WORLD_AUTOLOAD setting=",ProjectSettings.get_setting("autoload/WorldEvents","MISSING"))
	for node in root.get_children():print("ROOT_NODE ",node.name," script=",node.get_script())
	var source=load("res://scripts/world_events/world_events.gd")
	print("WORLD_SCRIPT ",source," valid=",source.can_instantiate() if source else false)
	quit()
