@tool
class_name CharacterClothing
extends Node
const Item=preload("res://scripts/clothing/clothing_item.gd")
const Materials=preload("res://scripts/psx_materials.gd")
const Masks=preload("res://scripts/clothing/clothing_masks.gd")
const WINTER=preload("res://assets/character/clothing/winter_jacket.tres")
const LARGE_JEANS=preload("res://assets/character/clothing/large_jeans_01.tres")
const SNEAKERS=preload("res://assets/character/clothing/sneakers.tres")
const COP_OUTFIT=preload("res://assets/character/clothing/cop_outfit.tres")
const SLOTS := [Item.Slot.SHOES,Item.Slot.PANTS,Item.Slot.TOP,Item.Slot.OUTFIT,Item.Slot.OUTERWEAR]
const VARIANT_SLOTS := {
	&"texture_chaussures":Item.Slot.SHOES,
	&"texture_pantalon":Item.Slot.PANTS,
	&"texture_haut":Item.Slot.TOP,
	&"texture_tenue_complete":Item.Slot.OUTFIT,
	&"texture_doudoune":Item.Slot.OUTERWEAR,
}
signal changed(item: Resource)
@export_node_path("Node3D") var model_path := NodePath("../Visual/CharacterMotion/cop")
## Modules precharges. Le changement de tenue reutilise leurs textures et leurs poids.
@export var available_items: Array[Item]=[WINTER,LARGE_JEANS,SNEAKERS,COP_OUTFIT]
var _equipment: Dictionary={Item.Slot.OUTERWEAR:WINTER}
@export_group("Couche 1")
@export var shoes: Item:
	get:return _equipment.get(Item.Slot.SHOES)
	set(value):_set_slot(Item.Slot.SHOES,value)
@export var pants: Item:
	get:return _equipment.get(Item.Slot.PANTS)
	set(value):_set_slot(Item.Slot.PANTS,value)
@export var top: Item:
	get:return _equipment.get(Item.Slot.TOP)
	set(value):_set_slot(Item.Slot.TOP,value)
## Remplace le haut et le pantalon. Certaines tenues comprennent leurs chaussures.
@export var full_outfit: Item:
	get:return _equipment.get(Item.Slot.OUTFIT)
	set(value):_set_slot(Item.Slot.OUTFIT,value)
@export_group("Couche 2")
## Porte sur le corps, les pieces separees ou la tenue complete.
@export var outerwear: Item:
	get:return _equipment.get(Item.Slot.OUTERWEAR)
	set(value):_set_slot(Item.Slot.OUTERWEAR,value)
@export_group("")
@export_storage var _texture_choices: Dictionary[StringName,StringName]={}
var _skeleton: Skeleton3D
var _model: Node3D
var _cache: Dictionary={}
var _masks := Masks.new()
var _body_meshes: Array[MeshInstance3D]=[]
var _editor_clock := 0.0
var _asset_signature: Array=[]

func _ready() -> void:
	refresh();set_process(Engine.is_editor_hint())

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary]=[]
	for property in VARIANT_SLOTS:
		var item: Item=_equipment.get(VARIANT_SLOTS[property])
		if not item or not item.texture_set:continue
		var choices := item.texture_set.choices()
		if choices.size()<2:continue
		if properties.is_empty():
			properties.append({"name":"Variantes de texture","type":TYPE_NIL,"usage":PROPERTY_USAGE_GROUP})
		properties.append({"name":property,"type":TYPE_INT,"hint":PROPERTY_HINT_ENUM,
			"hint_string":",".join(choices),"usage":PROPERTY_USAGE_EDITOR})
	return properties

func _get(property: StringName) -> Variant:
	if not VARIANT_SLOTS.has(property):return null
	var item: Item=_equipment.get(VARIANT_SLOTS[property])
	if not item or not item.texture_set:return 0
	return maxi(0,item.texture_set.choices().find(String(_texture_choices.get(item.id,&""))))

func _set(property: StringName, value: Variant) -> bool:
	if not VARIANT_SLOTS.has(property):return false
	var slot: int=VARIANT_SLOTS[property]
	var item: Item=_equipment.get(slot)
	if not item or not item.texture_set:return false
	var choices := item.texture_set.choices()
	var index := int(value)
	if index<0 or index>=choices.size():return false
	return set_texture_variant(slot,StringName(choices[index]) if index>0 else &"")

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():set_process(false);return
	_editor_clock+=delta
	if _editor_clock<.3:return
	_editor_clock=0
	var model := get_node_or_null(model_path)
	if model!=_model or not is_instance_valid(_skeleton) or _signature()!=_asset_signature:refresh()
	else:
		for cached in _cache.values():
			if not is_instance_valid(cached.root):refresh();return

