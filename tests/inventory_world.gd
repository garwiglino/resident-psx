extends SceneTree
var Action: Script
var Condition: Script
var errors: Array[String]=[]
var inventory: Node
var world: Node
var game: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func settle(frames := 8) -> void:
	for frame in frames: await process_frame
func entry(id: StringName) -> Dictionary:
	for section in inventory.model.sections:
		for value: Dictionary in inventory.model.sections[section]:
			if not value.is_empty() and value.item.id==id: return value
	return {}
func launch(path: String) -> void:
	if is_instance_valid(game):
		current_scene=null; game.queue_free(); await settle()
	var map: Node3D=load(path).instantiate(); root.add_child(map); current_scene=map
	await settle(20); game=current_scene
	game.pickup_feedback.enabled=false
	game.player.set_physics_process(false); game.player.enabled=false
	game.psx_renderer.set_process(false)
func command(kind: int,id: StringName=&"") -> Resource:
	var action: Resource=Action.new(); action.kind=kind; action.id=id; return action
func condition(kind: int,id: StringName) -> bool:
	var c: Resource=Condition.new(); c.kind=kind; c.id=id; return c.matches()
func run() -> void:
	inventory=root.get_node("InventoryState"); world=root.get_node("WorldEvents")
	Action=load("res://scripts/world_events/world_action.gd"); Condition=load("res://scripts/world_events/world_condition.gd")
	inventory.persist_collection=false; inventory.collection.clear()
	await launch("res://scenes/examples/inventory_demo.tscn")
	check(game.has_method("play_cinematic") and game.inventory_menu!=null,"F6 demo automatically receives the inventory and shared game systems")
	var original_ammo: int=game.player.reserve
	# World actions grant/remove actual bag entries, and conditions observe them.
	var grant := command(Action.Kind.GIVE_ITEM); grant.inventory_item=inventory.resolve_item(&"key_archives")
	var badge := command(Action.Kind.GIVE_ITEM); badge.inventory_item=inventory.resolve_item(&"access_maintenance")
	check(world.execute([grant,badge],game.level),"Inventory actions validate in normal world action chains")
	await settle()
	check(condition(Condition.Kind.HAS_ITEM,&"key_archives") and inventory.count(&"access_maintenance")==1,"Inventory conditions see granted keys and access cards")
	var door: Node=load("res://scenes/world_events/door.tscn").instantiate()
	door.door_id=&"test.inventory.door"; door.required_item_id=&"different_key"; door.duration=0; game.level.add_child(door)
	check(not door.interact(game.player) and door.locked,"Another key or badge cannot open a door with a different required ID")
	door.required_item_id=&"key_archives"
	check(door.interact(game.player) and door.is_open and not door.locked and inventory.count(&"key_archives")==1,"Matching key unlocks the door without silently consuming it")
	var badge_door: Node=load("res://scenes/world_events/door.tscn").instantiate()
	badge_door.door_id=&"test.inventory.badge"; badge_door.required_item_id=&"access_maintenance"; badge_door.consume_key_on_unlock=true; badge_door.duration=0; game.level.add_child(badge_door)
	check(badge_door.interact(game.player) and inventory.count(&"access_maintenance")==0,"Authored consume-on-unlock works independently for an access card")
	check(not inventory.drop(entry(&"key_archives").uid,1),"Protected keys cannot be discarded")
	# An authored pickup returns correctly when restoring an earlier world state.
	var pickup: Node=game.level.get_node("Objet_maintenance_note")
	var before_pickup: Dictionary=world.snapshot()
	check(pickup.interact(game.player) and not pickup.enabled,"Authored document is collected once")
	check(world.restore(before_pickup),"Earlier world/inventory state restores")
	await settle()
	check(pickup.enabled and pickup._visual.visible and inventory.count(&"maintenance_note")==0,"Restore respawns the original pickup rather than losing it")
	check(pickup.interact(game.player),"Restored pickup is usable again")
	check(inventory.use(entry(&"maintenance_note").uid).has("read") and condition(Condition.Kind.DOCUMENT_READ,&"maintenance_note"),"Reading a document updates document conditions")
	# A dropped stack is reconstructed, including after it has been recovered.
	var wall := StaticBody3D.new(); wall.collision_layer=1; wall.collision_mask=0
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size=Vector3(2,2,.1); collision.shape=shape; wall.add_child(collision); game.level.add_child(wall)
	wall.global_transform=Transform3D(game.player.global_basis,game.player.global_position-game.player.global_basis.z*.35+Vector3.UP*.5)
	for frame in 3: await physics_frame
	check(inventory.drop(entry(&"ammo_magnum").uid,3),"Ammo drops through the inventory service")
	var drop_snapshot: Dictionary=world.snapshot(); var drop: Node=game.level.get_node("inventory_drop_1")
	check((drop.global_position-game.player.global_position).dot(-game.player.global_basis.z)<.3,"Dropping near a wall keeps the item on the player's side")
	wall.queue_free(); await settle(2)
	check(drop.interact(game.player) and game.player.reserve==original_ammo,"Recovering ammo restores the exact reserve")
	check(world.restore(drop_snapshot),"Snapshot with a dropped stack restores")
	await settle(); drop=game.level.get_node_or_null("inventory_drop_1")
	check(drop!=null and drop.enabled and drop.quantity==3 and game.player.reserve==original_ammo-3,"Restored drop is visible exactly once and stays outside the bag")
	# Invalid snapshots cannot clear live world/inventory state before rejection.
	var unchanged: Dictionary=world.snapshot(); var broken: Dictionary=unchanged.duplicate(true)
	broken.inventory.drops[0].packet.quantity=100000
	check(not world.restore(broken) and world.snapshot()==unchanged,"Invalid inventory snapshot is rejected before altering the current world")
	broken=unchanged.duplicate(true); broken.inventory.model.sections.items[0].state={"object":game}
	check(not world.restore(broken) and world.snapshot()==unchanged,"Live object references cannot enter inventory save state")
	# Real scene teardown/recreation keeps slots, rounds, and per-level drops.
	game.player.ammo=4
	var outfit: CharacterClothing=game.player.get_node("Tenue")
	outfit.unequip()
	outfit.set_texture_variant(ClothingItem.Slot.SHOES,&"Sorami")
	var wardrobe := outfit.wardrobe_state()
	var slots: Dictionary=inventory.model.snapshot(); var backend: RefCounted=inventory.backend
	current_scene=null; game.queue_free(); await settle(); game=null
	var other := Node3D.new(); other.name="OtherLevel"; other.scene_file_path="res://tests/other_level.tscn"
	var settings: Node=load("res://scripts/levels/psx_level_settings.gd").new(); settings.name="ReglagesNiveau"; other.add_child(settings)
	root.add_child(other); current_scene=other; await settle(16); game=current_scene
	check(inventory.backend==backend and inventory.model.snapshot()==slots and game.player.ammo==4,"Changing levels preserves the same inventory, slot order and loaded rounds")
	var restored_wardrobe: Dictionary=game.player.get_node("Tenue").wardrobe_state()
	check(restored_wardrobe==wardrobe,"The selected outfit and finish survive a level change. Expected %s, received %s" % [wardrobe,restored_wardrobe])
	check(not game.level.has_node("inventory_drop_1"),"A drop does not appear in a different level")
	await launch("res://scenes/examples/inventory_demo.tscn")
	check(game.level.has_node("inventory_drop_1") and game.player.ammo==4,"Returning to the source level restores its dropped object")
	check(game.level.get_node("inventory_drop_1").interact(game.player) and game.player.reserve==original_ammo,"Recovered return-trip drop still has its original quantity")
	# Collection persistence uses a dedicated temporary profile, never the user's.
	var profile: String="user://inventory_validation_%d.json" % Time.get_ticks_usec()
	var original_path: String=inventory.collection_file
	inventory.collection_file=profile; inventory.persist_collection=true
	var bag: Dictionary=inventory.model.snapshot()
	var a: StringName=inventory.catalogue.cards[0].id; var b: StringName=inventory.catalogue.cards[1].id
	check(inventory.collect_card(a) and inventory.collect_card(b),"Collection profile can be saved repeatedly, replacing its previous file")
	var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(profile))
	check(saved is Dictionary and saved.cards.size()==2,"Second atomic profile write retains both collected cards")
	inventory.collection.clear(); inventory._load_collection()
	check(inventory.owns_card(a) and inventory.owns_card(b) and inventory.model.snapshot()==bag,"Collection reload preserves art ownership without changing gameplay inventory")
	check(condition(Condition.Kind.CARD_COLLECTED,a),"Collection condition observes the collected card")
	inventory.persist_collection=false; inventory.collection_file=original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile))
	var remove := command(Action.Kind.REMOVE_ITEM,&"key_archives"); world.execute([remove],game.level); await settle()
	check(inventory.count(&"key_archives")==0 and not condition(Condition.Kind.HAS_ITEM,&"key_archives"),"Remove-item action and possession condition agree")
	current_scene=null; game.queue_free(); await settle(); game=null; world.reset_run(); await settle()
	check(inventory.owns_card(a) and inventory.model.count(&"desert_eagle")==0,"New run clears gameplay inventory and preserves the goodie collection")
	var result := {"ok":errors.is_empty(),"errors":errors,"collection_cards":inventory.catalogue.cards.size()}
	FileAccess.open("res://docs/inventory-world-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("INVENTORY_WORLD_OK " if errors.is_empty() else "INVENTORY_WORLD_FAILED ",JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
