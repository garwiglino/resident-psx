@tool
class_name PSXLamp3D
extends "res://scripts/psx_light_3d.gd"
## A single PSX light owns the fixture's illuminated surfaces and local sound.
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
const SurfaceShader=preload("res://shaders/psx_lamp_surface.gdshader")
const BINDING_VERSION := 2
@export_group("Modele de lampe")
@export var model_scene: PackedScene:
	set(value):
		if model_scene and model_scene.changed.is_connected(_schedule_model):model_scene.changed.disconnect(_schedule_model)
		model_scene=value
		if model_scene and not model_scene.changed.is_connected(_schedule_model):model_scene.changed.connect(_schedule_model)
		_schedule_model()
@export var model_position := Vector3.ZERO:
	set(value):model_position=value;_schedule_model()
@export var model_rotation_degrees := Vector3.ZERO:
	set(value):model_rotation_degrees=value;_schedule_model()
@export var model_scale := Vector3.ONE:
	set(value):model_scale=value;_schedule_model()
## Noms des materiaux lumineux du modele. Le reste conserve son vertex lighting.
@export var emissive_material_names := PackedStringArray(["M_light"]):
	set(value):emissive_material_names=value;_schedule_model()
## Facultatif : chemins de meshes depuis la racine du modele ; toutes leurs surfaces sont lumineuses.
@export var emissive_mesh_paths: Array[NodePath]=[]:
	set(value):emissive_mesh_paths=value;_schedule_model()
@export_group("Partie lumineuse")
@export var emission_uses_light_color := true
@export_color_no_alpha var emission_color := Color.WHITE
@export_range(0,4,.05) var emission_strength := 1.0
@export_group("Son localise")
@export var local_sound: AudioStream
@export var audio_enabled := true
@export var audio_loop := true
@export_range(-60,0,.5,"suffix:dB") var audio_volume_db := -26.0
@export_range(.1,8,.1,"suffix:m") var audio_unit_size := 1.0
@export_range(.5,40,.5,"suffix:m") var audio_max_distance := 8.0
@export var audio_offset := Vector3.ZERO
@export var audio_reverb := true
## Module le volume sans relancer la boucle ni recliquer l'enveloppe SPU.
@export var audio_follows_flicker := false
var model: Node3D
var local_audio: AudioStreamPlayer3D
var _emissive_meshes: Array[MeshInstance3D]=[]
var _surface_count := 0
var _model_pending := false
var _audio_signature: Array=[]
var _model_error := ""
var _binding_version := 0

static func _material_key(value: String) -> String:
	value=value.strip_edges().to_lower()
	# Blender's duplicate suffix does not change the material's purpose.
	var suffix := value.rsplit(".",true,1)
	if suffix.size()==2 and suffix[1].is_valid_int():value=suffix[0]
	return value.replace("_","").replace("-","").replace(" ","")

static func source_material_name(material: Material) -> String:
	if not material:return ""
	var source := String(material.get_meta("psx_source_material",""))
	if not source.is_empty():return source
	var name := material.resource_name
	# Compatibility with already-exported page materials. Preserve their unique
	# page names for kit overrides while resolving the original Blender name.
	var parts := name.split("__")
	if parts.size()>=3 and parts[0] in ["prop","stairs","door_01","door_glass","wall_door","wall_door_double","wall_loop","wall_loop_simple","wall_loop_window","window_glass","window_condemned","floor","ceiling"]:
		return "__".join(parts.slice(1,parts.size()-1))
	return name

func _matches_emissive_material(material: Material) -> bool:
	if not material:return false
	var source := _material_key(source_material_name(material))
	for name in emissive_material_names:
		if not name.strip_edges().is_empty() and (source==_material_key(name) or material.resource_name.nocasecmp_to(name.strip_edges())==0):return true
	return false

func _ready() -> void:
	process_priority=-20
	_rebuild_model()
	if not Engine.is_editor_hint():
		local_audio=AudioStreamPlayer3D.new();local_audio.name="SonLocalise";local_audio.max_polyphony=1;add_child(local_audio)
		Routing.set_category(local_audio,&"Ambience")
		local_audio.finished.connect(_audio_finished)
	_sync_visuals()

