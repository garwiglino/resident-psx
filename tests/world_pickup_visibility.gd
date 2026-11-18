extends SceneTree
var errors: Array[String]=[]
var game: Node
var inventory: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: errors.append(message); push_error(message)
func settle(frames := 8) -> void:
	for frame in frames: await process_frame
func registered(node: Node) -> int:
	var count := 0
	for entry: Dictionary in game.psx_renderer.entries:
		if is_instance_valid(entry.node) and node.is_ancestor_of(entry.node): count+=1
	return count
func run() -> void:
	root.size=Vector2i(320,240); inventory=root.get_node("InventoryState")
	var profile_hash := FileAccess.get_sha256(inventory.collection_file)
	inventory.persist_collection=false; inventory.collection.clear()
	var level: Node3D=load("res://scenes/examples/inventory_demo.tscn").instantiate(); root.add_child(level); current_scene=level
	await settle(20); game=current_scene
	game.pickup_feedback.enabled=false
	game.player.set_physics_process(false); game.player.enabled=false
	var card: Node3D=game.level.get_node("Carte_1")
	card.set_process(false)
	check(card.enabled and card._visual.visible and registered(card)==2,"Uncollected authored cards register both faces during real F6 startup")
	var camera := Camera3D.new(); game.add_child(camera); camera.global_position=card.global_position+Vector3(0,.4,.7); camera.look_at(card.global_position+Vector3.UP*.21); camera.fov=50
	game.psx_renderer.set_active_camera(camera); await settle(3); await RenderingServer.frame_post_draw
	var at := camera.unproject_position(card._visual.global_position)
	var image := root.get_texture().get_image(); image.save_png("res://docs/card-in-game.png")
	# The center can lie on the black question mark; compare the rendered card area.
	card._visual.hide(); game.psx_renderer._process(0); await RenderingServer.frame_post_draw
	var without_card := root.get_texture().get_image(); var changed := 0
	for y in range(maxi(0,roundi(at.y)-80),mini(image.get_height(),roundi(at.y)+80)):
		for x in range(maxi(0,roundi(at.x)-45),mini(image.get_width(),roundi(at.x)+45)):
			if image.get_pixel(x,y).get_luminance()-without_card.get_pixel(x,y).get_luminance()>.03: changed+=1
	check(changed>100,"Uncollected card is visibly drawn in the actual gameplay raster")
	card._visual.show(); card.set_process(true)
	var spawned: Node3D=load("res://scenes/inventory/card_pickup.tscn").instantiate(); spawned.card_id=inventory.catalogue.cards[4].id; game.level.add_child(spawned); spawned.global_position=card.global_position+Vector3(.5,0,0)
	await settle()
	check(registered(spawned)==2,"A card created after gameplay startup also appears in the native renderer")
	card.card_height=.32; await settle()
	check(registered(card)==2,"Changing a card's visual settings refreshes its rendered faces rather than losing them")
	var target: Node3D=game.level.get_node_or_null("MecanismeObjet")
	if not target:target=game.level.get_node("PlacementVanne")
	var completion: Resource=load("res://scripts/world_events/world_action.gd").new();completion.kind=1;completion.id=&"test.placement.visibility.finished";target.actions.append(completion)
	check(not target.find_children("*","MeshInstance3D",true,false).is_empty(),"Wheel installation has a visible mechanism rather than an empty marker")
	var model: Node3D=target.get_node(target.visual_path); var wheel: Node3D=target.get_node(target.installed_visual_path)
	check(target.can_interact() and not wheel.visible and registered(target)>0,"Empty socket is visible and registered before installation")
	model.visible=false; check(not target.can_interact(),"Hidden mechanism never offers an interaction prompt"); model.visible=true
	var empty: Node3D=load("res://scripts/inventory/item_target.gd").new(); empty.required_item_id=&"valve_wheel"; game.level.add_child(empty)
	check(not empty.can_interact(),"A bare marker without a model cannot offer a phantom interaction")
	inventory.give(inventory.resolve_item(&"valve_wheel"))
	var before_install: Dictionary=root.get_node("WorldEvents").snapshot()
	check(target.interact(game.player),"Inspecting the socket opens the new placement view")
	game.item_placement.set_process(false)
	game.item_placement.select_part(target)
	for entry: Dictionary in inventory.model.sections[&"items"]:
		if not entry.is_empty() and entry.item.id==&"valve_wheel":game.item_placement.choose(entry.uid);break
	game.item_placement._process(target.placement_duration)
	game.item_placement._process(10)
	check(wheel.visible and inventory.count(&"valve_wheel")==0,"Installing the part visibly mounts the wheel and consumes one item")
	await settle()
	check(root.get_node("WorldEvents").flag(&"test.placement.visibility.finished") and not target.can_interact(),"Installed mechanism publishes its world event and stops requesting another wheel")
	camera.global_position=target.global_position+Vector3(.5,1.0,1.7); camera.look_at(target.get_interaction_position()); camera.fov=45
	await settle(3); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/wheel-installed-in-game.png")
	check(root.get_node("WorldEvents").restore(before_install),"Mechanism state can restore with world/inventory state"); await settle()
	check(not wheel.visible and inventory.count(&"valve_wheel")==1 and target.can_interact(),"Restoring before installation removes the wheel and returns its item")
	await settle(3); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/wheel-socket-in-game.png")
	# Owned cards remain visible only in placements explicitly configured for tests.
	inventory.collection[card.card_id]=true; inventory.collection_changed.emit(card.card_id)
	check(not card.hide_when_owned and card.enabled and card._visual.visible,"Example explicitly displays cards already present in the persistent collection")
	var bag: Dictionary=inventory.model.snapshot(); var owned: int=inventory.collection.size()
	check(card.interact(game.player),"Example's already-owned card can be tested again")
	check(inventory.collection.size()==owned and inventory.model.snapshot()==bag and not card.enabled,"Repeat collection grants no duplicate, no gameplay reward, and hides the card for this run")
	inventory.collection[spawned.card_id]=true; inventory.collection_changed.emit(spawned.card_id)
	check(spawned.hide_when_owned and not spawned.enabled and not spawned._visual.visible,"Normal card placements still hide already-owned cards")
	check(FileAccess.get_sha256(inventory.collection_file)==profile_hash,"Visibility validation never changes the user's persistent collection")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout
	current_scene=null; game.queue_free(); await settle()
	var result := {"ok":errors.is_empty(),"errors":errors}
	FileAccess.open("res://docs/world-pickup-visibility.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WORLD_PICKUP_VISIBILITY_OK " if errors.is_empty() else "WORLD_PICKUP_VISIBILITY_FAILED ",JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
