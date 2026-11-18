extends Node
## Persistent run inventory; the existing weapon inventory remains the ammo engine.
signal changed
signal collection_changed(id: StringName)
signal notice(text: String)
signal item_acquired(item: Resource,quantity: int,discovery: bool)
signal card_acquired(card: Resource,fresh: bool)
const Model=preload("res://scripts/inventory/inventory_model.gd")
const Item=preload("res://scripts/inventory/item_definition.gd")
const Weapons=preload("res://scripts/weapon_inventory.gd")
var catalogue: Resource=preload("res://assets/inventory/catalogue.tres")
var model: RefCounted
var backend: RefCounted
var game: Node
var initialized := false
var collection: Dictionary={}
var collection_file := "user://ferro_eclipse_collection.json"
var persist_collection := true
var _registry: Dictionary={}
var _mutating := false
var _last_counts: Dictionary={}
var _preferred_weapon := ""
var _drops: Array[Dictionary]=[]
var _next_drop := 1
var _clothing: CharacterClothing
var _wardrobe: Dictionary={}
var _wardrobe_defaults: Dictionary={}

func _ready() -> void:
	for item: Resource in catalogue.items: register_item(item)
	_new_model(); WorldEvents.run_reset.connect(reset_run)
	_load_collection()

func _new_model() -> void:
	model=Model.new(catalogue.item_capacity,catalogue.equipment_capacity)
	model.changed.connect(_model_changed)

func register_item(item: Resource) -> bool:
	if not item or not item.has_method("maximum_stack") or item.id.is_empty(): return false
	_registry[item.id]=item; return true

func resolve_item(id: StringName,path := "") -> Resource:
	if _registry.has(id): return _registry[id]
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var value: Resource=load(path)
		if register_item(value) and value.id==id: return value
	return null

func bind_game(session: Node) -> void:
	game=session
	if not initialized:
		_mutating=true; backend=session.player.weapon_inventory
		for state: Dictionary in backend.weapons:
			var item := weapon_item(state.definition)
			var before := {}
			for entry: Dictionary in model.sections[&"equipment"]:
				if not entry.is_empty(): before[entry.uid]=true
			model.add(item,1,{"ammo":int(state.ammo)})
			for entry: Dictionary in model.sections[&"equipment"]:
				if not entry.is_empty() and not before.has(entry.uid): state["inventory_uid"]=entry.uid; break
		for ammo_type in backend.reserves:
			var quantity := int(backend.reserves[ammo_type])
			if quantity>0: model.add(ammo_item(ammo_type),quantity)
		if session.starting_medkits>0: model.add(resolve_item(&"medkit"),session.starting_medkits)
		initialized=true; _mutating=false
	else:
		if not backend: backend=Weapons.new()
		backend.cancel_reload(); backend.action=Weapons.Action.READY; backend.action_left=0
	_reconcile_backend()
	session.player.bind_weapon_inventory(backend)
	_bind_wardrobe(session.player)
	if not backend.ammo_changed.is_connected(_backend_changed): backend.ammo_changed.connect(_backend_changed)
	_publish()
	_restore_drops()

func _bind_wardrobe(player: Node) -> void:
	if is_instance_valid(_clothing) and _clothing.changed.is_connected(_wardrobe_changed):
		_clothing.changed.disconnect(_wardrobe_changed)
	_clothing=player.get_node_or_null("Tenue") as CharacterClothing
	_wardrobe_defaults={}
	if not _clothing:return
	_wardrobe_defaults=_clothing.wardrobe_state()
	if not _wardrobe.is_empty():_clothing.restore_wardrobe(_wardrobe)
	_clothing.changed.connect(_wardrobe_changed)
	_wardrobe_changed(null)

func _wardrobe_changed(_item: Resource) -> void:
	if is_instance_valid(_clothing):_wardrobe=_clothing.wardrobe_state()

func is_bound_player(player: Node) -> bool:
	return initialized and is_instance_valid(game) and game.player==player and backend!=null

func weapon_item(definition: Resource) -> Resource:
	var item := resolve_item(definition.id)
	if item and item.kind==Item.Kind.WEAPON: return item
	item=Item.new(); item.id=definition.id; item.display_name=definition.display_name; item.kind=Item.Kind.WEAPON; item.weapon=definition
	register_item(item); return item

func ammo_item(ammo_type: StringName) -> Resource:
	for item: Resource in _registry.values():
		if item.kind==Item.Kind.AMMO and item.ammo_type==ammo_type: return item
	var item := Item.new(); item.id=StringName("ammo_"+String(ammo_type)); item.kind=Item.Kind.AMMO
	item.display_name="Munitions "+String(ammo_type); item.ammo_type=ammo_type; item.stack_limit=99
	register_item(item); return item

