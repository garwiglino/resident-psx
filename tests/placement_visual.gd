extends SceneTree
var game: Node3D
var inventory: Node
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func capture(name: String) -> void:
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image();image.resize(960,720,Image.INTERPOLATE_NEAREST)
	image.save_png("res://docs/placement-"+name+".png")
func click(slot: Control) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new();event.position=slot.get_global_rect().get_center();event.global_position=event.position
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event)
func run() -> void:
	root.size=Vector2i(320,240);inventory=root.get_node("InventoryState");inventory.persist_collection=false
	root.get_node("WorldEvents").reset_run()
	game=load("res://scenes/systemes_jeu.tscn").instantiate()
	var level: Node3D=load("res://scenes/examples/inventory_demo.tscn").instantiate();level.name="Map";game.add_child(level)
	for area in level.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.pickup_feedback.enabled=false
	for enemy in game.enemies:enemy.active=false;enemy.set_physics_process(false)
	for id: StringName in [&"valve_wheel",&"lever_handle",&"fuse_16a"]:inventory.give(inventory.resolve_item(id),1,{},false)
	var station: Node3D=level.get_node_or_null("MecanismeObjet")
	if not station:station=level.get_node("PlacementVanne")
	var completion: Resource=load("res://scripts/world_events/world_action.gd").new();completion.kind=1;completion.id=&"test.placement.visual.finished";station.actions.append(completion)
	game.player.global_position=station.global_transform*Vector3(0,0,.9);game.player.global_rotation.y=station.global_rotation.y;game.player.reset_camera_follow()
	await physics_frame;game._process(0)
	check(game.nearest.get("node")==station,"Existing map station is selected by the normal proximity interaction")
	var interact := InputEventAction.new();interact.action="interact";interact.pressed=true;game._input(interact)
	var controller: Node=game.item_placement;controller.set_process(false)
	check(controller.is_active(),"Real E action opens the inherited station in inventory_demo")
	check(controller.phase==controller.Phase.INSPECTING and not controller.menu.canvas.visible,"E first shows the fixed inspection view")
	controller.select_part(station)
	await capture("choose")
	check(not game.hud.prompt.visible and not game.hud.ammo_label.visible,"Gameplay HUD is hidden throughout the station view")
	click(controller.menu.grid.get_child(1));await process_frame
	check(controller._wrong_pending,"Real slot click selects the wrong part")
	game.dialogue.set_process(false);game.dialogue._process(.9);await capture("wrong-item")
	for tick in 500:
		if not controller._wrong_pending:break
		game.dialogue._process(.1)
	check(not controller._wrong_pending,"Wrong-item auto reply returns to picker")
	for frame in 3:await process_frame
	click(controller.menu.grid.get_child(0));await process_frame
	check(controller.phase==controller.Phase.PLACING,"Real slot click starts correct-part installation")
	controller._process(station.placement_duration*.5);await capture("insert")
	controller._process(station.placement_duration)
	controller._process(10)
	check(not controller.is_active() and station.prepare_piece().visible,"Insertion returns to gameplay")
	for frame in 3:await process_frame
	check(root.get_node("WorldEvents").flag(&"test.placement.visual.finished"),"Placement publishes its authored completion actions")
	await capture("done")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	print("PLACEMENT_VISUAL_OK " if failures.is_empty() else "PLACEMENT_VISUAL_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
