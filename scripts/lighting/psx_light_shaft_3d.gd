@tool
class_name PSXLightShaft3D
extends MeshInstance3D
## Reusable window-aligned polygon sheets. Local -Z points into the room.
const ShaftMaterial=preload("res://scripts/materials/psx_light_shaft_material.gd")
const DefaultMaterial: PSXLightShaftMaterial=preload("res://assets/materials/window_light_shaft.tres")
@export_enum("Faisceau large","Rayons etroits") var shape := 0:
	set(value):shape=value;notify_property_list_changed();_schedule()
@export var source_size := Vector2(1.2,1.5):
	set(value):source_size=value;_schedule()
@export_range(.1,30,.05,"suffix:m") var length := 4.0:
	set(value):length=value;_schedule()
@export var end_size := Vector2(1.8,1.7):
	set(value):end_size=value;_schedule()
## Decalage horizontal/vertical de l'extremite, dans le repere de la fenetre.
@export var end_offset := Vector2(0,-1.5):
	set(value):end_offset=value;_schedule()
@export_range(1,8,1) var ray_count := 3:
	set(value):ray_count=value;_schedule()
@export_range(.02,1,.01,"suffix:m") var ray_width := .15:
	set(value):ray_width=value;_schedule()
## Decoupage longitudinal pour l'interpolation affine et le tri des polygones.
@export_range(1,8,1) var segments := 4:
	set(value):segments=value;_schedule()
@export var shaft_material: PSXLightShaftMaterial:
	set(value):
		if shaft_material and shaft_material.changed.is_connected(_material_changed):shaft_material.changed.disconnect(_material_changed)
		shaft_material=value
		if shaft_material and not shaft_material.changed.is_connected(_material_changed):shaft_material.changed.connect(_material_changed)
		_schedule()
var _pending := false
func _enter_tree() -> void:add_to_group("psx_no_light_occluder")
func _ready() -> void:_rebuild()
func _schedule() -> void:
	if not is_inside_tree() or _pending:return
	_pending=true;call_deferred("_rebuild")
func _rebuild() -> void:
	if not is_inside_tree():
		_pending=false
		return
	if not shaft_material:
		# Set up the per-node default after instantiation. Duplicating a scripted
		# material in the property initializer can reenter ClassDB during load.
		_pending=true
		var material := ShaftMaterial.new()
		material.resource_name=DefaultMaterial.resource_name
		material.color=DefaultMaterial.color
		material.strength=DefaultMaterial.strength
		material.texture=DefaultMaterial.texture
		shaft_material=material
	_pending=false
	var start := Vector2(maxf(absf(source_size.x),.02),maxf(absf(source_size.y),.02))
	var end := Vector2(maxf(absf(end_size.x),.02),maxf(absf(end_size.y),.02))
	var tip := Vector3(end_offset.x,end_offset.y,-maxf(length,.1))
	var vertices := PackedVector3Array();var uvs := PackedVector2Array();var indices := PackedInt32Array()
	if shape==0:
		_sheet(vertices,uvs,indices,Vector3.ZERO,tip,Vector3(start.x*.5,0,0),Vector3(end.x*.5,0,0))
		_sheet(vertices,uvs,indices,Vector3.ZERO,tip,Vector3(0,start.y*.5,0),Vector3(0,end.y*.5,0))
	else:
		var count := clampi(ray_count,1,8)
		for ray in count:
			var fraction := (float(ray)+.5)/count-.5
			var origin := Vector3(fraction*start.x,0,0);var destination := tip+Vector3(fraction*end.x,0,0)
			var half := maxf(ray_width,.02)*.5
			_sheet(vertices,uvs,indices,origin,destination,Vector3(half,0,0),Vector3(half*end.x/start.x,0,0))
			_sheet(vertices,uvs,indices,origin,destination,Vector3(0,start.y*.5,0),Vector3(0,end.y*.5,0))
	var normals := PackedVector3Array();normals.resize(vertices.size());normals.fill(Vector3.UP)
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
	var geometry := mesh as ArrayMesh
	if not geometry:geometry=ArrayMesh.new()
	else:geometry.clear_surfaces()
	geometry.resource_name="PSX light shaft sheets";geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh=geometry;material_override=shaft_material;cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;_refresh_runtime()
func _sheet(vertices: PackedVector3Array,uvs: PackedVector2Array,indices: PackedInt32Array,origin: Vector3,tip: Vector3,start_half: Vector3,end_half: Vector3) -> void:
	var count := clampi(segments,1,8)
	for segment in count:
		var a := float(segment)/count;var b := float(segment+1)/count;var first := vertices.size()
		var ca := origin.lerp(tip,a);var cb := origin.lerp(tip,b);var ha := start_half.lerp(end_half,a);var hb := start_half.lerp(end_half,b)
		vertices.append_array(PackedVector3Array([ca-ha,ca+ha,cb+hb,cb-hb]));uvs.append_array(PackedVector2Array([Vector2(0,a),Vector2(1,a),Vector2(1,b),Vector2(0,b)]))
		# Explicit reverse windings keep the surface visible from either side in PSX.
		for index in [0,1,2,0,2,3,2,1,0,3,2,0]:indices.append(first+index)
func _material_changed() -> void:_refresh_runtime()
func _refresh_runtime() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():return
	var events := get_node_or_null("/root/WorldEvents");var game: Node=events.game_for(self) if events else null
	if not game or not is_instance_valid(game.psx_renderer) or not game.psx_renderer.native_geometry:return
	var renderer: Node=game.psx_renderer;renderer.entries=renderer.entries.filter(func(entry: Dictionary):return entry.node!=self)
	renderer.register_dynamic_geometry(self)
func _validate_property(property: Dictionary) -> void:
	if property.name in ["mesh","material_override","material_overlay","cast_shadow"] or String(property.name).begins_with("surface_material_override/"):property.usage&=~(PROPERTY_USAGE_EDITOR|PROPERTY_USAGE_STORAGE)
	if property.name in ["ray_count","ray_width"] and shape==0:property.usage&=~PROPERTY_USAGE_EDITOR