func can_add(item: Resource,quantity := 1,state: Dictionary={}) -> bool:
	return register_item(item) and quantity>0 and model.capacity_for(item,state)>=quantity and (item.kind!=Item.Kind.WEAPON or item.weapon!=null)

func give(item: Resource,quantity := 1,state: Dictionary={},discovery := true) -> bool:
	if not can_add(item,quantity,state): return false
	if item.kind==Item.Kind.WEAPON and is_instance_valid(game) and not game.player.ensure_weapon_visual(item.weapon): return false
	if not model.add(item,quantity,state): return false
	item_acquired.emit(item,quantity,discovery); return true

func give_weapon(definition: Resource,equip := false) -> int:
	# Preserve the existing grant API: a new loadout includes its authored reserve.
	# Physical InventoryPickup3D weapons use give(), retaining their own packet only.
	if backend:
		for index in backend.weapons.size():
			if backend.weapons[index].definition.id==definition.id:
				if equip: backend.equip(index)
				return index
	var item := weapon_item(definition)
	var ammunition := ammo_item(definition.ammo_type)
	var reserve: int=maxi(int(definition.starting_reserve),0)
	var probe := Model.new(catalogue.item_capacity,catalogue.equipment_capacity)
	if not probe.restore(model.snapshot(),resolve_item) or not probe.add(item,1) or (reserve>0 and not probe.add(ammunition,reserve)): return -1
	if is_instance_valid(game) and not game.player.ensure_weapon_visual(definition): return -1
	_mutating=true; model.add(item,1)
	if reserve>0: model.add(ammunition,reserve)
	_mutating=false; _reconcile_backend(); _publish()
	item_acquired.emit(item,1,true)
	var uid := ""
	for entry: Dictionary in model.sections[&"equipment"]:
		if not entry.is_empty() and entry.item==item: uid=entry.uid
	var index := weapon_index(uid)
	if equip and index>=0: backend.equip(index)
	return index

func add_ammo(ammo_type: StringName,quantity: int) -> int:
	return quantity if give(ammo_item(ammo_type),quantity) else 0

func count(id: StringName) -> int: return model.count(id)
func has_item(id: StringName,quantity := 1) -> bool: return count(id)>=quantity
func remove_item(id: StringName,quantity := 1) -> bool: return model.remove_id(id,quantity)
func move(uid: String,section: StringName,index: int) -> bool: return model.move(uid,section,index)

func _model_changed() -> void:
	if _mutating: return
	_reconcile_backend(); _publish()

func _reconcile_backend() -> void:
	if _mutating: return
	_mutating=true
	if not backend: backend=Weapons.new()
	var active := active_weapon_uid(); var previous := {}
	for state: Dictionary in backend.weapons:
		if state.has("inventory_uid"): previous[state.inventory_uid]=state
	var ordered: Array[Dictionary]=[]; var reserves := {}
	for entry: Dictionary in model.sections[&"equipment"]:
		if entry.is_empty(): continue
		if entry.item.kind==Item.Kind.AMMO:
			var type: StringName=entry.item.ammo_type; reserves[type]=int(reserves.get(type,0))+int(entry.quantity)
		elif entry.item.kind==Item.Kind.WEAPON and entry.item.weapon:
			var state: Dictionary=previous.get(entry.uid,{})
			if state.is_empty():
				var definition: Resource=entry.item.weapon.duplicate(); definition.starting_reserve=0
				state={"definition":definition,"ammo":clampi(int(entry.state.get("ammo",definition.starting_ammo)),0,definition.magazine_capacity),"cooldown":0.0,"inventory_uid":entry.uid}
			ordered.append(state); entry.state["ammo"]=int(state.ammo)
	backend.weapons=ordered; backend.reserves=reserves
	backend.active_index=-1
	var requested := _preferred_weapon if not _preferred_weapon.is_empty() else active
	for index in ordered.size():
		if ordered[index].inventory_uid==requested: backend.active_index=index
	if backend.active_index<0 and not backend.holstered and not ordered.is_empty(): backend.active_index=0
	_preferred_weapon=""
	if is_instance_valid(game) and is_instance_valid(game.player):
		for state: Dictionary in ordered: game.player.ensure_weapon_visual(state.definition)
	if active!=active_weapon_uid(): backend.action=Weapons.Action.READY; backend.action_left=0; backend.weapon_changed.emit()
	backend.ammo_changed.emit(); _mutating=false

