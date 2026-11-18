extends RefCounted
## Authoritative weapon/ammo state; no scene, audio or input dependencies.
signal weapon_changed
signal ammo_changed
const Definition = preload("res://scripts/weapon_definition.gd")
enum Action { READY, RELOADING, SWITCHING }
var weapons: Array[Dictionary]=[]
var reserves: Dictionary={}
var active_index := -1
var holstered := false
var action := Action.READY
var action_left := 0.0

func active_definition() -> Definition:
	return weapons[active_index].definition if active_index>=0 else null

func add_weapon(template: Definition) -> int:
	if not template or template.id.is_empty() or template.ammo_type.is_empty():return -1
	for index in weapons.size():
		if weapons[index].definition.id==template.id:return index
	var definition: Definition=template.duplicate()
	definition.magazine_capacity=maxi(definition.magazine_capacity,1)
	definition.shot_interval=maxf(definition.shot_interval,.05)
	definition.reload_duration=maxf(definition.reload_duration,.01)
	weapons.append({"definition":definition,"ammo":clampi(definition.starting_ammo,0,definition.magazine_capacity),"cooldown":0.0})
	add_ammo(definition.ammo_type,maxi(definition.starting_reserve,0))
	return weapons.size()-1

func equip(index: int,immediate := false) -> bool:
	if index<0 or index>=weapons.size() or index==active_index:return false
	# No rounds are removed until reload completion, so cancellation is lossless.
	active_index=index
	holstered=false
	action_left=0.0 if immediate else maxf(active_definition().equip_duration,0)
	action=Action.SWITCHING if action_left>0 else Action.READY
	weapon_changed.emit();ammo_changed.emit()
	return true

func cycle(direction: int) -> bool:
	if active_index<0:return equip(0 if direction>0 else weapons.size()-1)
	if weapons.size()<2:return false
	return equip(posmod(active_index+(1 if direction>0 else -1),weapons.size()))

func unequip() -> bool:
	if active_index<0:return false
	active_index=-1
	holstered=true
	action=Action.READY;action_left=0.0
	weapon_changed.emit();ammo_changed.emit()
	return true

func ammo() -> int:
	return int(weapons[active_index].ammo) if active_index>=0 else 0

func set_ammo(value: int) -> void:
	if active_index<0:return
	weapons[active_index].ammo=clampi(value,0,active_definition().magazine_capacity)
	ammo_changed.emit()

func reserve() -> int:
	return int(reserves.get(active_definition().ammo_type,0)) if active_index>=0 else 0

func set_reserve(value: int) -> void:
	if active_index<0:return
	reserves[active_definition().ammo_type]=maxi(value,0)
	ammo_changed.emit()

func add_ammo(ammo_type: StringName,count: int) -> int:
	if ammo_type.is_empty() or count<=0:return 0
	reserves[ammo_type]=int(reserves.get(ammo_type,0))+count
	ammo_changed.emit()
	return count

func cooldown() -> float:
	return float(weapons[active_index].cooldown) if active_index>=0 else 0.0

func try_fire() -> bool:
	if active_index<0 or action!=Action.READY or cooldown()>.000001 or ammo()<=0:return false
	weapons[active_index].ammo-=1
	weapons[active_index].cooldown=active_definition().shot_interval
	ammo_changed.emit()
	return true

func begin_reload(duration := -1.0) -> bool:
	if active_index<0 or action!=Action.READY or ammo()>=active_definition().magazine_capacity or reserve()<=0:return false
	action=Action.RELOADING;action_left=duration if duration>0 else active_definition().reload_duration
	ammo_changed.emit()
	return true

func dry_fire() -> bool:
	if active_index<0 or action!=Action.READY or cooldown()>.000001 or ammo()>0:return false
	weapons[active_index].cooldown=.2
	return true

func cancel_reload() -> void:
	if action!=Action.RELOADING:return
	action=Action.READY;action_left=0;ammo_changed.emit()

func advance(delta: float) -> void:
	delta=maxf(delta,0)
	for state in weapons:state.cooldown=maxf(float(state.cooldown)-delta,0)
	if action==Action.READY:return
	action_left=maxf(action_left-delta,0)
	if action_left>.000001:return
	if action==Action.RELOADING:
		var transferred := mini(maxi(active_definition().magazine_capacity-ammo(),0),reserve())
		weapons[active_index].ammo+=transferred
		reserves[active_definition().ammo_type]-=transferred
	action=Action.READY;action_left=0;ammo_changed.emit()
