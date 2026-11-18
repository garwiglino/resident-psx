@tool
class_name ModularMap3D
extends Node3D
signal plan_changed
signal construction_rebuilt
const Layout = preload("res://scripts/modular_map/layout.gd")
const Kit = preload("res://scripts/modular_map/kit.gd")
const Door = preload("res://scripts/modular_map/door.gd")
const Sequence = preload("res://scripts/dialogue/dialogue_sequence.gd")
const ReflectiveMaterial = preload("res://scripts/materials/psx_reflective_material.gd")
const DEFAULT_GLASS_REFLECTIONS = preload("res://assets/materials/reflections/vitre.tres")
const GlassBreak = preload("res://scripts/modular_map/door_glass_break.gd")
const GLASS_DUST := "res://assets/effects/glass_dust_atlas.png"
const GLASS_PAGE := "res://assets/environment/modular_2m/new_atlas_portes_psx_256_256_64_128.png"
const GLASS_FRACTURE := "res://assets/environment/modular_2m/door_01_glass_fracture.json"
@export var layout: Resource:
	set(value):
		if layout and layout.changed.is_connected(_plan_changed): layout.changed.disconnect(_plan_changed)
		layout=value
		if layout and not layout.changed.is_connected(_plan_changed): layout.changed.connect(_plan_changed)
		_plan_changed()
@export var kit: Resource:
	set(value):
		if kit and kit.changed.is_connected(_schedule): kit.changed.disconnect(_schedule)
		kit=value
		if kit and not kit.changed.is_connected(_schedule): kit.changed.connect(_schedule)
		_schedule()
@export_group("Construction")
@export var ceilings := true:
	set(value): ceilings=value; _schedule()
## Editor cutaway only. The runtime always uses the Ceilings setting above.
@export var show_ceilings_in_editor := false:
	set(value): show_ceilings_in_editor=value; _schedule()
@export_storage var editor_storey := 0
@export var show_other_storeys_in_editor := false:
	set(value):show_other_storeys_in_editor=value;_schedule()
## Unique per map. Door facts use <namespace>.<edge>, even after a rebuild.
@export var event_namespace := "carte"
## Reflet peint des surfaces vitrees. Vider pour garder le verre d'origine.
@export var glass_reflections: ReflectiveMaterial = DEFAULT_GLASS_REFLECTIONS:
	set(value):
		if glass_reflections and glass_reflections.changed.is_connected(_schedule):
			glass_reflections.changed.disconnect(_schedule)
		glass_reflections=value
		_watch_glass_reflections()
		_schedule()
@export_group("Bris de verre")
## Son spatial de la vitre. Mixage audio > Interactions.
@export var glass_break_sound: AudioStream:
	set(value):
		glass_break_sound=value
		_update_glass_break_sounds()
@export_range(-40,0,.5,"suffix:dB") var glass_break_volume_db := 0.0:
	set(value):
		glass_break_volume_db=value
		_update_glass_break_sounds()
@export_group("Portes verrouillees")
## Shared default; the Cartes 2m panel can override each door separately.
@export var locked_door_dialogues: Sequence=preload("res://assets/audio/dialogs/locked_doors_key/locked_doors_key.tres"):
	set(value): locked_door_dialogues=value; _schedule()
@export var permanent_door_dialogues: Sequence=preload("res://assets/audio/dialogs/locked_doors/locked_doors.tres"):
	set(value):
		# An editor resource opened before this field existed can serialize null.
		permanent_door_dialogues=value if value else preload("res://assets/audio/dialogs/locked_doors/locked_doors.tres");_schedule()
@export_range(0,30,.5,"suffix:s") var locked_dialogue_cooldown := 4.0:
	set(value): locked_dialogue_cooldown=value; _schedule()
@export_range(0,.5,.01,"suffix:s") var locked_dialogue_delay := .03:
	set(value):locked_dialogue_delay=value;_schedule()