func refresh() -> void:
	_masks.clear()
	_body_meshes.clear()
	for cached in _cache.values():
		_disconnect_item(cached.item)
		if is_instance_valid(cached.root):_dispose_module(cached.root)
	_cache.clear();_model=get_node_or_null(model_path);_skeleton=null
	if not _model:return
	_skeleton=_model.get_node_or_null("rig/Skeleton3D")
	if not _skeleton:return
	_asset_signature=_signature()
	# Generated children are transient, not saved into the artist's scene.
	# This also removes stale modules left by a tool-script hot reload.
	for child in _skeleton.get_children():
		if child.has_meta("clothing_generated"):_dispose_module(child)
	for mesh: MeshInstance3D in _model.find_children("*","MeshInstance3D",true,false):
		if mesh.skin and mesh.get_node_or_null(mesh.skeleton)==_skeleton and mesh.mesh is ArrayMesh:
			_body_meshes.append(mesh)
			_masks.register_mesh(mesh,true)
	for item in available_items:_cache_item(item)
	for item: Item in _equipment.values():_cache_item(item)
	_apply()

func _dispose_module(mount: Node3D) -> void:
	mount.visible=false
	# Remove the rendering instance before releasing its private materials.
	# This also makes editor reimports safe for GLES dependency updates.
	for mesh in mount.find_children("*","MeshInstance3D",true,false):
		mesh.mesh=null
		mesh.material_override=null
	mount.free()

func _signature() -> Array:
	var result: Array=[]
	var items: Array[Item]=available_items.duplicate()
	for item: Item in _equipment.values():
		if item not in items:items.append(item)
	for item in items:
		if not item or not item.scene:continue
		result.append_array([item.get_instance_id(),item.id,item.slot,item.includes_shoes,item.automatic_mask,item.mask_allow_one_corner,item.scene.resource_path,FileAccess.get_modified_time(item.scene.resource_path),item.skin_metadata,FileAccess.get_modified_time(item.skin_metadata),item.hides_meshes.duplicate()])
	return result

func _cache_item(item: Item) -> bool:
	if not item or not item.scene or item.id.is_empty() or not is_instance_valid(_skeleton):return false
	if _cache.has(item.id):return _cache[item.id].item==item
	var source := item.scene.instantiate()
	var metadata: Dictionary={}
	if not item.skin_metadata.is_empty() and FileAccess.file_exists(item.skin_metadata):
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(item.skin_metadata))
		if parsed is Dictionary:metadata=parsed
	var meshes: Array[MeshInstance3D]=[]
	for child in source.find_children("*","MeshInstance3D",true,false):meshes.append(child)
	if meshes.is_empty():source.free();return false
	var prepared: Array[Dictionary]=[]
	for mesh in meshes:
		var source_skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if not mesh.skin or not source_skeleton or not mesh.mesh is ArrayMesh:source.free();return false
		var skin := Skin.new()
		var mask_bind_transforms: Array[Transform3D]=[]
		for bind in mesh.skin.get_bind_count():
			var name := String(mesh.skin.get_bind_name(bind))
			if name.is_empty():name=String(source_skeleton.get_bone_name(mesh.skin.get_bind_bone(bind)))
			if _skeleton.find_bone(name)<0:source.free();return false
			var source_bone := source_skeleton.find_bone(name)
			if source_bone<0:source.free();return false
			var pose := mesh.skin.get_bind_pose(bind)
			if metadata.get("bind_space","")=="rig_local" and metadata.has("bind_vertex_transform"):
				var rows: Array=metadata.bind_vertex_transform
				var correction := Transform3D(Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2])),Vector3(rows[0][3],rows[1][3],rows[2][3]))
				pose=pose*correction
			skin.add_named_bind(name,pose)
			mask_bind_transforms.append(source_skeleton.get_bone_global_rest(source_bone)*pose)
		prepared.append({"mesh":mesh,"skin":skin,"mask_bind_transforms":mask_bind_transforms})
	var mount := Node3D.new();mount.name="Clothing_"+String(item.id);mount.set_meta("clothing_generated",true)
	_skeleton.add_child(mount);mount.visible=false
	for data in prepared:
		var mesh: MeshInstance3D=data.mesh
		mesh.owner=null
		mesh.get_parent().remove_child(mesh);mount.add_child(mesh)
		mesh.skin=data.skin;mesh.skeleton=mesh.get_path_to(_skeleton)
		if metadata.get("bind_space","")=="rig_local":mesh.transform=Transform3D.IDENTITY
		mesh.set_meta("psx_skin_metadata",item.skin_metadata)
		mesh.set_meta("clothing_id",item.id)
		mesh.set_meta("clothing_mask_allow_one_corner",item.mask_allow_one_corner)
		_masks.register_mesh(mesh,false,data.mask_bind_transforms)
	source.free()
	var surfaces: Array[Dictionary]=[]
	for mesh in mount.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var source_material: Material=mesh.get_active_material(surface)
			if not source_material is StandardMaterial3D:continue
			var material := Materials.character_material(source_material)
			mesh.set_surface_override_material(surface,material)
			surfaces.append({"material":material,"name":StringName(source_material.resource_name),
				"original_texture":source_material.albedo_texture})
	_cache[item.id]={"root":mount,"item":item,"materials":surfaces,"meshes":meshes}
	if not item.changed.is_connected(_item_changed.bind(item)):item.changed.connect(_item_changed.bind(item))
	_apply_texture(item)
	_register_geometry(mount)
	return true