func _schedule_model() -> void:
	if not is_inside_tree() or _model_pending:return
	_model_pending=true;call_deferred("_rebuild_model")

func _contains_lamp(node: Node) -> bool:
	if node.has_method("get_surface_emission"):return true
	for child in node.get_children():
		if _contains_lamp(child):return true
	return false

func _rebuild_model() -> void:
	_model_pending=false
	if not is_inside_tree():return
	_binding_version=BINDING_VERSION
	if is_instance_valid(model):remove_child(model);model.free()
	model=null;_emissive_meshes=[];_surface_count=0;_model_error=""
	if model_scene:
		var instance := model_scene.instantiate()
		if not instance is Node3D or _contains_lamp(instance):
			_model_error="Model Scene doit contenir le modele seul, pas une lampe PSXLamp3D complete.";instance.free()
		else:
			model=instance;model.name="Modele";add_child(model)
			model.transform=Transform3D(Basis.from_euler(model_rotation_degrees*PI/180).scaled_local(model_scale),model_position)
			_bind_surfaces(model)
	_sync_visuals();update_configuration_warnings();update_gizmos()
	if not Engine.is_editor_hint():call_deferred("_register_runtime_geometry")

func _bind_surfaces(branch: Node) -> void:
	if branch is MeshInstance3D and branch.mesh:
		var indices := PackedInt32Array()
		var mesh_selected := model.get_path_to(branch) in emissive_mesh_paths
		var whole_override: Material=branch.material_override
		var whole_replacement: Material
		for surface in branch.mesh.get_surface_count():
			var source: Material=whole_override if whole_override else branch.get_active_material(surface)
			var selected := mesh_selected
			selected=selected or _matches_emissive_material(source)
			if not selected:continue
			if whole_replacement:indices.append(surface);continue
			var material: Material
			if DisplayServer.get_name()=="headless":
				# Dummy rendering cannot reflect spatial instance uniforms. Native
				# PSX rendering reads the same unlit metadata without a GPU material.
				var plain := StandardMaterial3D.new();plain.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				if source is StandardMaterial3D:plain.albedo_color=source.albedo_color;plain.albedo_texture=source.albedo_texture
				material=plain
			else:
				var shader_material := ShaderMaterial.new();shader_material.shader=SurfaceShader
				if source is StandardMaterial3D:
					shader_material.set_shader_parameter("tint",source.albedo_color)
					shader_material.set_shader_parameter("has_texture",source.albedo_texture!=null)
					if source.albedo_texture:shader_material.set_shader_parameter("albedo_texture",source.albedo_texture)
					shader_material.set_shader_parameter("alpha_scissor_threshold",source.alpha_scissor_threshold)
				elif source is ShaderMaterial:
					for parameter in ["tint","has_texture","albedo_texture"]:
						var value: Variant=source.get_shader_parameter(parameter)
						if value!=null:shader_material.set_shader_parameter(parameter,value)
				material=shader_material
			material.resource_name=source.resource_name if source else "M_light"
			if source:material.set_meta("psx_source_material",source_material_name(source))
			if whole_override:whole_replacement=material
			else:branch.set_surface_override_material(surface,material)
			indices.append(surface)
		if whole_replacement:branch.material_override=whole_replacement
		if not indices.is_empty():
			branch.set_meta("psx_unlit_light_id",get_instance_id());branch.set_meta("psx_unlit_surfaces",indices)
			_emissive_meshes.append(branch);_surface_count+=indices.size()
	for child in branch.get_children():_bind_surfaces(child)

func get_flicker_ratio() -> float:
	if not enabled or not is_visible_in_tree() or light_energy<=0:return 0.0
	return get_render_energy()/light_energy

func get_surface_emission() -> Color:
	var color := light_color if emission_uses_light_color else emission_color
	return color*(emission_strength*get_flicker_ratio())

