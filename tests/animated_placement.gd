extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func item_uid(inventory: Node) -> String:
	for entry: Dictionary in inventory.model.sections[&"items"]:
		if not entry.is_empty() and entry.item.id==&"fuse_16a":return entry.uid
	return ""
func run() -> void:
	create_timer(40).timeout.connect(func():push_error("Animated placement timed out");quit(2))
	var inventory := root.get_node("InventoryState");inventory.persist_collection=false
	var world := root.get_node("WorldEvents");world.reset_run()
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/animated-export-validation.json"))
	var model_path: String=String(report.fixture).path_join("assets/props/generic_machine/generic_machine.model.scn")
	if not FileAccess.file_exists(model_path):push_error("Run the Blender animated export validation first");quit(1);return
	var info: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(String(report.fixture).path_join("assets/props/generic_machine/source.json")))
	var game: Node3D=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.pickup_feedback.enabled=false;game.set_process(false)
	game.player.set_process(false);game.player.set_physics_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var assembly: Node3D=load("res://scenes/inventory/placement_target.tscn").instantiate();assembly.interaction_id=&"test.exported_machine"
	var model: Node3D=load(model_path).instantiate();assembly.get_node("Modele").add_child(model)
	var part: Node3D=assembly.get_node("Emplacements/Emplacement");var other: Node3D=part.duplicate();other.name="Second";part.get_parent().add_child(other)
	var slots: Array[Node3D]=[part,other]
	for index in 2:
		var slot: Node3D=slots[index];slot.required_item=load("res://assets/inventory/items/fuse_16a.tres")
		var point: Node3D=slot.get_node("PointInsertion");var piece: Node3D=point.get_node("PieceInstallee")
		piece.add_child(load("res://scripts/inventory/item_visuals.gd").world(slot.required_item))
		var marker: Node3D=model.get_node(info.nodes["point_%d" % index]);point.owner=null;point.reparent(marker,false);point.transform=Transform3D.IDENTITY
		var area: Area3D=slot.get_node("ZoneSelection");area.owner=null;area.reparent(marker,false);area.transform=Transform3D.IDENTITY
		slot.placement_socket_path=slot.get_path_to(point);slot.installed_visual_path=slot.get_path_to(piece);slot.selection_area_path=slot.get_path_to(area)
		slot.highlight_paths.assign([slot.get_path_to(model.get_node(info.nodes.PanelSkinned))])
	part.animation_player_path=part.get_path_to(model.get_node(info.animations[0].player));part.installation_animation=info.animations[0].name
	game.level.add_child(assembly);assembly.position=Vector3(1000,0,1000)
	for frame in 3:await process_frame
	check(assembly.configuration_error().is_empty(),"Exporter output fits an ordinary authored multi-socket placement scene")
	var mesh: MeshInstance3D=model.get_node(info.nodes.PanelSkinned);var registered := false
	for entry in game.psx_renderer.entries:
		if entry.node==mesh:registered=true;check(entry.skeleton!=null and not entry.fixed,"Native PSX renderer retains the imported skin as dynamic geometry")
	check(registered,"Exported rigged model is registered by the native renderer")
	inventory.give(inventory.resolve_item(&"fuse_16a"),2,{},false)
	var controller: Node=game.item_placement
	check(assembly.interact(game.player) and controller.phase==controller.Phase.INSPECTING,"Exported mechanism opens cursor inspection before the inventory");controller.set_process(false)
	check(controller.select_part(part) and controller.choose(item_uid(inventory)),"First Blender bone socket accepts the item")
	controller._process(1);controller._process(1.1)
	check(world.interaction_used(part._id()) and not world.interaction_used(other._id()) and controller.phase==controller.Phase.INSPECTING,"Imported animation completes and keeps the second socket available")
	check(controller.select_part(other) and controller.choose(item_uid(inventory)),"Second Blender bone socket is independent")
	controller._process(1)
	check(not controller.is_active() and world.interaction_used(assembly._id()) and inventory.count(&"fuse_16a")==0,"Both inserted pieces complete the mechanism without losing the rig")
	var saved: Dictionary=world.snapshot();world.restore(saved)
	for frame in 4:await process_frame
	check(part.prepare_piece().visible and other.prepare_piece().visible,"Restoring world state keeps both independently attached pieces")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/animated-placement-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("ANIMATED_PLACEMENT_OK " if failures.is_empty() else "ANIMATED_PLACEMENT_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
