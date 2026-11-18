extends SceneTree
const Style=preload("res://scripts/ui/cursor_style.gd")
var game: Node3D
var failures: Array[String]=[]
var checks := 0
var simulated_mouse: Variant=null
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func settle(frames := 5) -> void:
	for frame in frames:
		await process_frame
		# Keep synthetic input stable while Windows can also send real pointer events.
		if simulated_mouse!=null and is_instance_valid(game):move(simulated_mouse)
func move(at: Vector2) -> void:
	simulated_mouse=at
	var event := InputEventMouseMotion.new();event.position=at;event.global_position=at;root.push_input(event,true)
	game.game_cursor._inside=true;game.game_cursor._process(0)
func capture(name: String) -> Image:
	await settle();await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image();image.save_png("res://docs/cursors-"+name+".png");return image
func preview_pack() -> void:
	var style: Resource=load("res://assets/ui/cursors/default_cursors.tres")
	var viewport := SubViewport.new();viewport.size=Vector2i(320,64);viewport.disable_3d=true;viewport.gui_disable_input=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.world_2d=World2D.new();root.add_child(viewport)
	var row := Control.new();row.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;viewport.add_child(row)
	row.draw.connect(func():
		row.draw_rect(Rect2(0,0,320,64),Color(.04,.045,.05))
		for kind in range(Style.Kind.HIT+1):
			row.draw_rect(Rect2(5+kind*44,4,42,54),Color(.09,.095,.1))
			var center := Vector2(26+kind*44,23)
			style.draw(row,kind,center+style.hotspot(kind)-style.texture(kind).get_size()*.5))
	var names := ["FLECHE","ACTION","PRISE","TENIR","BLOQUE","VISEE","IMPACT"]
	for kind in names.size():
		var label := Label.new();label.text=names[kind];label.position=Vector2(5+kind*44,39);label.size=Vector2(42,16);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_override("font",load("res://assets/fonts/m5x7.ttf"));label.add_theme_font_size_override("font_size",12);label.add_theme_color_override("font_color",style.pointer_color);row.add_child(label)
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image();image.resize(960,192,Image.INTERPOLATE_NEAREST);image.save_png("res://docs/cursor-pack-preview.png");viewport.queue_free();await process_frame
func run() -> void:
	create_timer(45).timeout.connect(func():push_error("Cursor validation timeout");quit(2));root.size=Vector2i(320,240)
	var inventory: Node=root.get_node("InventoryState");inventory.persist_collection=false;root.get_node("WorldEvents").reset_run()
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.pickup_feedback.enabled=false;game.set_process(false);game.player.set_process(false);game.player.set_physics_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	await settle();var pointer: Node=game.game_cursor
	check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and not pointer.canvas.visible,"Gameplay keeps captured aiming input and no menu cursor")
	for kind in range(Style.Kind.HIT+1):
		var image: Texture2D=game.cursor_style.texture(kind)
		check(image.get_width()<=16 and image.get_height()<=16,"Cursor stays small at native resolution: "+str(kind))
	game.pause_game();await settle(12);move(Vector2(20,20));await settle()
	check(paused and pointer.canvas.visible and pointer.kind==Style.Kind.POINTER,"Pointer renders in the paused menu without unpausing the world")
	check(pointer.canvas.mouse_filter==Control.MOUSE_FILTER_IGNORE and pointer.canvas.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Cursor cannot intercept clicks and uses nearest filtering")
	await capture("pointer")
	move(game.hud.start_button.get_global_rect().get_center());await settle()
	check(pointer.kind==Style.Kind.POINT,"A usable pause button changes the pointer to the pointing hand");await capture("menu-hand")
	game.start_game();await settle();check(not pointer.canvas.visible and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Resuming restores captured gameplay without a duplicate pointer")
	inventory.give(inventory.resolve_item(&"valve_wheel"),1,{},false);check(game.inventory_menu.open(),"Inventory opens with the new cursor")
	await settle(12)
	var filled: Control
	for slot: Control in game.inventory_menu._slots:
		if slot.visible and slot.section==&"items" and not slot.entry().is_empty():filled=slot;break
	move(filled.get_global_rect().get_center());await settle()
	check(pointer.kind==Style.Kind.OPEN_HAND,"A draggable inventory item shows the open hand")
	filled.force_drag({"inventory":inventory.get_instance_id(),"uid":filled.entry().uid},null)
	var destination: Control=game.inventory_menu._slots[1];move(destination.get_global_rect().get_center());await settle()
	check(root.gui_is_dragging() and pointer.kind==Style.Kind.GRAB,"A valid inventory drag shows the closed hand");await capture("drag")
	move(Vector2(5,5));await settle();check(pointer.kind==Style.Kind.BLOCKED,"A drop outside inventory slots shows the muted forbidden cursor")
	root.gui_cancel_drag();game.inventory_menu.close();await settle()
	var station: Node3D=load("res://scenes/interactions/interphone_example.tscn").instantiate();station.interaction_id=&"test.cursors.phone";station.position=Vector3(1000,0,1000);game.level.add_child(station);await settle()
	var manager: Node=game.item_placement;check(station.interact(game.player),"Interphone inspection still opens")
	manager.set_process(false);manager.set_physics_process(false);var part: Node3D=station.get_node("Parties/Appeler")
	move(Vector2(8,8));manager._physics_process(0);await settle()
	check(not pointer.canvas.visible and manager.inspection.canvas.visible and not manager.inspection.cursor.hovering,"Inspection shows one themed pointer without a system duplicate")
	await physics_frame;await process_frame;move(manager.camera.unproject_position(part.selection_area().global_position));manager._physics_process(0);await settle()
	check(manager.hovered==part and manager.inspection.cursor.hovering and manager.inspection.cursor.style==game.cursor_style,"A real inspection hotspot switches to the same themed pointing hand");await capture("inspection-hand")
	manager.cancel();station.queue_free();await settle()
	game.player.aiming=false;var idle := await capture("idle")
	game.player.aiming=true;game.hud.reticle.queue_redraw();var aiming := await capture("aim")
	var changed := 0
	for y in range(112,128):
		for x in range(152,168):
			if idle.get_pixel(x,y)!=aiming.get_pixel(x,y):changed+=1
	check(changed>30 and not pointer.canvas.visible,"Weapon aim draws the pack's centered reticle while the mouse remains captured")
	game.hud.hit_time=.1;game.hud.set_process(false);game.hud.reticle.queue_redraw();var hit := await capture("hit")
	check(hit.get_region(Rect2i(152,112,16,16)).get_data()!=aiming.get_region(Rect2i(152,112,16,16)).get_data(),"An impact uses the matching hit icon and retains its short confirmation timing")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await preview_pack()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/game-cursors-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("GAME_CURSORS_OK " if failures.is_empty() else "GAME_CURSORS_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