func _sync_visuals() -> void:
	if DisplayServer.get_name()=="headless":return
	var color := get_surface_emission()
	for mesh in _emissive_meshes:
		if is_instance_valid(mesh):mesh.set_instance_shader_parameter("psx_lamp_color",color)

func _process(_delta: float) -> void:
	if _binding_version!=BINDING_VERSION and not _model_pending:_schedule_model()
	_sync_visuals()
	if not Engine.is_editor_hint():_sync_audio()

func _register_runtime_geometry() -> void:
	if not is_instance_valid(model):return
	var events := get_node_or_null("/root/WorldEvents")
	var game: Node=events.game_for(self) if events else null
	if not game or not is_instance_valid(game.psx_renderer):return
	var renderer: Node=game.psx_renderer
	for entry in renderer.entries:
		if is_instance_valid(entry.node) and (entry.node==model or model.is_ancestor_of(entry.node)):return
	renderer.register_dynamic_geometry(model)

func _sync_audio() -> void:
	if not is_instance_valid(local_audio):return
	var signature: Array=[local_sound,audio_loop]
	if signature!=_audio_signature:
		Routing.stop(local_audio);_audio_signature=signature
		local_audio.stream=null
		if local_sound:
			var stream: AudioStream=get_node("/root/PSXAudio").prepare(local_sound).duplicate()
			if stream.is_class("AudioStreamPSX"):stream.set("loop",audio_loop)
			elif stream is AudioStreamWAV:
				stream.loop_mode=AudioStreamWAV.LOOP_FORWARD if audio_loop else AudioStreamWAV.LOOP_DISABLED
				if audio_loop and stream.loop_end<=stream.loop_begin:stream.loop_end=roundi(stream.get_length()*stream.mix_rate)
			local_audio.stream=stream
			if local_audio.has_meta("one_shot_finished"):local_audio.remove_meta("one_shot_finished")
	local_audio.position=audio_offset;local_audio.unit_size=audio_unit_size;local_audio.max_distance=audio_max_distance
	var gain := get_flicker_ratio() if audio_follows_flicker else 1.0
	local_audio.volume_db=maxf(-80,audio_volume_db+linear_to_db(maxf(gain,.0001)))
	Routing.set_reverb_enabled(local_audio,audio_reverb)
	var powered := enabled and is_visible_in_tree() and light_energy>0 and audio_enabled and local_audio.stream!=null and _audio_in_range()
	if not powered:
		if local_audio.playing:Routing.stop(local_audio)
		if local_audio.has_meta("one_shot_finished"):local_audio.remove_meta("one_shot_finished")
	elif not local_audio.playing and (audio_loop or not local_audio.has_meta("one_shot_finished")):Routing.play(local_audio)

func _audio_in_range() -> bool:
	var listener: Node3D=get_viewport().get_audio_listener_3d()
	if not listener:listener=get_viewport().get_camera_3d()
	if not listener:return true
	# Far-away fixtures release their SPU voices. A small hysteresis prevents
	# repeated key-on/off when the listener stands exactly on the range edge.
	return listener.global_position.distance_to(local_audio.global_position)<=audio_max_distance+(.5 if local_audio.playing else 0.0)

func _audio_finished() -> void:
	if not audio_loop:local_audio.set_meta("one_shot_finished",true)

func _exit_tree() -> void:
	if is_instance_valid(local_audio):Routing.stop(local_audio)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not _model_error.is_empty():warnings.append(_model_error)
	elif not model_scene:warnings.append("Attribuer une scene de modele dans Model Scene.")
	elif _surface_count==0:warnings.append("Aucune surface lumineuse. Renseigner Emissive Material Names ou Emissive Mesh Paths.")
	return warnings

func get_editor_pick_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	if not is_instance_valid(model):return faces
	var meshes: Array[Node]=model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:meshes.push_front(model)
	for mesh: MeshInstance3D in meshes:
		if not mesh.mesh or not mesh.is_visible_in_tree():continue
		var local := global_transform.affine_inverse()*mesh.global_transform
		for point in mesh.mesh.get_faces():faces.append(local*point)
	return faces