func active_weapon_uid() -> String:
	return String(backend.weapons[backend.active_index].get("inventory_uid","")) if backend and backend.active_index>=0 and backend.active_index<backend.weapons.size() else ""
func weapon_index(uid: String) -> int:
	if backend:
		for index in backend.weapons.size():
			if backend.weapons[index].get("inventory_uid","")==uid: return index
	return -1

func _backend_changed() -> void:
	if _mutating or not backend: return
	_mutating=true
	for state: Dictionary in backend.weapons:
		var location: Dictionary=model.locate(String(state.get("inventory_uid","")))
		if not location.is_empty(): location.entry.state["ammo"]=int(state.ammo)
	for ammo_type in backend.reserves.keys():
		var present := 0
		for entry: Dictionary in model.sections[&"equipment"]:
			if not entry.is_empty() and entry.item.kind==Item.Kind.AMMO and entry.item.ammo_type==ammo_type: present+=int(entry.quantity)
		var desired := int(backend.reserves[ammo_type]); var difference := desired-present
		if difference>0:
			var item := ammo_item(ammo_type); var accepted := mini(difference,model.capacity_for(item))
			if accepted>0: model.add(item,accepted)
			backend.reserves[ammo_type]=present+accepted
		elif difference<0:
			var remaining := -difference
			for entry: Dictionary in model.sections[&"equipment"].duplicate():
				if entry.is_empty() or entry.item.kind!=Item.Kind.AMMO or entry.item.ammo_type!=ammo_type: continue
				var amount := mini(remaining,int(entry.quantity)); model.take(entry.uid,amount); remaining-=amount
				if remaining==0: break
	_mutating=false; model.revision+=1; _publish()

func _publish() -> void:
	for id in _registry:
		var quantity: int=model.count(id)
		var key := StringName("inventory.%s.count" % id)
		if quantity>0 or WorldEvents.fact(key,null)!=null: WorldEvents.set_fact(key,quantity)
		_last_counts[id]=quantity
	for id in collection:
		WorldEvents.set_fact(StringName("collection.%s.owned" % id),true)
	if is_instance_valid(game): game.medkits=model.count(&"medkit")
	changed.emit()

func use(uid: String) -> Dictionary:
	var location: Dictionary=model.locate(uid)
	if location.is_empty() or not is_instance_valid(game): return _result(false,"Objet indisponible.")
	var item: Resource=location.entry.item
	if item.kind==Item.Kind.WEAPON:
		var index := weapon_index(uid)
		if index>=0 and uid==active_weapon_uid():return _result(backend.unequip(),"Arme rangee.")
		return _result(index>=0 and backend.equip(index),"Arme equipee.")
	if item.kind==Item.Kind.DOCUMENT:
		WorldEvents.set_fact(StringName("document.%s.read" % item.id),true)
		WorldEvents.raise_event(StringName("document.%s.read" % item.id))
		return {"ok":true,"read":item,"message":""}
	if item.kind==Item.Kind.CONSUMABLE:
		if item.healing>0 and game.player.health>=game.player.max_health: return _result(false,"Sante deja au maximum.")
		if item.healing<=0 and item.use_actions.is_empty(): return _result(false,"Aucune utilisation definie.")
		if not item.use_actions.is_empty() and not WorldEvents.execute(item.use_actions,game): return _result(false,"Utilisation indisponible.")
		game.player.health=mini(game.player.health+item.healing,game.player.max_health)
		if item.consumed_on_use: model.take(uid,1)
		WorldEvents.raise_event(StringName("inventory.%s.used" % item.id))
		return _result(true,"Objet consomme.",not item.use_actions.is_empty())
	var target := nearest_target(item.id)
	if target and target.interact(game.player): return _result(true,"Objet utilise.",true)
	if item.id==&"fuse_16a" and game.legacy_couloir_content and game.nearest.get("kind","")=="power":
		game.interact()
		if game.power: return _result(true,"Fusible installe.",true)
	if not item.use_actions.is_empty():
		if WorldEvents.execute(item.use_actions,game):
			if item.consumed_on_use: model.take(uid,1)
			WorldEvents.raise_event(StringName("inventory.%s.used" % item.id))
			return _result(true,"Objet utilise.",true)
	return _result(false,"Cet objet ne s'utilise pas ici.")

func quick_heal() -> bool:
	for entry: Dictionary in model.sections[&"items"]:
		if not entry.is_empty() and entry.item.kind==Item.Kind.CONSUMABLE and entry.item.healing>0:
			var result := use(entry.uid); notice.emit(result.message); return result.ok
	notice.emit("Aucun soin disponible."); return false