func _disconnect_item(item: Item) -> void:
	if item and item.changed.is_connected(_item_changed.bind(item)):item.changed.disconnect(_item_changed.bind(item))

func _variant_surfaces(item: Item) -> Array:
	var surfaces: Array=_cache[item.id].materials
	if surfaces.is_empty() or not item.texture_set:return []
	var material_name := item.texture_set.material_name
	if not material_name.is_empty():
		return surfaces.filter(func(surface: Dictionary):return surface.name==material_name)
	var atlas: Texture2D=surfaces[0].original_texture
	if surfaces.all(func(surface: Dictionary):return surface.original_texture==atlas):
		return surfaces
	return []

func _apply_texture(item: Item) -> void:
	var cached: Dictionary=_cache[item.id]
	var variant: Texture2D
	var targets: Array=[]
	if item.texture_set:
		variant=item.texture_set.variants.get(_texture_choices.get(item.id,&""))
		if variant:targets=_variant_surfaces(item)
	for surface in cached.materials:
		var texture: Texture2D=item.texture if item.texture else surface.original_texture
		if variant and surface in targets:texture=variant
		if surface.material.albedo_texture==texture:continue
		surface.material.albedo_texture=texture
		if Engine.is_editor_hint():surface.material.emit_changed()

func _item_changed(item: Item) -> void:
	if not is_instance_valid(item) or not _cache.has(item.id):return
	notify_property_list_changed()
	_refresh_texture(item)

func _refresh_texture(item: Item) -> void:
	_apply_texture(item)
	if Engine.is_editor_hint():return
	var renderer := _find_renderer()
	if renderer:renderer.refresh_materials(_cache[item.id].root)

## Une cle vide restaure la texture d'origine. La selection appartient a ce joueur.
func set_texture_variant(slot: int, variant: StringName) -> bool:
	var item: Item=_equipment.get(slot)
	if not item:return false
	if not variant.is_empty():
		if not item.texture_set or not item.texture_set.variants.get(variant):return false
		if is_node_ready() and (_cache.has(item.id) and _variant_surfaces(item).is_empty()):return false
	if variant==_texture_choices.get(item.id,&""):return true
	var choices := _texture_choices.duplicate()
	if variant.is_empty():
		choices.erase(item.id)
	else:
		choices[item.id]=variant
	_texture_choices=choices
	if _cache.has(item.id):_refresh_texture(item)
	changed.emit(item)
	return true

func _find_renderer() -> Node:
	var ancestor := get_parent()
	while ancestor:
		var renderer := ancestor.get_node_or_null("PSXRenderer")
		if renderer and renderer.get("raster")!=null:return renderer
		if ancestor is Viewport:break
		ancestor=ancestor.get_parent()
	return null

func _register_geometry(mount: Node3D) -> void:
	if Engine.is_editor_hint():return
	var renderer := _find_renderer()
	if renderer:renderer.register_dynamic_geometry(mount)

func _apply() -> void:
	if not is_instance_valid(_skeleton):
		return
	var worn: Array[Item]=[]
	for item in _selected_items():
		if _cache_item(item):
			worn.append(item)
	for cached in _cache.values():
		cached.root.visible=cached.item in worn
	for mesh in _body_meshes:
		_apply_mesh_mask(mesh,worn)
	var outer: Array[Item]=[]
	if outerwear in worn:
		outer.append(outerwear)
	for item in worn:
		if item.slot==Item.Slot.OUTERWEAR:
			continue
		for mesh: MeshInstance3D in _cache[item.id].meshes:
			_apply_mesh_mask(mesh,outer)
	if not Engine.is_editor_hint():
		var renderer := _find_renderer()
		if renderer:renderer.request_paused_redraw()
	changed.emit(outerwear)

