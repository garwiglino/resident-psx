@tool
class_name InventoryPickup3D
extends "res://scripts/world_events/world_interaction_3d.gd"
const Item=preload("res://scripts/inventory/item_definition.gd")
const Visuals=preload("res://scripts/inventory/item_visuals.gd")
@export var item: Item:
	set(value): item=value; _schedule()
@export_range(1,999,1) var quantity := 1
@export var item_state: Dictionary={}
@export var rotation_speed := 35.0
@export_range(0,.1,.005,"suffix:m") var bob_amount := .018
var drop_id: StringName
var _visual: Node3D
var _time := 0.0
var _pending := false
var _collected := false
var _authored_enabled := true
var _base_height := .15
func _enter_tree() -> void:
	super._enter_tree(); add_to_group("psx_dynamic_geometry"); add_to_group("psx_no_light_occluder")
	if is_node_ready() and not Engine.is_editor_hint(): call_deferred("_sync")
func _ready() -> void:
	_authored_enabled=enabled
	_build()
	if not Engine.is_editor_hint():
		WorldEvents.run_reset.connect(_defer_sync)
		WorldEvents.state_changed.connect(_world_changed)
		_sync()
func _defer_sync() -> void: call_deferred("_sync")
func _world_changed(key: StringName,_value: Variant) -> void:
	if key==&"world.restored": _sync()
func _sync() -> void:
	if not is_inside_tree(): return
	_collected=WorldEvents.interaction_used(_id()); enabled=_authored_enabled and not _collected
	if is_instance_valid(_visual): _visual.visible=not _collected
	set_process(not _collected)
func _schedule() -> void:
	if is_inside_tree() and not _pending: _pending=true; call_deferred("_build")
func _build() -> void:
	_pending=false
	if is_instance_valid(_visual): remove_child(_visual); _visual.free()
	_visual=Node3D.new(); _visual.name="Objet"; add_child(_visual)
	_visual.add_child(Visuals.world(item))
	var bounds := Visuals.bounds(_visual)
	_base_height=maxf(.15,-bounds.position.y+bob_amount+.03)
	interaction_offset=Vector3(0,_base_height+bounds.get_center().y,0); _visual.position.y=_base_height
	_visual.visible=not _collected
	set_process(not _collected)
	refresh_render_geometry(self)
func _process(delta: float) -> void:
	if not is_instance_valid(_visual): return
	_time+=delta; _visual.rotation.y+=deg_to_rad(rotation_speed)*delta; _visual.position.y=_base_height+sin(_time*2.2)*bob_amount
func get_interaction_label() -> String:
	return "RAMASSER "+(item.display_name.to_upper() if item else "OBJET")+(" (%d)" % quantity if quantity>1 else "")
func _perform() -> bool:
	if not item or _collected: return false
	var inventory := get_node_or_null("/root/InventoryState"); var game := WorldEvents.game_for(self)
	if not inventory or not inventory.give(item,quantity,item_state,drop_id.is_empty()):
		if game: game.hud.toast("Pas assez de place dans l'inventaire.")
		return false
	if not drop_id.is_empty(): inventory.remove_drop(drop_id)
	_hide_pickup()
	if game: game.hud.toast("Objet ramasse : "+item.display_name)
	return true
func _hide_pickup() -> void:
	_collected=true; enabled=false; set_process(false)
	if _visual: _visual.visible=false