func nearest_target(id: StringName) -> Node:
	if not is_instance_valid(game): return null
	var chosen: Node; var best: float=game.interaction_distance
	for target in get_tree().get_nodes_in_group("world_interactions"):
		if not game.is_ancestor_of(target) or not target.has_method("accepts_inventory_item") or not target.accepts_inventory_item(id) or not target.can_interact(): continue
		var point: Vector3=target.get_interaction_position(); var distance: float=game.player.global_position.distance_to(point)
		# Use the same horizontal reach as the normal E interaction.
		distance=Vector2(point.x-game.player.global_position.x,point.z-game.player.global_position.z).length()
		if distance>best: continue
		var ray := PhysicsRayQueryParameters3D.create(game.player.global_position+Vector3.UP*1.1,point,1)
		var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and not target.is_ancestor_of(hit.collider) and hit.position.distance_to(point)>.5: continue
		chosen=target; best=distance
	return chosen

func _result(ok: bool,message: String,close := false) -> Dictionary: return {"ok":ok,"message":message,"close":close}

func collect_card(id: StringName) -> bool:
	var card: Resource=catalogue.card(id)
	if not card: return false
	if collection.has(id): card_acquired.emit(card,false); return false
	collection[id]=true; _save_collection(); _publish(); collection_changed.emit(id)
	card_acquired.emit(card,true)
	WorldEvents.raise_event(StringName("collection.%s.found" % id)); return true
func owns_card(id: StringName) -> bool: return bool(collection.get(id,false))

func _load_collection() -> void:
	if not persist_collection or not FileAccess.file_exists(collection_file): return
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(collection_file))
	if not data is Dictionary or not data.get("cards",[]) is Array: return
	for id in data.cards:
		if catalogue.card(StringName(id)): collection[StringName(id)]=true
	_publish()
func _save_collection() -> void:
	if not persist_collection: return
	var temporary := collection_file+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if not file: return
	file.store_string(JSON.stringify({"version":1,"cards":collection.keys()})); file.flush(); file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(collection_file))

func drop(uid: String,quantity: int) -> bool:
	var location: Dictionary=model.locate(uid)
	if location.is_empty() or not location.entry.item.can_discard() or quantity<=0 or quantity>int(location.entry.quantity) or not is_instance_valid(game): return false
	var packet: Dictionary=location.entry.duplicate(true); packet.quantity=quantity
	var id := StringName("inventory_drop_%d" % _next_drop); _next_drop+=1
	var origin: Vector3=game.player.global_position+Vector3.UP*.5
	var position: Vector3=origin-game.player.global_basis.z*.65
	var obstruction := PhysicsRayQueryParameters3D.create(origin,position,1)
	var wall: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(obstruction)
	if not wall.is_empty(): position=wall.position+wall.normal*.12
	var ray := PhysicsRayQueryParameters3D.create(position+Vector3.UP*.4,position-Vector3.UP*3,1)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty(): position=hit.position+Vector3.UP*.02
	var record := {"id":String(id),"level":game.level.scene_file_path,"position":[position.x,position.y,position.z],"packet":_packet_snapshot(packet)}
	_drops.append(record); _spawn_drop(record)
	model.take(uid,quantity); WorldEvents.raise_event(StringName("inventory.%s.dropped" % packet.item.id),{"quantity":quantity}); return true

func _packet_snapshot(entry: Dictionary) -> Dictionary:
	return {"id":String(entry.item.id),"path":entry.item.resource_path,"quantity":entry.quantity,"state":entry.state.duplicate(true)}
func remove_drop(id: StringName) -> void:
	for record in _drops.duplicate():
		if record.id==String(id): _drops.erase(record)
func _restore_drops() -> void:
	for record in _drops:
		if record.level==game.level.scene_file_path and not WorldEvents.interaction_used(StringName(record.id)): _spawn_drop(record)
func _spawn_drop(record: Dictionary) -> void:
	if game.level.has_node(NodePath(record.id)): return
	var pickup: Node3D=load("res://scripts/inventory/item_pickup.gd").new()
	pickup.add_to_group("inventory_runtime_drops")
	pickup.name=record.id; pickup.interaction_id=StringName(record.id); pickup.drop_id=StringName(record.id)
	pickup.item=resolve_item(StringName(record.packet.id),record.packet.path)
	pickup.quantity=record.packet.quantity; pickup.item_state=record.packet.state.duplicate(true)
	game.level.add_child(pickup); var p: Array=record.position; pickup.global_position=Vector3(p[0],p[1],p[2])