func _selected_items() -> Array[Item]:
	var items: Array[Item]=[]
	var slots: Array[int]=[]
	if not outfit_includes_shoes():slots.append(Item.Slot.SHOES)
	if full_outfit:
		slots.append(Item.Slot.OUTFIT)
	else:
		slots.append_array([Item.Slot.PANTS,Item.Slot.TOP])
	slots.append(Item.Slot.OUTERWEAR)
	for slot in slots:
		var item: Item=_equipment.get(slot)
		if item and item.slot==slot:
			items.append(item)
	return items

func outfit_includes_shoes() -> bool:
	return full_outfit!=null and full_outfit.includes_shoes

func _apply_mesh_mask(mesh: MeshInstance3D, layers: Array[Item]) -> void:
	var covers: Array[MeshInstance3D]=[]
	var hidden := false
	for item in layers:
		hidden=hidden or StringName(mesh.name) in item.hides_meshes
		if item.automatic_mask:
			covers.append_array(_cache[item.id].meshes)
	_masks.apply(mesh,covers,hidden)

func _set_slot(slot: int, item: Item) -> bool:
	if item and (item.slot!=slot or (is_node_ready() and not _cache_item(item))):
		return false
	if item:
		_equipment[slot]=item
	else:
		_equipment.erase(slot)
	notify_property_list_changed()
	if is_node_ready():
		_apply()
	return true

func equip(item: Item) -> bool:
	if not item or not _cache_item(item):
		return false
	if item.slot in [Item.Slot.TOP,Item.Slot.PANTS]:
		_equipment.erase(Item.Slot.OUTFIT)
	return _set_slot(item.slot,item)

func equip_id(id: StringName) -> bool:
	for item in available_items:
		if item and item.id==id:return equip(item)
	return false

func unequip(slot := Item.Slot.OUTERWEAR) -> void:
	_set_slot(slot,null)

func is_equipped(id: StringName) -> bool:
	for item in _selected_items():
		if item.id==id and _cache.has(id) and _cache[id].root.visible:
			return true
	return false

func items_for_slot(slot: int) -> Array[Item]:
	var items: Array[Item]=[]
	for cached in _cache.values():
		var item: Item=cached.item
		if item.slot==slot:items.append(item)
	return items

func add_available_item(item: Item) -> bool:
	if not _cache_item(item):return false
	if item not in available_items:
		available_items=available_items.duplicate()
		available_items.append(item)
		changed.emit(item)
	return true

func equipped_item(slot: int) -> Item:
	var item: Item=_equipment.get(slot)
	return item if item and is_equipped(item.id) else null

func texture_variant(slot: int) -> StringName:
	var item := equipped_item(slot)
	return _texture_choices.get(item.id,&"") if item else &""

func wardrobe_state() -> Dictionary:
	var slots := {}
	for slot in SLOTS:
		var item: Item=_equipment.get(slot)
		slots[str(slot)]=String(item.id) if item else ""
	return {"slots":slots,"textures":_texture_choices.duplicate()}

func restore_wardrobe(state: Dictionary) -> void:
	var slots: Dictionary=state.get("slots",{})
	var equipment := _equipment.duplicate()
	for slot in SLOTS:
		var key := str(slot)
		if not slots.has(key):continue
		var id := StringName(slots[key])
		if id.is_empty():
			equipment.erase(slot)
		elif _cache.has(id) and _cache[id].item.slot==slot:
			equipment[slot]=_cache[id].item
	var choices: Dictionary[StringName,StringName]={}
	var textures: Dictionary=state.get("textures",{})
	for key in textures:
		var id := StringName(key)
		var variant := StringName(textures[key])
		if not _cache.has(id):continue
		var item: Item=_cache[id].item
		if item.texture_set and item.texture_set.variants.get(variant):choices[id]=variant
	var previous := _texture_choices
	if equipment==_equipment and choices==previous:return
	_equipment=equipment
	_texture_choices=choices
	var materials_changed := false
	for cached in _cache.values():
		var item: Item=cached.item
		if previous.get(item.id,&"")==choices.get(item.id,&""):continue
		_apply_texture(item)
		materials_changed=true
	if materials_changed and not Engine.is_editor_hint():
		var renderer := _find_renderer()
		if renderer:renderer.refresh_materials(_model)
	notify_property_list_changed()
	_apply()

func _exit_tree() -> void:
	_masks.clear()
	for cached in _cache.values():
		_disconnect_item(cached.item)
		if is_instance_valid(cached.root) and cached.root.is_inside_tree():cached.root.queue_free()