@export var locked_door_sounds: Array[AudioStream]=[preload("res://assets/audio/interactables/locked_door_1.wav"),preload("res://assets/audio/interactables/locked_door_2.wav")]:
	set(value): locked_door_sounds=value; _schedule()
@export_range(-40,0,.5,"suffix:dB") var locked_sound_volume_db := -6.0:
	set(value): locked_sound_volume_db=value; _schedule()
var generated: Node3D
var _pending := false
var _glass_materials: Dictionary[StandardMaterial3D, StandardMaterial3D] = {}
var _glass_fracture: Dictionary = {}

func set_editor_storey(level: int) -> void:
	editor_storey=level;_schedule();update_gizmos()
func editor_height() -> float:return int(editor_storey)*Layout.STOREY_HEIGHT

func _plan_changed() -> void:
	_schedule(); plan_changed.emit()

func _ready() -> void:
	_watch_glass_reflections()
	if not layout: layout=Layout.new()
	if not kit and ResourceLoader.exists("res://assets/environment/modular_2m/default_kit.tres"):
		kit=load("res://assets/environment/modular_2m/default_kit.tres")
	rebuild()
	if not Engine.is_editor_hint():
		var session := get_node_or_null("/root/LevelRuntime")
		if session: session.request_current_scene()

func _schedule() -> void:
	if not is_inside_tree() or _pending: return
	_pending=true; call_deferred("rebuild")

func rebuild() -> void:
	_pending=false
	if not is_inside_tree(): return
	if is_instance_valid(generated): remove_child(generated); generated.free()
	_glass_materials.clear()
	generated=Node3D.new(); generated.name="Construction"; add_child(generated)
	# owner stays null: generated meshes/collisions never inflate the saved scene.
	if not layout or not kit or not kit.data:
		construction_rebuilt.emit()
		return
	var levels: Array[int]=layout.level_ids()
	if not int(editor_storey) in levels:editor_storey=0
	for level: int in levels:
		var parent := generated
		if level!=0:
			parent=Node3D.new();parent.name="Etage_"+str(level);parent.position.y=level*Layout.STOREY_HEIGHT;parent.set_meta("map_storey",level);generated.add_child(parent)
		_build_storey(parent,level)
	if Engine.is_editor_hint() and not show_other_storeys_in_editor:
		for child in generated.get_children():
			if child is Node3D:child.visible=int(child.get_meta("map_storey",0))==int(editor_storey)
	update_configuration_warnings(); update_gizmos()
	construction_rebuilt.emit()

func door_at_edge(level: int, edge: String) -> WorldDoor3D:
	if not is_instance_valid(generated): return null
	var storey_path := "" if level == 0 else "Etage_%d/" % level
	return generated.get_node_or_null(storey_path + "Bord_" + edge.replace(":","_") + "/Porte") as WorldDoor3D

