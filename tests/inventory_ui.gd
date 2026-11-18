extends SceneTree
var errors: Array[String]=[]
var game: Node
var inventory: Node
var menu: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func settle(count := 5) -> void:
	for frame in count: await process_frame
func screenshot(name: String) -> void:
	await settle(2); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/"+name+".png")
func entry(id: StringName) -> Dictionary:
	for section in inventory.model.sections:
		for value: Dictionary in inventory.model.sections[section]:
			if not value.is_empty() and value.item.id==id: return value
	return {}
func action(name: String) -> void:
	var event := InputEventAction.new(); event.action=name; event.pressed=true; game._input(event)
func mouse(at: Vector2,pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.position=at; event.global_position=at; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	root.push_input(event)
func run() -> void:
	root.size=Vector2i(320,240); inventory=root.get_node("InventoryState"); inventory.persist_collection=false; inventory.collection.clear()
	game=load("res://scenes/main.tscn").instantiate(); root.add_child(game); current_scene=game
	game.pickup_feedback.enabled=false
	for enemy in game.enemies: enemy.set_physics_process(false); enemy.active=false
	menu=game.inventory_menu
	check(inventory.backend==game.player.weapon_inventory and inventory.count(&"desert_eagle")==1,"Inventory shares actual weapon/ammunition state")
	check(inventory.count(&"ammo_magnum")==game.player.reserve and inventory.count(&"medkit")==game.starting_medkits,"Starting supplies appear in slots")
	for id: StringName in [&"key_archives",&"access_maintenance",&"valve_wheel",&"lever_handle",&"maintenance_note"]: check(inventory.give(inventory.resolve_item(id)),"Generic item definitions are usable")
	check(inventory.give(inventory.resolve_item(&"metal_parts"),12),"Materials can stack")
	inventory.give(inventory.resolve_item(&"medkit"),4); inventory.add_ammo(&"magnum",20)
	for index in 3: inventory.collect_card(inventory.catalogue.cards[index].id)
	action("inventory"); await settle()
	check(menu.opened and paused and game.player.controls_blocked,"I opens the inventory, locks controls and pauses the world")
	check(menu.slot_font==game.dialogue.style.font and menu.modal.get_theme_stylebox("panel")==game.hud.menu.get_theme_stylebox("panel"),"Inventory combines the dialogue body font with the actual pause panel")
	for tab: Button in menu._tabs:
		check(tab.get_theme_font("font")==game.hud.canvas.theme.get_font("font","MenuTab") and tab.get_theme_font_size("font_size")==16,"All tab headings use the shared PSX title font at 16 px")
	check(menu.modal.size==Vector2(320,240) and menu.modal.position==Vector2.ZERO,"Inventory fills the native PSX viewport")
	check(menu._sections[&"items"].visible and not menu._sections[&"equipment"].visible,"Only one inventory category is shown")
	var arrow: Control=menu._inventory.get_child(1); var arrow_at := arrow.get_global_rect().get_center()
	mouse(arrow_at,true); mouse(arrow_at,false); await settle()
	check(not menu._sections[&"items"].visible and menu._sections[&"equipment"].visible,"Arrows cycle to weapons and ammunition in the same modal")
	await screenshot("inventory-weapons"); mouse(arrow_at,true); mouse(arrow_at,false); await settle()
	menu.select_slot(&"items",0); await screenshot("inventory-menu")
	# Send real viewport mouse input through Godot's drag/drop callbacks.
	var source: Control=menu._slots[0]; var target: Control=menu._slots[3]
	var uid: String=inventory.model.slot(&"items",0).uid
	var from := source.get_global_rect().get_center(); var to := target.get_global_rect().get_center()
	mouse(from,true)
	var motion := InputEventMouseMotion.new(); motion.position=from+Vector2(20,4); motion.global_position=motion.position; motion.relative=Vector2(20,4); motion.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(motion)
	motion=InputEventMouseMotion.new(); motion.position=to; motion.global_position=to; motion.relative=to-from; motion.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(motion)
	mouse(to,false); await settle()
	check(inventory.model.slot(&"items",3).get("uid","")==uid,"Real drag/drop swaps occupied inventory slots")
	var medkit := entry(&"medkit"); game.player.health=40; menu._use(medkit.uid); await settle()
	check(game.player.health==90 and inventory.count(&"medkit")==4,"Consume heals and removes exactly one item")
	var document := entry(&"maintenance_note"); menu._use(document.uid); await settle()
	check(menu._reader.visible and root.get_node("WorldEvents").fact(&"document.maintenance_note.read",false),"Read opens the document and records a world fact")
	await screenshot("inventory-document"); menu.back()
	var ammo := entry(&"ammo_magnum"); var total: int=inventory.count(&"ammo_magnum")
	menu._show_category(1)
	menu.show_context(ammo.uid,Vector2(290,175)); await settle(); check(menu._context.get_global_rect().end.x<=320,"Context menu stays inside the native screen")
	await screenshot("inventory-context"); menu._ask_drop(ammo.uid); await settle()
	check(menu._quantity.visible and menu._slider.max_value==total,"Stack discard opens a quantity slider")
	menu._slider.value=7; await screenshot("inventory-quantity")
	menu._ask_all(); await settle(); check(menu._warning.visible and inventory.count(&"ammo_magnum")==total,"Discard-all requires explicit confirmation")
	await screenshot("inventory-discard-warning"); menu.back(); menu._perform_drop(2); await settle()
	check(inventory.count(&"ammo_magnum")==total-2 and game.player.reserve==total-2,"Discarded ammunition stays synchronized with reload reserves")
	var drop: Node=game.level.get_node("inventory_drop_1"); menu.close(); check(drop.interact(game.player),"Dropped objects can be picked up again")
	check(inventory.count(&"ammo_magnum")==total,"Picking up a dropped stack restores its exact amount")
	menu.open(); await settle(2)
	var tab_at: Vector2=menu._tabs[1].get_global_rect().get_center(); mouse(tab_at,true); mouse(tab_at,false); await settle(2)
	var hover := InputEventMouseMotion.new(); hover.position=menu._cards[1].get_global_rect().get_center(); hover.global_position=hover.position; root.push_input(hover)
	await screenshot("inventory-collection")
	check(menu._card_image.texture==inventory.catalogue.cards[1].image and menu._card_name.text==inventory.catalogue.cards[1].display_name,"Hover preview uses the selected collected card and its name")
	check(menu._card_image.size.y>=96 and menu._card_image.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and menu._card_image.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"The larger collection preview preserves nearest sampling and aspect ratio")
	check(menu._collection.visible and not menu._inventory.visible and menu.modal.size==Vector2(320,240),"Collection switches within the same fullscreen layout")
	check(menu._card_text.text.contains("Unite"),"Collection descriptions are readable without accents")
	menu.close()
	var target_node: Node3D=load("res://scenes/inventory/item_target.tscn").instantiate(); target_node.interaction_id=&"test.inventory.wheel"
	target_node.use_selection_view=false # Legacy direct-use API remains available.
	target_node.interaction_offset=Vector3(0,1.1,0); game.level.add_child(target_node); target_node.global_position=game.player.global_position+Vector3(0,0,-.8)
	var wheel := entry(&"valve_wheel"); var used: Dictionary=inventory.use(wheel.uid)
	check(used.ok and inventory.count(&"valve_wheel")==0 and root.get_node("WorldEvents").interaction_used(&"test.inventory.wheel"),"Mechanism consumes the matching part through world interactions")
	var card: Node3D=load("res://scenes/inventory/card_pickup.tscn").instantiate(); card.card_id=inventory.catalogue.cards[3].id; game.level.add_child(card)
	check(is_equal_approx(card._visual.get_child(0).mesh.size.y,.3),"World cards are exactly 30 cm high")
	check(card._visual.get_child(0).mesh.material.albedo_texture==inventory.catalogue.card_mystery and card._visual.get_child(1).mesh.material.albedo_texture==inventory.catalogue.card_back,"World card uses mystery front and supplied common back")
	var rotation: float=card._visual.rotation.y; card._process(.5); check(card._visual.rotation.y!=rotation,"World card rotates and bobs smoothly")
	var bag_before: Dictionary=inventory.model.snapshot(); check(card.interact(game.player),"World card can be collected")
	check(inventory.owns_card(card.card_id) and inventory.model.snapshot()==bag_before,"Collectible cards use the collection without taking gameplay slots")
	# A weapon can leave the last slot without granting or losing its loaded ammo.
	var gun := entry(&"desert_eagle"); game.player.ammo=6
	game.player.weapon_inventory.action=0; game.player.weapon_inventory.action_left=0
	check(game.player.reload_weapon(),"Reload can be started before discarding its weapon")
	check(inventory.drop(gun.uid,1) and game.player.weapon_definition()==null,"Discarding the last weapon supports an unarmed player")
	check(game.player.motion.aim_pose.reload_time<0 and game.player.motion.aim_pose.fire_time<0,"Discarding a weapon also clears its upper body action overlays")
	var gun_drop: Node=game.level.get_node("inventory_drop_2"); check(gun_drop.interact(game.player),"Dropped weapon can be recovered")
	check(game.player.ammo==6 and game.player.reserve==total,"Recovered weapon retains loaded rounds without duplicating reserve ammo")
	var saved: Dictionary=root.get_node("WorldEvents").snapshot(); var position: Dictionary=inventory.model.snapshot()
	inventory.remove_item(&"key_archives"); check(root.get_node("WorldEvents").restore(saved),"World state restores the inventory snapshot")
	check(inventory.model.snapshot()==position,"World restoration preserves slot order, quantities, keys and weapon state")
	# Larger authored capacities must scroll without cropping the fourth column.
	inventory.catalogue=inventory.catalogue.duplicate(); inventory.catalogue.item_capacity=32
	for extra in 16: inventory.model.sections[&"items"].append({})
	var expanded: CanvasLayer=load("res://scenes/inventory/inventory_menu.tscn").instantiate(); expanded.game=game; game.add_child(expanded); expanded.open(); await settle()
	var fourth: Control=expanded._slots[3]; var scroll: ScrollContainer=fourth.get_parent().get_parent()
	check(scroll.get_v_scroll_bar().visible and fourth.get_global_rect().end.x<=scroll.get_global_rect().end.x-scroll.get_v_scroll_bar().size.x,"Expanded inventories keep every slot column visible next to the scrollbar")
	expanded.close(); expanded.queue_free()
	game.inventory_menu.close(); current_scene=null; game.queue_free(); await settle(8); paused=false
	var result := {"ok":errors.is_empty(),"errors":errors,"cards":inventory.collection.size()}
	FileAccess.open("res://docs/inventory-ui-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("INVENTORY_UI_OK " if errors.is_empty() else "INVENTORY_UI_FAILED ",JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
