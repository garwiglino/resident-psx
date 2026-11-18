extends SceneTree
var errors: Array[String]=[]
var history: Array[Dictionary]=[]
var game: Node
var feedback: Node
var inventory: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: errors.append(message); push_error(message)
func settle(frames := 5) -> void:
	for frame in frames: await process_frame
func wait_audio() -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not feedback._sound_jobs.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(feedback._sound_jobs.is_empty(),"Non-looping pickup sound sequence finishes")
func sound(kind: StringName,player: AudioStreamPlayer) -> void:
	var source: AudioStream=load("res://scripts/audio/psx_audio_routing.gd").source_of(player.stream)
	history.append({"kind":String(kind),"time":Time.get_ticks_msec(),"path":source.resource_path,"native":player.stream.is_class("AudioStreamPSX"),"bus":player.bus,"voice":player.get_instance_id()})
func screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(path)
func run() -> void:
	root.size=Vector2i(320,240); inventory=root.get_node("InventoryState"); inventory.persist_collection=false; inventory.collection.clear()
	var profile_hash := FileAccess.get_sha256(inventory.collection_file)
	var level: Node3D=load("res://scenes/examples/inventory_demo.tscn").instantiate(); root.add_child(level); current_scene=level; await settle(20); game=current_scene
	game.player.set_physics_process(false); feedback=game.pickup_feedback; feedback.sound_started.connect(sound)
	check(history.is_empty() and not feedback.is_active(),"Starting loadout and saved collection do not trigger pickup effects")
	check(game.inventory_menu.slot_font==game.dialogue.style.font,"Menu uses the dialogue body font")
	for tab: Button in game.inventory_menu._tabs:
		check(tab.get_theme_font_size("font_size")==16 and tab.get_theme_font("font")!=game.inventory_menu.slot_font,"The tab headings use the distinct 16-pixel heading font")
	var ammo: Node=game.level.get_node("Objet_ammo_magnum")
	check(ammo.interact(game.player),"Ordinary world pickup succeeds")
	check(history.size()==1 and history[0].kind=="item_pickup" and not feedback.is_active(),"Every normal pickup plays the shared UI sound without pausing")
	if not history.is_empty():
		var bus := AudioServer.get_bus_index(history[0].bus)
		var dry: bool=history[0].bus==&"PSX Dry" or (bus>=0 and AudioServer.get_bus_send(bus)==&"PSX Dry")
		check(history[0].native and dry and history[0].path.ends_with("/ui/item_pickup.wav"),"Pickup uses the exact provided file through native PSX audio with a dry UI send")
	await wait_audio(); history.clear()
	var wheel: Node=game.level.get_node("Objet_valve_wheel")
	var camera: Camera3D=game.psx_renderer.camera; var lights: int=game.psx_renderer.world_lights.size()
	Input.action_press("interact")
	check(wheel.interact(game.player),"Essential world pickup succeeds")
	await settle(8)
	check(feedback.opened and paused and game.player.controls_blocked,"Essential discovery pauses the world and owns the controls")
	check(feedback.current_item.id==&"valve_wheel" and feedback.item_name.text==load("res://scripts/dialogue/dialogue_text.gd").plain(wheel.item.display_name) and feedback.canvas.visible,"Discovery displays the picked object's exact name")
	check(feedback.modal.size==Vector2(144,140) and feedback.modal.position==Vector2(88,50),"Discovery is centered with room for a two-line item name")
	check(feedback.modal.get_global_rect().encloses(feedback.confirm_button.get_global_rect()),"OK button stays inside the compact discovery frame")
	check(feedback.preview_root.rotation_degrees.is_equal_approx(feedback.preview_tilt_degrees) and feedback.rotation_speed==40,"Preview keeps a subtle fixed tilt while spinning faster")
	check(feedback.pickup_volume_db==-12 and feedback.discovery_volume_db==-10,"Pickup and discovery sound levels are raised by six decibels")
	check(feedback.confirm_button.disabled,"Held pickup key cannot dismiss the modal")
	feedback.confirm(); check(feedback.opened,"Held-key guard also protects keyboard confirmation")
	Input.action_release("interact"); await settle(2)
	var elapsed: float=game.elapsed; var angle: float=feedback.rotator.rotation.y
	await create_timer(.6,true).timeout
	check(game.elapsed==elapsed and absf(feedback.rotator.rotation.y-angle)>.05,"The 3D object rotates slowly while gameplay stays frozen")
	check(feedback.preview_renderer.native_geometry.get_statistics().batches==1,"3D discovery uses the same native PSX vertex-light renderer")
	var gray: Image=feedback.backdrop.texture.get_image(); var is_gray := true
	for y in range(0,gray.get_height(),11):
		for x in range(0,gray.get_width(),11):
			var c := gray.get_pixel(x,y); is_gray=is_gray and is_equal_approx(c.r,c.g) and is_equal_approx(c.g,c.b)
	check(is_gray,"Only the frozen backdrop is converted to gray")
	check(history.size()>=2 and history[0].kind=="item_pickup" and history[1].kind=="essential_item_found","Essential fanfare follows the common pickup sound")
	if history.size()>=2: check(history[1].time-history[0].time>=430 and history[1].time-history[0].time<700,"Essential fanfare begins immediately after the 471 ms pickup clip")
	await screenshot("res://docs/essential-item-found.png")
	var button_at: Vector2=feedback.confirm_button.get_global_rect().get_center()
	var press := InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.position=button_at; press.global_position=button_at; press.pressed=true; root.push_input(press); await process_frame
	var release := press.duplicate(); release.pressed=false; root.push_input(release); await settle(2)
	check(not feedback.opened and not paused and not game.player.controls_blocked and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Clicking OK restores gameplay, controls and mouse capture")
	check(game.psx_renderer.camera==camera and game.psx_renderer.world_lights.size()==lights,"Preview leaves the gameplay camera and level lights unchanged")
	await wait_audio(); history.clear()
	check(inventory.collect_card(inventory.catalogue.cards[5].id),"Fresh secret card is collected")
	await wait_audio()
	check(history.size()==2 and history[0].kind=="item_pickup" and history[1].kind=="secret_card_found" and history[1].path.ends_with("/ui/secret_card_found.wav"),"Secret card plays common pickup then its exact secret-card fanfare")
	check(not feedback.is_active() and not paused,"Collection cards keep their nonblocking exploration behavior")
	history.clear()
	var rapid := Time.get_ticks_msec()
	inventory.collect_card(inventory.catalogue.cards[6].id); inventory.collect_card(inventory.catalogue.cards[7].id)
	check(history.size()==2 and history[0].kind=="item_pickup" and history[1].kind=="item_pickup" and history[1].time-rapid<100,"Rapid pickups each play immediately instead of waiting behind previous fanfares")
	await wait_audio()
	check(history.filter(func(row: Dictionary):return row.kind=="secret_card_found").size()==2,"Each rapid pickup retains its own following discovery sound")
	history.clear(); var owned_count: int=inventory.collection.size()
	inventory.collect_card(inventory.catalogue.cards[6].id); await wait_audio()
	check(inventory.collection.size()==owned_count and history.size()==2 and history[1].kind=="secret_card_found","Repeatable demo cards still play their pickup fanfare without adding duplicates")
	# A grant from the world system waits for OK before the next authored action.
	var Action: Script=load("res://scripts/world_events/world_action.gd")
	var grant: Resource=Action.new(); grant.kind=Action.Kind.GIVE_ITEM; grant.inventory_item=inventory.resolve_item(&"lever_handle")
	var after: Resource=Action.new(); after.kind=Action.Kind.SET_FLAG; after.id=&"test.after_discovery"
	root.get_node("WorldEvents").execute([grant,after],game.level); await settle(8)
	check(feedback.opened and feedback.current_item.id==&"lever_handle" and not root.get_node("WorldEvents").flag(after.id),"World action chain waits for a lever's discovery modal")
	await create_timer(.25,true).timeout; feedback.confirm(); await settle()
	check(root.get_node("WorldEvents").flag(after.id) and not paused,"World actions resume after OK")
	await wait_audio()
	# Multiple discoveries remain one paused modal until the last confirmation.
	inventory.give(inventory.resolve_item(&"key_archives")); inventory.give(inventory.resolve_item(&"access_maintenance")); await settle(8)
	check(feedback.opened and feedback._queue.size()==1,"Several essential grants are queued without overlapping windows")
	await create_timer(.25,true).timeout; feedback.confirm()
	check(feedback.opened and paused and feedback.current_item.id==&"access_maintenance","Next discovery keeps the world paused in the same modal")
	await create_timer(.25,true).timeout; feedback.confirm(); check(not paused and not feedback.opened,"Last OK releases the discovery modal")
	feedback.cancel()
	# Dialogue ownership survives a discovery interruption.
	var line: Resource=load("res://scripts/dialogue/dialogue_line.gd").new(); line.text="Conversation en cours."
	var sequence: Resource=load("res://scripts/dialogue/dialogue_sequence.gd").new(); sequence.lines.append(line)
	check(game.play_dialogue(sequence,false),"Conversation starts before a scripted reward")
	inventory.give(inventory.resolve_item(&"fuse_16a")); await settle(8)
	check(feedback.opened and game.dialogue.suspended and game.dialogue.is_active(),"Discovery safely suspends an existing conversation")
	await create_timer(.25,true).timeout; feedback.confirm(); await settle()
	check(not paused and not game.dialogue.suspended and game.dialogue.is_active() and game.player.controls_blocked,"OK resumes the previous conversation and retains its control lock")
	game.dialogue.cancel(); feedback.cancel(); await settle()
	var Item: Script=load("res://scripts/inventory/item_definition.gd")
	var filler: Resource=Item.new(); filler.id=&"test_filler"; filler.kind=Item.Kind.MATERIAL
	inventory.model.add(filler,inventory.model.capacity_for(filler)); history.clear()
	var refused: Resource=Item.new(); refused.id=&"test_full_key"; refused.kind=Item.Kind.KEY
	check(not inventory.give(refused) and history.is_empty() and not feedback.is_active(),"A failed full-inventory pickup never plays a sound or opens a discovery modal")
	check(FileAccess.get_sha256(inventory.collection_file)==profile_hash,"Feedback testing preserves the user's collection file")
	current_scene=null; game.queue_free(); await settle(8)
	var result := {"ok":errors.is_empty(),"errors":errors}
	FileAccess.open("res://docs/pickup-feedback-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PICKUP_FEEDBACK_OK " if errors.is_empty() else "PICKUP_FEEDBACK_FAILED ",JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