func _build_storey(parent: Node3D,level: int) -> void:
	for cell: Vector2i in layout.surface_cells(level):
		var center := Vector3(cell.x*2+1,0,cell.y*2+1)
		if layout.has_floor(cell,level):
			_add_mesh(parent,"floor",center)
			_box(parent,Vector3(2,.1,2),center-Vector3(0,.05,0))
		if ceilings and layout.has_ceiling(cell,level) and (not Engine.is_editor_hint() or show_ceilings_in_editor):
			var shared_slab: bool=layout.has_floor(cell,level+1)
			_add_mesh(parent,"ceiling",center+Vector3(0,2.9 if shared_slab else 3.0,0))
			# The upper floor already supplies this slab's collision. Do not leave
			# a lower ceiling collider protruding above the upper floor surface.
			if not shared_slab:_box(parent,Vector3(2,.1,2),center+Vector3(0,3.05,0))
	var edges: Dictionary = layout.effective_edges(level)
	var graph := _junctions(edges)
	for key: String in edges:
		var config: Dictionary = edges[key]
		var info := Layout.edge_info(key)
		var slots := Layout.footprint(key,config)
		var finish: Vector2i = Layout.edge_info(slots[-1]).b
		var center: Vector3 = (info.center + Layout.edge_info(slots[-1]).center) * .5
		var branch: Vector2i = (finish - info.a).sign()
		var start_mask := _mask(graph,info.a,branch,info.yaw)
		var end_mask := _mask(graph,finish,-branch,info.yaw)
		var module: String = config.variant
		if config.kind == Layout.Kind.DOOR: module="wall_door_double" if slots.size()==2 else "wall_door"
		elif config.kind == Layout.Kind.WINDOW: module="wall_loop_window"
		var holder := Node3D.new(); holder.name="Bord_"+key.replace(":","_")
		holder.position=center; holder.rotation.y=info.yaw; parent.add_child(holder)
		_add_mesh(holder,module,Vector3.ZERO,start_mask,end_mask)
		var body := StaticBody3D.new(); holder.add_child(body)
		var shape := CollisionShape3D.new(); shape.shape=kit.shape_for(module,start_mask,end_mask); body.add_child(shape)
		if config.kind == Layout.Kind.DOOR: _door(holder,key,config,slots.size()==2,level)
		elif config.kind == Layout.Kind.WINDOW and config.variant != "empty":
			var panel := "window_condemned" if config.variant == "boarded" else "window_glass"
			_add_mesh(holder,panel,Vector3.ZERO)
			var panel_shape := CollisionShape3D.new(); panel_shape.shape=kit.shape_for(panel); body.add_child(panel_shape)

func _door(parent: Node3D, key: String, config: Dictionary, double: bool,level := 0) -> void:
	var door := Door.new(); door.name="Porte"
	var id := StringName(config.get("id", ""))
	var identity := key.replace(":","_") if level==0 else "etage_%d.%s" % [level,key.replace(":","_")]
	door.door_id=id if not id.is_empty() else StringName(event_namespace+"."+identity)
	var lock_mode: int=int(config.get("lock_mode",1 if not String(config.get("required_item_id","")).is_empty() else (2 if config.get("locked",false) else 0)))
	door.permanently_locked=lock_mode==2;door.initially_open=config.get("open",false) and lock_mode!=2;door.initially_locked=lock_mode!=0
	door.required_item_id=StringName(config.get("required_item_id","")) if lock_mode==1 else &""; door.consume_key_on_unlock=config.get("consume_key",false)
	door.opened_event=StringName(config.get("opened_event","")); door.closed_event=StringName(config.get("closed_event",""))
	door.locked_dialogue_enabled=config.get("locked_dialogue_enabled",true)
	door.locked_dialogue_pool=config.get("locked_dialogue_pool") if config.get("locked_dialogue_pool") else locked_door_dialogues
	door.permanent_dialogue_pool=config.get("permanent_dialogue_pool") if config.get("permanent_dialogue_pool") else permanent_door_dialogues
	if not door.permanent_dialogue_pool:door.permanent_dialogue_pool=preload("res://assets/audio/dialogs/locked_doors/locked_doors.tres")
	door.locked_dialogue_cooldown=locked_dialogue_cooldown
	door.locked_dialogue_delay=locked_dialogue_delay
	door.locked_sounds=locked_door_sounds;door.locked_sound_volume_db=locked_sound_volume_db
	door.interaction_offset=Vector3(0,1.1,0)
	var pivot := Node3D.new(); pivot.name="Pivot"; pivot.position.x=-1.0 if double else -.5
	door.add_child(pivot)
	var variant: String = config.variant
	var leaf: String = {"glass":"door_glass", "door_03":"door_03", "double_02":"door_02", "double_03":"door_03"}.get(variant, "door_01")
	var suffix := leaf.right(2) if leaf != "door_glass" else "02"
	var left_leaf := "double_door_left_" + suffix
	var right_leaf := "double_door_right_" + suffix
	# An individually exported leaf still overrides its corresponding pair.
	var authored_pair: bool = double and not kit.module_overrides.has(leaf) and kit.data.modules.has(left_leaf) and kit.data.modules.has(right_leaf)
	_door_leaf(pivot,left_leaf if authored_pair else leaf,door.door_id,&"gauche")
	if double:
		var right := Node3D.new(); right.name="RightPivot"; right.position.x=1
		if not authored_pair: right.rotation.y=PI
		door.add_child(right)
		_door_leaf(right,right_leaf if authored_pair else leaf,door.door_id,&"droite",authored_pair)
	parent.add_child(door)
	if Engine.is_editor_hint() and door.initially_open:
		pivot.rotation.y=deg_to_rad(-95)
		if double: door.get_node("RightPivot").rotation.y+=deg_to_rad(95)

