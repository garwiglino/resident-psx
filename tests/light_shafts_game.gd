extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle() -> void:
	for frame in 4:await process_frame
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("Shaft gameplay validation timeout");quit(2));root.get_node("InventoryState").persist_collection=false
	var game: Node3D=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.set_process(false);game.player.set_process(false);game.player.set_physics_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var source: MeshInstance3D=load("res://scenes/effects/window_light_shaft.tscn").instantiate();source.position=Vector3(1000,1.5,1000);game.level.add_child(source)
	var camera := Camera3D.new();game.add_child(camera);camera.position=Vector3(1003,1.5,997);camera.look_at(Vector3(1000,.8,999));camera.make_current()
	var renderer: Node=game.psx_renderer;renderer.set_active_camera(camera);renderer.fog_enabled=false;renderer.ambient_light_color=Color.BLACK;await settle();renderer._process(0)
	var matching: Array=renderer.entries.filter(func(entry: Dictionary):return entry.node==source)
	check(matching.size()==1 and matching[0].fixed and matching[0].blend_mode==1,"Gameplay caches the placed effect as static additive geometry")
	check(renderer.primitives.any(func(packet: Dictionary):return packet.blend_mode==1),"Real gameplay renderer submits the effect with its correct blend equation")
	var before := source.mesh.get_aabb();source.length=2.6;await settle();renderer._process(0)
	matching=renderer.entries.filter(func(entry: Dictionary):return entry.node==source)
	check(source.mesh.get_aabb().size.z<before.size.z and matching.size()==1 and matching[0].aabb.size.z<2.61,"Live shape changes replace the gameplay geometry without duplicating it")
	source.shaft_material.strength=1.2;source.shaft_material.color=Color(.6,.8,1);await settle();renderer._process(0)
	matching=renderer.entries.filter(func(entry: Dictionary):return entry.node==source)
	check(matching[0].source_color.is_equal_approx(source.shaft_material.color*source.shaft_material.strength),"Gameplay receives independent color/strength edits")
	source.hide();await settle();renderer._process(0);check(not renderer.primitives.any(func(packet: Dictionary):return packet.blend_mode==1),"Hiding the effect releases its additive draws in gameplay")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/light-shafts-game-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("LIGHT_SHAFTS_GAME_OK " if failures.is_empty() else "LIGHT_SHAFTS_GAME_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
