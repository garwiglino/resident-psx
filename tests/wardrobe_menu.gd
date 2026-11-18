extends SceneTree

const Item=preload("res://scripts/clothing/clothing_item.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func settle(frames: int) -> void:
	for frame in frames:await process_frame

func click(button: Button) -> void:
	for down in [true,false]:
		mouse_button(button.get_global_rect().get_center(),down)

func mouse_button(at: Vector2,down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=at
	event.global_position=at
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=down
	root.push_input(event)

func fits_button(button: Button) -> bool:
	var frame := button.get_theme_stylebox("normal")
	var font := button.get_theme_font("font")
	var size := button.get_theme_font_size("font_size")
	var available := button.size-frame.get_minimum_size()
	return font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=available.x and font.get_height(size)<=available.y

func run() -> void:
	root.size=Vector2i(320,240)
	var inventory := root.get_node("InventoryState")
	var world := root.get_node("WorldEvents")
	inventory.persist_collection=false
	world.reset_run()
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle(4)
	var menu=game.inventory_menu
	var clothing: CharacterClothing=game.player.get_node("Tenue")
	var start := clothing.wardrobe_state()
	check(menu.canvas.theme==game.hud.canvas.theme and game.pickup_feedback.canvas.theme==menu.canvas.theme and
		game.item_placement.menu.canvas.theme==menu.canvas.theme,"Menus share the same PSX theme")
	game.pause_game()
	await settle(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/psx-menu-pause.png")
	game.start_game()
	var world_entries: int=game.psx_renderer.entries.size()
	var world_atlas: Texture2D=game.psx_renderer.atlas_texture
	var world_lights: Array=game.psx_renderer.world_lights.duplicate()
	check(menu.open() and paused,"Wardrobe opens inside the normal paused inventory")
	await settle(3)
	click(menu._tabs[2])
	await settle(8)
	var page=menu._wardrobe
	var preview=page.preview
	check(page.visible and not menu._inventory.visible and not menu._collection.visible,"Hitomi is the third inventory tab")
	check(preview.renderer.native_geometry!=null and preview.renderer.triangle_count>0,"The portrait uses the native PSX renderer")
	check(game.psx_renderer.entries.size()==world_entries and game.psx_renderer.atlas_texture==world_atlas and
		game.psx_renderer.entries.all(func(entry: Dictionary):return entry.node.get_viewport()==root),
		"Opening the portrait neither registers its clothes in the world nor rebuilds the world atlas")
	check(preview.mixer.current_animation==&"cloth_idle" and is_equal_approx(preview.mixer.current_animation_length,4.0),"Portrait plays the exported four-second cloth_idle")
	check(preview.outfit.wardrobe_state()==start and preview.outfit!=clothing,"Preview and game outfit match on separate models")
	var time: float=preview.mixer.current_animation_position
	await create_timer(.18).timeout
	check(not is_equal_approx(preview.mixer.current_animation_position,time),"The idle plays while the world is paused")
	check(page._piece_label.text=="Sneakers" and not page._color_label.text.is_empty(),"The page shows the equipped piece and its finish")
	for index in range(menu._tabs.size()-1):
		check(menu._tabs[index].get_rect().end.x<=menu._tabs[index+1].get_rect().position.x,"Tab titles fit without overlap")
	var bar: Control=menu._tabs[2].get_parent()
	check(bar.get_rect().end.x<=menu.modal.size.x-8,"All tabs and the close button fit in the modal")
	for button in bar.get_children():check(fits_button(button),"Tab text fits with its theme padding")
	for button in page._categories:check(fits_button(button),"Category text fits with its theme padding")
	for index in range(page._categories.size()-1):
		check(page._categories[index].get_rect().end.y<=page._categories[index+1].get_rect().position.y,"Wardrobe categories fit without overlap")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/hitomi-wardrobe.png")

	var live_yaw: float=game.player.global_rotation.y
	var drag_from: Vector2=preview.get_global_rect().position+Vector2(6,65)
	var drag_delta := Vector2(90,0)
	mouse_button(drag_from,true)
	var motion := InputEventMouseMotion.new()
	motion.position=drag_from+drag_delta
	motion.global_position=motion.position
	motion.relative=drag_delta
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	mouse_button(motion.position,false)
	check(is_equal_approx(preview._model.rotation.y,PI) and not preview._dragging and
		is_equal_approx(game.player.global_rotation.y,live_yaw),"A real drag turns only the portrait through 180 degrees")
	await settle(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/hitomi-dos.png")

	var renderer: Node=game.psx_renderer
	# Sample the actual frozen world behind the opaque fullscreen menu.
	menu.canvas.hide()
	await settle(2)
	await RenderingServer.frame_post_draw
	var lookup: Texture2D=renderer.raster.get_shader_parameter("texture_page_lookup")
	var old_atlas: Texture2D=renderer.primitives[0].texture
	var decor := Rect2i(0,0,20,240)
	var before_frame := root.get_texture().get_image()
	var before := before_frame.get_region(decor)
	var old_color := clothing.texture_variant(Item.Slot.SHOES)
	var right := InputEventKey.new()
	right.keycode=KEY_RIGHT
	right.pressed=true
	root.push_input(right)
	check(clothing.texture_variant(Item.Slot.SHOES)!=old_color and preview.outfit.wardrobe_state()==clothing.wardrobe_state(),
		"Right color arrow applies the finish to the live character and preview")
	check(renderer.atlas_texture!=old_atlas and renderer.raster.get_shader_parameter("texture_page_lookup")==lookup,
		"The old world frame keeps its own page table until the new frame is ready")
	await settle(4)
	await RenderingServer.frame_post_draw
	check(renderer.primitives[0].texture==renderer.atlas_texture and renderer._drawn_atlas_revision==renderer.geometry_revision,
		"The paused frame presents its new geometry and atlas together")
	check(renderer.world_lights==world_lights,"The portrait light stays out of the level after a redraw")
	var after_frame := root.get_texture().get_image()
	var decor_matches := after_frame.get_region(decor).get_data()==before.get_data()
	if not decor_matches:
		before_frame.save_png("res://docs/hitomi-world-before.png")
		after_frame.save_png("res://docs/hitomi-world-after.png")
	check(decor_matches,"The paused scenery keeps identical pixels during the outfit change")
	menu.canvas.show()
	var recolored := clothing.wardrobe_state()
	var snapshot: Dictionary=world.snapshot()
	var dressed_vertices: int=renderer.vertex_count
	click(page._piece_buttons[1])
	check(not clothing.is_equipped(&"sneakers") and not preview.outfit.is_equipped(&"sneakers") and page._piece_label.text=="Aucun",
		"Cycling to Aucun removes the sneakers immediately from both models")
	await settle(3)
	check(renderer.vertex_count<dressed_vertices,"The paused world stops drawing the removed sneakers")
	check(world.restore(snapshot) and clothing.wardrobe_state()==recolored and preview.outfit.wardrobe_state()==recolored,
		"The existing world snapshot restores the outfit and finish")
	page._categories[2].pressed.emit()
	check(page._piece_label.text=="Aucun" and page._piece_buttons[0].disabled and page._color_buttons[1].disabled,
		"Empty categories disable both selectors")
	click(page._categories[4])
	if clothing.set_texture_variant(Item.Slot.OUTERWEAR,&"Sport violet turquoise"):
		await settle(2)
		var label: Label=page._color_label
		var font := label.get_theme_font("font")
		var line_height := font.get_height(label.get_theme_font_size("font_size"))
		check(label.text=="Sport violet turquoise" and label.get_line_count()*line_height<=label.size.y,
			"Long finish names fit in the color selector")
	clothing.restore_wardrobe(recolored)

	clothing.unequip(Item.Slot.OUTERWEAR)
	click(page._categories[3])
	click(page._piece_buttons[1])
	check(clothing.is_equipped(&"cop_outfit") and preview.outfit.is_equipped(&"cop_outfit") and page._piece_label.text=="Tenue de police",
		"The full uniform equips through the wardrobe in both viewports")
	check(not clothing.is_equipped(&"sneakers") and not clothing.is_equipped(&"large_jeans_01") and
		not preview.outfit.is_equipped(&"sneakers"),"The uniform's boots replace the selected shoes")
	preview._model.rotation.y=0
	await settle(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/cop-outfit-wardrobe.png")
	click(page._categories[0])
	check(page._piece_label.text=="Avec la tenue" and page._piece_buttons[1].disabled,"The wardrobe indicates the outfit's included footwear")
	click(page._categories[3])
	click(page._piece_buttons[1])
	check(clothing.is_equipped(&"sneakers") and clothing.is_equipped(&"large_jeans_01"),"Removing the uniform restores the selected shoes and pants")
	clothing.restore_wardrobe(recolored)

	menu._tabs[1].pressed.emit()
	var stopped_at: float=preview.mixer.current_animation_position
	await settle(6)
	check(menu._collection.visible and not page.visible and preview.buffer.render_target_update_mode==SubViewport.UPDATE_DISABLED and
		is_equal_approx(preview.mixer.current_animation_position,stopped_at),"Collection suspends the wardrobe render")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/psx-menu-collection.png")
	menu.close()
	check(not paused and not menu.opened and clothing.wardrobe_state()==recolored and game._control_owners.is_empty(),
		"Closing the menu resumes controls and retains the chosen outfit")
	check(menu.open(),"The inventory can reopen")
	menu._tabs[2].pressed.emit()
	check(preview.outfit.wardrobe_state()==recolored,"Reopening the page retains the outfit")
	menu.close()

	inventory.persist_collection=false
	for player in game.find_children("*","AudioStreamPlayer",true,false):player.stop()
	for player in game.find_children("*","AudioStreamPlayer3D",true,false):player.stop()
	await create_timer(.15).timeout
	game.queue_free()
	await settle(4)
	await create_timer(.15).timeout
	print("WARDROBE_MENU_OK" if failures.is_empty() else "WARDROBE_MENU_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