func _clear_live_drops() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.level): return
	for pickup in get_tree().get_nodes_in_group("inventory_runtime_drops"):
		if game.level.is_ancestor_of(pickup):
			pickup.get_parent().remove_child(pickup); pickup.free()

func snapshot() -> Dictionary:
	_backend_changed()
	return {"version":1,"model":model.snapshot(),"active_weapon":active_weapon_uid(),"weapon_holstered":backend!=null and backend.holstered,"collection":collection.keys(),"drops":_drops.duplicate(true),"next_drop":_next_drop,"wardrobe":_wardrobe.duplicate(true)}
func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version",0)!=1 or not data.get("model") is Dictionary or not _plain_data(data): return false
	var probe := Model.new(catalogue.item_capacity,catalogue.equipment_capacity)
	if not probe.restore(data.model,resolve_item): return false
	if not data.get("collection",[]) is Array or not data.get("drops",[]) is Array: return false
	var wardrobe: Variant=data.get("wardrobe",{})
	if not wardrobe is Dictionary:return false
	for field in ["slots","textures"]:
		var entries: Variant=wardrobe.get(field,{})
		if not entries is Dictionary:return false
		for key in entries:
			if typeof(entries[key]) not in [TYPE_STRING,TYPE_STRING_NAME]:return false
			if field=="slots" and String(key) not in ["0","1","2","3","4"]:return false
	var active := String(data.get("active_weapon","")); var equipped: Dictionary=probe.locate(active)
	if not active.is_empty() and (equipped.is_empty() or equipped.entry.item.kind!=Item.Kind.WEAPON): return false
	var holstered: Variant=data.get("weapon_holstered",false)
	if holstered is not bool or (holstered and not active.is_empty()): return false
	var ids := {}
	for drop in data.get("drops",[]):
		if not drop is Dictionary or not drop.get("packet") is Dictionary: return false
		var id := String(drop.get("id","")); var position: Variant=drop.get("position")
		if not id.begins_with("inventory_drop_") or not id.trim_prefix("inventory_drop_").is_valid_int() or ids.has(id) or not drop.get("level") is String: return false
		if not position is Array or position.size()!=3: return false
		for coordinate in position:
			if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)): return false
		var packet: Dictionary=drop.packet; var item := resolve_item(StringName(packet.get("id","")),String(packet.get("path","")))
		if not item or not packet.get("state",{}) is Dictionary or int(packet.get("quantity",0))<1 or int(packet.quantity)>item.maximum_stack(): return false
		ids[id]=true
	return true
func _plain_data(value: Variant,depth := 0) -> bool:
	if depth>32: return false
	if value is Dictionary:
		for key in value:
			if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or not _plain_data(value[key],depth+1): return false
		return true
	if value is Array:
		for part in value:
			if not _plain_data(part,depth+1): return false
		return true
	return typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_STRING_NAME]
func restore(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	_mutating=true
	var ok: bool=model.restore(data.model,resolve_item)
	_mutating=false
	if not ok: return false
	if backend and backend.ammo_changed.is_connected(_backend_changed): backend.ammo_changed.disconnect(_backend_changed)
	backend=Weapons.new(); _preferred_weapon=String(data.get("active_weapon","")); initialized=true
	backend.holstered=bool(data.get("weapon_holstered",false))
	for id in data.get("collection",[]):
		if catalogue.card(StringName(id)): collection[StringName(id)]=true
	_clear_live_drops(); _drops.assign(data.get("drops",[])); _next_drop=maxi(int(data.get("next_drop",1)),1)
	for record in _drops: _next_drop=maxi(_next_drop,int(String(record.id).trim_prefix("inventory_drop_"))+1)
	_reconcile_backend()
	if is_instance_valid(game): game.player.bind_weapon_inventory(backend)
	_wardrobe=data.get("wardrobe",{}).duplicate(true)
	if is_instance_valid(_clothing):
		_clothing.restore_wardrobe(_wardrobe if not _wardrobe.is_empty() else _wardrobe_defaults)
		_wardrobe_changed(null)
	backend.ammo_changed.connect(_backend_changed); _publish(); _restore_drops(); _save_collection(); return true

func reset_run() -> void:
	if backend and backend.ammo_changed.is_connected(_backend_changed): backend.ammo_changed.disconnect(_backend_changed)
	# World restore also resets the run before applying its snapshot to this player.
	_wardrobe.clear()
	_clear_live_drops(); backend=null; initialized=false; _drops.clear(); _next_drop=1; _preferred_weapon=""
	_new_model(); _publish()
