extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var trigger=load("res://scripts/dialogue/dialogue_trigger_3d.gd").new()
	root.add_child(trigger)
	check(trigger.get_node_or_null("Volume") is CollisionShape3D,"Adding the dialogue class directly creates a visible native volume")
	var volume: CollisionShape3D=trigger.get_node("Volume")
	check(volume.shape is BoxShape3D and volume.shape.size==Vector3(2,3,2),"Default trigger is a 2 x 3 x 2 m box")
	var packed := PackedScene.new()
	check(packed.pack(trigger)==OK,"Generated collision is owned and can be saved")
	var restored=packed.instantiate();root.add_child(restored)
	check(restored.get_child_count()==1 and restored.get_node("Volume").shape is BoxShape3D,"Save/reload keeps exactly one native collision box")
	var authored=load("res://scenes/dialogue/dialogue_trigger.tscn").instantiate()
	authored.get_node("Volume").shape.size=Vector3(4,2,5);root.add_child(authored)
	check(authored.get_child_count()==1 and authored.get_node("Volume").shape.size==Vector3(4,2,5),"Existing authored volume dimensions remain intact")
	trigger.queue_free();restored.queue_free();authored.queue_free();await process_frame
	print("TRIGGER_VOLUME_OK" if failures.is_empty() else "TRIGGER_VOLUME_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