func _add_mesh(parent: Node3D, module: String, at: Vector3, a := 0, b := 0) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name=module; node.mesh=kit.mesh_for(module,a,b)
	_apply_glass_reflections(node)
	node.position=at; parent.add_child(node); return node

func _door_leaf(pivot: Node3D, module: String, id: StringName, side: StringName, mirrored := false) -> void:
	var leaf := _add_mesh(pivot,module,Vector3.ZERO)
	if _build_breakable_pane(pivot,leaf,id,side,mirrored):return
	_box(pivot,Vector3(1,2.2,.045),Vector3(-.5 if mirrored else .5,1.1,0))

func _build_breakable_pane(pivot: Node3D, leaf: MeshInstance3D, id: StringName, side: StringName, mirrored: bool) -> bool:
	if not leaf.mesh:return false
	var pane_index := -1
	var glass_material: StandardMaterial3D
	for i in leaf.mesh.get_surface_count():
		var material := leaf.get_active_material(i) as StandardMaterial3D
		if not material or not _is_glass_material(material):continue
		if pane_index>=0:return false
		pane_index=i
		glass_material=material
	if pane_index<0 or leaf.mesh.get_surface_count()<2:return false
	var pane := ArrayMesh.new()
	pane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,leaf.mesh.surface_get_arrays(pane_index))
	pane.surface_set_material(0,glass_material)
	var bounds := pane.get_aabb()
	var leaf_left := -1.0 if mirrored else 0.0
	var leaf_right := leaf_left+1.0
	if bounds.position.x<=leaf_left or bounds.end.x>=leaf_right or bounds.position.y<=0.0 or bounds.end.y>=2.2:return false
	if _glass_fracture.is_empty():
		if not FileAccess.file_exists(GLASS_FRACTURE):return false
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(GLASS_FRACTURE))
		if not parsed is Dictionary or not parsed.has("rim") or not parsed.has("shards"):return false
		_glass_fracture=parsed
	var authored_uv := glass_material.resource_name == "new_atlas_portes_psx_256_256_64_128_glass" and ResourceLoader.exists(GLASS_PAGE)
	var fit := GlassBreak.fit_pane(_glass_fracture,pane,mirrored,authored_uv)
	if fit.is_empty():return false
	var dust_atlas := load(GLASS_DUST) as Texture2D if not Engine.is_editor_hint() else null
	if not Engine.is_editor_hint() and not dust_atlas:return false
	var fracture_material := glass_material
	if authored_uv:
		fracture_material=glass_material.duplicate() as StandardMaterial3D
		fracture_material.albedo_texture=load(GLASS_PAGE) as Texture2D
	var wood := ArrayMesh.new()
	for surface in leaf.mesh.get_surface_count():
		if surface==pane_index:continue
		wood.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,leaf.mesh.surface_get_arrays(surface))
		wood.surface_set_material(wood.get_surface_count()-1,leaf.get_active_material(surface))
	for surface in leaf.mesh.get_surface_count():leaf.set_surface_override_material(surface,null)
	leaf.mesh=wood
	var breaker := GlassBreak.new()
	breaker.name="VitreCassable"
	breaker.state_key=StringName("door.%s.glass.%s.broken" % [id,side])
	breaker.intact=MeshInstance3D.new()
	breaker.intact.name="VitreIntacte"
	breaker.intact.mesh=pane
	breaker.add_child(breaker.intact)
	breaker.configure(_glass_fracture,fit,fracture_material,dust_atlas,glass_break_sound,glass_break_volume_db)
	pivot.add_child(breaker)
	# Keep the solid leaf and allow a ray through the opening after breakage.
	var low := bounds.position
	var high := bounds.end
	var mid_y := (low.y+high.y)*.5
	_box(pivot,Vector3(1,low.y,.045),Vector3(leaf_left+.5,low.y*.5,0))
	_box(pivot,Vector3(1,2.2-high.y,.045),Vector3(leaf_left+.5,(high.y+2.2)*.5,0))
	_box(pivot,Vector3(low.x-leaf_left,bounds.size.y,.045),Vector3((low.x+leaf_left)*.5,mid_y,0))
	_box(pivot,Vector3(leaf_right-high.x,bounds.size.y,.045),Vector3((leaf_right+high.x)*.5,mid_y,0))
	return true

