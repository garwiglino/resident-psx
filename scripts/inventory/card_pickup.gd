@tool
class_name CollectionCard3D
extends "res://scripts/world_events/world_interaction_3d.gd"
const Catalogue=preload("res://assets/inventory/catalogue.tres")
const PSX=preload("res://scripts/psx_materials.gd")
@export var card_id: StringName=&"cendre_01"
## Keep enabled in normal levels. Disable for a repeatable test/demo placement.
@export var hide_when_owned := true:
	set(value):
		hide_when_owned=value
		if is_node_ready(): _sync()
@export_range(.15,.5,.01,"suffix:m") var card_height := .30:
	set(value): card_height=value; _schedule()
@export_range(0,180,1,"suffix:deg/s") var rotation_speed := 42.0
@export_range(0,.1,.005,"suffix:m") var bob_amount := .025
@export_range(.1,5,.1) var bob_speed := 1.7
@export_range(0,1,.01) var minimum_light := .25:
	set(value): minimum_light=value; _schedule()
var _visual: Node3D
var _time := 0.0
var _pending := false
var _collected := false
var _authored_enabled := true
func _enter_tree() -> void:
	super._enter_tree(); add_to_group("psx_dynamic_geometry"); add_to_group("psx_no_light_occluder")
	if is_node_ready() and not Engine.is_editor_hint(): call_deferred("_sync")
func _ready() -> void:
	_authored_enabled=enabled
	_time=float(absi(hash(str(get_path())))%1000)/100.0; _build()
	if not Engine.is_editor_hint():
		var inventory := get_node_or_null("/root/InventoryState")
		if inventory: inventory.collection_changed.connect(_collection_changed)
		WorldEvents.state_changed.connect(_world_changed)
		WorldEvents.run_reset.connect(_defer_sync)
		_sync()
func _defer_sync() -> void: call_deferred("_sync")
func _world_changed(key: StringName,_value: Variant) -> void:
	if key==&"world.restored" or key==StringName("interaction.%s.used" % _id()): _sync()
func _collection_changed(id: StringName) -> void:
	if id==card_id: _sync()
func _sync() -> void:
	if not is_inside_tree(): return
	var inventory := get_node_or_null("/root/InventoryState")
	_collected=not Engine.is_editor_hint() and (WorldEvents.interaction_used(_id()) or (hide_when_owned and inventory!=null and inventory.owns_card(card_id)))
	enabled=_authored_enabled and not _collected
	if is_instance_valid(_visual): _visual.visible=not _collected
	set_process(not _collected)
func _schedule() -> void:
	if is_inside_tree() and not _pending: _pending=true; call_deferred("_build")
func _build() -> void:
	_pending=false
	if is_instance_valid(_visual): remove_child(_visual); _visual.free()
	_visual=Node3D.new(); _visual.name="CarteAnimee"; add_child(_visual)
	for back in [false,true]:
		var mesh := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size=Vector2(card_height*2/3,card_height)
		quad.material=PSX.make(Color.WHITE,Catalogue.card_back if back else Catalogue.card_mystery,Vector2.ONE,Color(minimum_light,minimum_light,minimum_light))
		mesh.mesh=quad; mesh.rotation.y=PI if back else 0.0; mesh.position.z=-.0005 if back else .0005
		_visual.add_child(mesh)
	_visual.position.y=card_height*.7; interaction_offset=Vector3(0,card_height*.7,0)
	_visual.visible=not _collected
	set_process(not _collected)
	refresh_render_geometry(self)
func _process(delta: float) -> void:
	if not _visual: return
	_time+=delta; _visual.rotation.y+=deg_to_rad(rotation_speed)*delta; _visual.position.y=card_height*.7+sin(_time*bob_speed)*bob_amount
func get_interaction_label() -> String: return "RAMASSER LA CARTE"
func _perform() -> bool:
	var inventory := get_node_or_null("/root/InventoryState")
	if not inventory or not Catalogue.card(card_id): return false
	var fresh: bool=inventory.collect_card(card_id)
	_hide_card()
	var game := WorldEvents.game_for(self)
	if game:
		game.hud.toast("Carte trouvee : "+Catalogue.card(card_id).display_name if fresh else "Carte deja dans la collection.")
	return true
func _hide_card() -> void:
	_collected=true; enabled=false; set_process(false)
	if _visual: _visual.visible=false
func _validate_property(property: Dictionary) -> void:
	if property.name=="card_id":
		var values := PackedStringArray()
		for card: Resource in Catalogue.cards: values.append(String(card.id))
		property.hint=PROPERTY_HINT_ENUM; property.hint_string=",".join(values)
func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray() if Catalogue.card(card_id) else PackedStringArray(["Choisir une carte du catalogue FERRO ECLIPSE."])