func _apply_glass_reflections(node: MeshInstance3D) -> void:
	if node.mesh and glass_reflections:
		for surface in node.mesh.get_surface_count():
			var base := node.mesh.surface_get_material(surface) as StandardMaterial3D
			if not base or base is ReflectiveMaterial or not _is_glass_material(base):
				continue
			if not _glass_materials.has(base):
				_glass_materials[base]=glass_reflections.with_base(base)
			node.set_surface_override_material(surface,_glass_materials[base])

static func _is_glass_material(material: StandardMaterial3D) -> bool:
	if material.transparency!=BaseMaterial3D.TRANSPARENCY_ALPHA:return false
	var name := material.resource_name.to_lower()
	var parts := name.split("__",false)
	return ("glass" in parts[1] or "vitre" in parts[1]) if parts.size()==3 else name.ends_with("_glass")

func _watch_glass_reflections() -> void:
	if glass_reflections and not glass_reflections.changed.is_connected(_schedule):
		glass_reflections.changed.connect(_schedule)

func _update_glass_break_sounds() -> void:
	if Engine.is_editor_hint() or not is_instance_valid(generated):return
	for pane in generated.find_children("VitreCassable", "StaticBody3D", true, false):
		if pane is GlassBreak:pane.set_break_sound(glass_break_sound,glass_break_volume_db)

func _box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new(); parent.add_child(body)
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size=size
	collision.shape=shape; collision.position=at; body.add_child(collision)

static func _junctions(edges: Dictionary) -> Dictionary:
	var graph := {}
	for key: String in edges:
		var slots := Layout.footprint(key,edges[key])
		var a: Vector2i = Layout.edge_info(key).a
		var b: Vector2i = Layout.edge_info(slots[-1]).b
		var direction := (b-a).sign()
		if not graph.has(a): graph[a]=[]
		if not graph.has(b): graph[b]=[]
		graph[a].append(direction); graph[b].append(-direction)
	return graph

static func _mask(graph: Dictionary, point: Vector2i, own: Vector2i, yaw: float) -> int:
	var mask := 0
	for direction: Vector2i in graph.get(point,[]):
		if direction == own: continue
		if direction == -own: mask |= 1
		else:
			var local := Basis(Vector3.UP,yaw).inverse()*Vector3(direction.x,0,direction.y)
			mask |= 2 if local.z>0 else 4
	return mask

func apply_plan(state: Dictionary) -> void:
	# A new resource identity also persists edits on an instanced map as overrides.
	var replacement := Layout.new(); replacement.restore(state); layout=replacement

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not scale.is_equal_approx(Vector3.ONE): warnings.append("Garder une echelle de 1 pour respecter les cases de 2 m.")
	if event_namespace.strip_edges().is_empty(): warnings.append("Renseigner un identifiant de carte unique pour les portes et evenements.")
	if layout:
		for level: int in layout.level_ids():
			for key: String in layout.invalid_double_doors(level): warnings.append("%s, porte double %s : deux bords alignes entre les memes pieces sont necessaires, sans T au milieu. Murs retablis en attendant." % [Layout.level_name(level),key])
	return warnings
