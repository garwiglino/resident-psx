@tool
extends Node2D
## PSX-like render path: CPU geometry, integer projection, Gouraud colours,
## affine 2D triangles and ordering table, with local player/weapon visibility correction.
const WIDTH := 320
const HEIGHT := 240
const UNITS := 1024.0
const FAR := 42.0
const NEAR := 0.08
const TexturePages = preload("res://scripts/texture_pages.gd")
const CharacterSkinning=preload("res://scripts/character_skinning.gd")
const UnlitMaterial=preload("res://scripts/materials/psx_unlit_material.gd")
const ShaftMaterial=preload("res://scripts/materials/psx_light_shaft_material.gd")
const ReflectiveMaterial=preload("res://scripts/materials/psx_reflective_material.gd")
const Grade=preload("res://scripts/levels/palette_grade.gd")
const AnimeStyle=preload("res://scripts/psx_anime_style.gd")
const DEFAULT_ANIME=preload("res://assets/rendering/anime_psx.tres")
const PREVIEW_PROPERTIES := ["vertex_snapping","affine_texture_strength","dithering","draw_distance","fog_enabled","fog_start","fog_end","fog_color","ordering_table_size","ambient_light_color","color_tint","saturation","brightness","anime_style"]
@export_group("Style anime PSX")
@export var anime_style: AnimeStyle=DEFAULT_ANIME
@export_group("Rendu PSX")
@export var vertex_snapping := true
## 1 = interpolation affine PSX. 0 = perspective corrigee. Entre les deux : fondu des UV.
@export_range(0.0,1.0,.01) var affine_texture_strength := 1.0
@export var dithering := true
@export var fog_enabled := true
@export var color_tint := Color.WHITE
@export_range(0,2,.01) var saturation := 1.0
@export_range(0,2,.01) var brightness := 1.0
@export_range(10.0,100.0,1.0,"suffix:m") var draw_distance := 42.0
@export_range(0.0,80.0,.5,"suffix:m") var fog_start := 9.0
@export_range(1.0,100.0,.5,"suffix:m") var fog_end := 33.0
## Couleur du depth cue PSX, calcule sur les sommets et quantifie en RGB555.
@export var fog_color := Color(.027,.044,.046)
@export_enum("256:256","512:512","1024:1024","2048:2048") var ordering_table_size := 1024
@export_group("Eclairage du niveau")
## Noir = aucune lumiere ambiante. Placer des PSXLight3D pour eclairer la carte.
@export var ambient_light_color := Color.BLACK
@export_group("Performances")
## 0 = sans limite. Le tick physique reste à 60 Hz.
@export_range(0,240,1,"suffix:FPS") var target_fps := 60
var native_geometry_enabled := true
var general_depth_correction := true
## UI item previews use the transparent viewport clear instead of a world fill.
var draw_background := true
var game: Node3D
var camera: Camera3D
var entries: Array[Dictionary] = []
var primitives: Array[Dictionary] = []
var blank: ImageTexture
var triangle_count := 0
var vertex_count := 0
var raster: ShaderMaterial
var _add_quarter_raster: ShaderMaterial
var _batch_canvases: Array[RID]=[]
var _effects_canvas := RID()
var inverse_camera := Transform3D.IDENTITY
var camera_matrix := Basis.IDENTITY
var view_position := Vector3.ZERO
var focal := 200.0
var torch_pos := Vector3.ZERO
var torch_dir := Vector3.FORWARD
var torch_on := true
var torch_color := Vector3.ONE
var torch_energy := 2.0
var torch_range := 16.0
var torch_outer_cos := cos(deg_to_rad(22.0))
var torch_inner_cos := cos(deg_to_rad(13.2))
var powered := false
var effects: Array[Dictionary]=[]
var last_process_us := 0
var last_draw_us := 0
var native_geometry: RefCounted
var batch_count := 0
var _render_settings: Array=[]
var atlas_texture: Texture2D
var texture_page_count := 0
var extended_texture_pages := false
var _has_reflections := false
var _mirror_viewport: SubViewport
var _mirror_canvas: Node2D
var _mirror_meshes: Array[ArrayMesh]=[]
var _mirror_entries: Array[Dictionary]=[]
var _perspective_meshes: Array[ArrayMesh]=[]
var shot_light_position := Vector3.ZERO
var shot_light_color := Vector3.ZERO
var shot_light_energy := 0.0
var shot_light_range := 1.0
var world_lights: Array[Dictionary]=[]
var _lighting_signature: Array=[]
var editor_preview := false
var _geometry_root: Node3D
var _lighting_root: Node3D
var _orthographic_size := 0.0
var _native_error_reported := false
var _player_depth_active := false
var _palette_signature: Array=[]
var _hover_unlit_ids := PackedInt64Array()
var geometry_revision := 0
var _clothing_entries: Array[Dictionary]=[]
var _glass_dust_emitters: Array[Node3D]=[]
var _local_aim_meshes: Array[MeshInstance3D]=[]
var _atlas_uniforms: Dictionary={}
var _frame_atlas_uniforms: Dictionary={}
var _frame_atlas_revision := -1
var _drawn_atlas_revision := -1
var _frame_uses_mesh := false
var _frame_has_cel := false
var _paused_redraw_pending := false
var _last_view_transform := Transform3D.IDENTITY
var _has_rendered_view := false
## An already-open editor can still own an older, non-reloadable native DLL.
## Do not run the full GDScript rasterizer on every preview frame in that case.
var native_restart_required: Dictionary={}

func _ready() -> void:
	set_process(false)

func setup(game_root: Node3D,active_camera: Camera3D) -> void:
	game=game_root
	camera=active_camera
	process_priority=100
	_geometry_root=game.level;_lighting_root=game
	_prepare_canvas()
	_sync_world_lights()
	cache_branch(game.level)
	cache_branch(game.player.motion.model)
	for enemy in game.enemies:cache_branch(enemy)
	for item in game.interactables:
		if item.node:cache_branch(item.node)
	_finish_geometry()
	set_process(true)

func set_active_camera(active_camera: Camera3D) -> void:
	if not is_instance_valid(active_camera):return
	camera=active_camera;_render_settings=[]

func setup_editor(scene_root: Node3D,preview_camera: Camera3D) -> void:
	# This reads the edited nodes directly; no scene, gameplay or audio is instantiated.
	editor_preview=true;game=null;camera=preview_camera
	_geometry_root=scene_root;_lighting_root=scene_root
	torch_on=false;powered=false;shot_light_energy=0
	_prepare_canvas()
	rebuild_editor_geometry()
	set_process(false)

func rebuild_editor_geometry() -> void:
	entries.clear();primitives.clear();_perspective_meshes.clear();_local_aim_meshes.clear();_glass_dust_emitters.clear()
	_sync_world_lights()
	cache_branch(_geometry_root)
	_finish_geometry()

func render_editor() -> void:
	if editor_preview and native_restart_required.is_empty():_process(0)

func _prepare_canvas() -> void:
	z_index=-100
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	var image := Image.create(1,1,false,Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	blank=ImageTexture.create_from_image(image)
	raster=ShaderMaterial.new()
	raster.shader=load("res://shaders/psx_raster.gdshader")
	_add_quarter_raster=ShaderMaterial.new();_add_quarter_raster.shader=load("res://shaders/psx_add_quarter.gdshader")
	material=raster
func _set_raster_parameter(parameter: StringName,value: Variant) -> void:
	raster.set_shader_parameter(parameter,value)
	if _add_quarter_raster:_add_quarter_raster.set_shader_parameter(parameter,value)

func _finish_geometry() -> void:
	geometry_revision+=1
	camera.cull_mask=0
	# Only the custom PSX raster path draws; keep the World3D for physics/cameras.
	get_viewport().disable_3d=true
	var atlas := TexturePages.build(entries,blank,color_tint,saturation,brightness)
	_palette_signature=[color_tint,saturation,brightness]
	_apply_atlas(atlas)
	if native_geometry_enabled and ClassDB.class_exists("PSXGeometry"):
		if not native_geometry:native_geometry=ClassDB.instantiate("PSXGeometry")
		_check_native_compatibility()
		if not native_geometry:apply_render_settings();return
		if native_geometry.has_method("set_world_lights") and int(native_geometry.get_statistics().version)>=11:
			_configure_native_geometry()
			var ambient := Grade.color(ambient_light_color,saturation)
			native_geometry.set_world_lights(world_lights,Vector3(ambient.r,ambient.g,ambient.b))
			if not native_geometry.has_method("get_player_depth_texture") and not _native_error_reported:
				push_warning("Redemarrer Godot pour activer la correction de profondeur du joueur et de son arme.")
				_native_error_reported=true
			elif not native_geometry.has_method("get_depth_texture") and not _native_error_reported:
				push_warning("Redemarrer Godot pour charger la profondeur globale et les lumieres bloquees par les murs (v15).")
				_native_error_reported=true
		else:
			if not _native_error_reported:push_error("Redemarrer Godot pour charger le rendu PSX natif et les expressions du visage.")
			_native_error_reported=true
			native_geometry=null
	apply_render_settings()

func register_weapon_geometry(visual: Node3D) -> void:
	register_dynamic_geometry(visual)

func register_dynamic_geometry(visual: Node3D) -> void:
	# New acquisitions rebuild the atlas once. Switching owned weapons only
	# changes visibility; their geometry is already registered.
	var source_viewport := _source_viewport()
	if visual.get_viewport()!=source_viewport:return
	entries=entries.filter(func(entry: Dictionary):return is_instance_valid(entry.node) and entry.node.get_viewport()==source_viewport)
	_local_aim_meshes.assign(_local_aim_meshes.filter(func(node: MeshInstance3D):return is_instance_valid(node)))
	cache_branch(visual)
	_rebuild_atlas()

func refresh_materials(branch: Node) -> void:
	if branch.get_viewport()!=_source_viewport():return
	for entry in entries:
		if not is_instance_valid(entry.node) or (entry.node!=branch and not branch.is_ancestor_of(entry.node)):continue
		var mat: Material=entry.node.get_active_material(int(entry.get("surface",0)))
		_cache_reflection(entry,mat)
		if mat is StandardMaterial3D:
			entry.unlit=mat is UnlitMaterial or mat is ShaftMaterial;entry.blend_mode=1 if mat is ShaftMaterial else 0
			entry.texture=mat.albedo_texture if mat.albedo_texture else blank
			entry.translucent=mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA
			entry.light_occluder=_is_world_surface(entry.node) and entry.skeleton==null and not entry.translucent and int(entry.get("unlit_light_id",0))==0
			entry.light_static_receiver=entry.light_occluder and not entry.unlit
			entry.source_color=mat.albedo_color;entry.source_emission=mat.emission if mat.emission_enabled else Color.BLACK
			if mat is ShaftMaterial:entry.source_color=mat.color*mat.strength
			entry.color=_material_color(entry.source_color,entry.texture!=blank)
			entry.emission=_material_color(entry.source_emission,entry.texture!=blank)
			if entry.fixed:
				for vertex in entry.static_positions.size():entry.static_light[vertex]=Vector3.ZERO if entry.unlit else bake_light(entry.static_positions[vertex],entry.static_normals[vertex],entry.color,entry.emission)
	_rebuild_atlas()

func _rebuild_atlas() -> void:
	geometry_revision+=1
	var atlas := TexturePages.build(entries,blank,color_tint,saturation,brightness)
	_palette_signature=[color_tint,saturation,brightness]
	_apply_atlas(atlas)
	_configure_native_geometry()
	request_paused_redraw()

func request_paused_redraw() -> void:
	if editor_preview or _paused_redraw_pending or not is_inside_tree() or not get_tree().paused:return
	_paused_redraw_pending=true
	call_deferred("_redraw_paused_frame")

func _redraw_paused_frame() -> void:
	if is_inside_tree() and get_tree().paused and is_instance_valid(game) and not game.is_queued_for_deletion():
		_render_scene(_has_rendered_view)
	_paused_redraw_pending=false

func set_hover_unlit(meshes: Array) -> void:
	var ids := PackedInt64Array()
	for mesh in meshes:
		if is_instance_valid(mesh) and mesh is MeshInstance3D and not ids.has(mesh.get_instance_id()):ids.append(mesh.get_instance_id())
	ids.sort()
	if ids==_hover_unlit_ids:return
	_hover_unlit_ids=ids
	if not native_geometry:return
	if native_geometry.has_method("set_unlit_overrides"):native_geometry.set_unlit_overrides(ids)
	else:_configure_native_geometry()

func _configure_native_geometry() -> void:
	if not native_geometry:return
	var source_viewport := _source_viewport()
	var valid := entries.filter(func(entry: Dictionary):return is_instance_valid(entry.node) and entry.node.get_viewport()==source_viewport)
	if native_geometry.has_method("set_unlit_overrides"):
		native_geometry.configure(valid);native_geometry.set_unlit_overrides(_hover_unlit_ids)
	else:
		# Support an editor still holding the previous non-reloadable DLL.
		# Texture pages and UVs stay intact; no atlas rebuild is needed on hover.
		var configured: Array=[]
		for entry in valid:
			if _hover_unlit_ids.has(entry.node.get_instance_id()):
				var temporary: Dictionary=entry.duplicate();temporary.unlit=true;configured.append(temporary)
			else:configured.append(entry)
		native_geometry.configure(configured)

func _apply_atlas(atlas: Dictionary) -> void:
	atlas_texture=atlas.texture;texture_page_count=atlas.page_count;extended_texture_pages=atlas.extended
	_has_reflections=atlas.has_reflections
	_mirror_entries.assign(entries.filter(func(entry: Dictionary):return entry.get("scene_reflection",0)>0))
	_clothing_entries.assign(entries.filter(func(entry: Dictionary):return entry.has("clothing_mesh")))
	# A paused frame can still be on screen when the next atlas is rebuilt.
	_atlas_uniforms={"texture_pages":atlas.pages.slice(0,TexturePages.PACKET_PAGES),
		"texture_page_lookup":atlas.lookup,"extended_texture_pages":extended_texture_pages,
		"reflections_enabled":_has_reflections}
	if native_geometry:_check_native_compatibility()

func _check_native_compatibility() -> void:
	var version := int(native_geometry.get_statistics().version)
	var required := _required_native_version()
	native_restart_required={}
	if version>=required:return
	native_restart_required={"loaded":version,"required":required}
	native_geometry=null
	if not _native_error_reported:
		push_warning("Moteur PSX v%d encore charge ; v%d requise. Enregistrer les scenes puis rouvrir Godot. L'apercu PSX est suspendu pour eviter un rendu de secours lent." % [version,required])
		_native_error_reported=true

func _required_native_version() -> int:
	if anime_style and anime_style.is_active():return 29
	if _has_reflections:return 27
	for entry in entries:
		if entry.get("ignore_self_shadow",false):return 25
	for entry in entries:
		if int(entry.get("blend_mode",0))==1:return 21
	for entry in entries:
		if entry.get("unlit",false):return 20
	for entry in entries:
		if not entry.get("torch_receiver",true):return 19
	for entry in entries:
		if int(entry.get("unlit_light_id",0))!=0:return 17
	return 16 if extended_texture_pages else 11

func _sync_world_lights() -> void:
	var lights: Array[Dictionary]=[]
	var source_viewport := _source_viewport()
	for light in get_tree().get_nodes_in_group("psx_world_lights"):
		if not is_instance_valid(_lighting_root) or light.get_viewport()!=source_viewport:continue
		if (_lighting_root!=light and not _lighting_root.is_ancestor_of(light)) or not light.enabled or not light.is_visible_in_tree():continue
		if light.light_energy<=0:continue
		var half_angle := deg_to_rad(float(light.spot_angle_degrees))*.5
		var outer_cos := cos(half_angle)
		var kind: int=light.light_type
		var light_color := Grade.color(light.light_color,saturation)
		var fixture_emission := Grade.color(light.get_surface_emission(),saturation) if light.has_method("get_surface_emission") else Color.BLACK
		lights.append({"id":light.get_instance_id(),"position":light.global_position if kind!=2 else Vector3.ZERO,"color":Vector3(light_color.r,light_color.g,light_color.b),
		 "fixture_emission":_rgb(fixture_emission),
		 "energy":light.get_render_energy(),"range":light.light_range if kind!=2 else 1.0,"type":kind,"direction":-light.global_basis.z.normalized() if kind!=0 else Vector3.FORWARD,
		 "outer_cos":outer_cos if kind==1 else 0.0,"inner_cos":maxf(cos(half_angle*(1.0-float(light.spot_softness))),outer_cos+.000001) if kind==1 else 1.0})
	var signature: Array=[ambient_light_color,saturation,lights]
	if signature==_lighting_signature:return
	_lighting_signature=signature;world_lights=lights
	if native_geometry:
		var ambient := Grade.color(ambient_light_color,saturation)
		native_geometry.set_world_lights(world_lights,Vector3(ambient.r,ambient.g,ambient.b))
	else:
		for entry in entries:
			if not entry.fixed or entry.get("unlit",false) or int(entry.get("unlit_light_id",0))!=0:continue
			for vertex in entry.static_positions.size():
				entry.static_light[vertex]=bake_light(entry.static_positions[vertex],entry.static_normals[vertex],entry.color,entry.emission)

func apply_render_settings() -> void:
	if _palette_signature!=[color_tint,saturation,brightness] and not entries.is_empty(): _refresh_grading()
	if not editor_preview:Engine.max_fps=target_fps
	_set_raster_parameter("dither_enabled",dithering)
	_set_raster_parameter("affine_texture_strength",affine_texture_strength)
	_set_raster_parameter("cel_orthographic_size",_orthographic_size)
	_configure_cel_raster(raster)
	if is_instance_valid(_mirror_canvas):
		_configure_cel_raster(_mirror_canvas.material)
		_mirror_canvas.material.set_shader_parameter("cel_orthographic_size",_orthographic_size)
	if not editor_preview:game.materials.snap_enabled=vertex_snapping
	if native_geometry:
		if native_geometry.has_method("set_anime_settings"):
			var style := anime_style.native_settings() if anime_style else {"enabled":false}
			if native_geometry.get_statistics().version<28:style.enabled=false
			native_geometry.set_anime_settings(style)
		native_geometry.set_render_settings({"far_clip":minf(draw_distance,camera.far),"near_clip":camera.near,
			"depth_correction":general_depth_correction,
			"fog_start":fog_start if fog_enabled else draw_distance+1,"fog_end":maxf(fog_end,fog_start+.001) if fog_enabled else draw_distance+2,
			"fog_color":_rgb(Grade.color(fog_color,saturation)),"ordering_buckets":ordering_table_size,"orthographic_size":_orthographic_size,"affine_texture_strength":affine_texture_strength})
	_render_settings=_render_signature()

func _configure_cel_raster(shader: ShaderMaterial) -> void:
	if not anime_style:return
	var three_tones := anime_style.tones==1
	var darkness := anime_style.darkness_threshold
	var middle := maxf(darkness+.0001,anime_style.middle_threshold if three_tones else anime_style.light_threshold)
	shader.set_shader_parameter("cel_thresholds",Vector3(darkness,middle,maxf(middle+.0001,anime_style.highlight_threshold)))
	shader.set_shader_parameter("cel_levels",Vector3(anime_style.shadow_level,anime_style.middle_level,anime_style.light_level))
	shader.set_shader_parameter("cel_shadow_tint",_rgb(anime_style.shadow_tint))
	shader.set_shader_parameter("cel_light_tint",_rgb(anime_style.light_tint))
	shader.set_shader_parameter("cel_strength",Vector2(anime_style.strength,anime_style.world_strength))
	shader.set_shader_parameter("cel_darkness_multiplier",anime_style.darkness_multiplier)
	shader.set_shader_parameter("cel_hue_retention",anime_style.light_color_retention)
	shader.set_shader_parameter("cel_three_tones",three_tones)
	shader.set_shader_parameter("cel_fog_color",_rgb(Grade.color(fog_color,saturation)))
	shader.set_shader_parameter("cel_fog_range",Vector2(fog_start,1.0/maxf(fog_end-fog_start,.001)) if fog_enabled else Vector2.ZERO)

func _render_signature() -> Array:
	return [vertex_snapping,affine_texture_strength,dithering,draw_distance,fog_enabled,fog_start,fog_end,fog_color,ordering_table_size,target_fps,camera.near,camera.far,_orthographic_size,color_tint,saturation,brightness,general_depth_correction,anime_style.signature() if anime_style else []]

static func _rgb(color: Color) -> Vector3: return Vector3(color.r,color.g,color.b)

func _material_color(source: Color, textured: bool) -> Color:
	return Grade.color(source,saturation,Color.WHITE if textured else color_tint,1.0 if textured else brightness)

func _refresh_grading() -> void:
	for entry in entries:
		entry.color=_material_color(entry.source_color,entry.texture!=blank)
		entry.emission=_material_color(entry.source_emission,entry.texture!=blank)
		if entry.fixed and not entry.get("unlit",false) and int(entry.get("unlit_light_id",0))==0:
			for i in entry.static_positions.size(): entry.static_light[i]=bake_light(entry.static_positions[i],entry.static_normals[i],entry.color,entry.emission)
	_rebuild_atlas()

func cache_branch(node: Node) -> void:
	if node is Node3D and node.has_method("update_glass_dust") and not node in _glass_dust_emitters:
		_glass_dust_emitters.append(node)
	if node is Viewport:return
	if node is MeshInstance3D:
		cache_mesh(node)
	elif node is Label3D and not editor_preview:
		node.visible=false
	for child in node.get_children():
		cache_branch(child)

func _source_viewport() -> Viewport:
	return _geometry_root.get_viewport() if is_instance_valid(_geometry_root) else get_viewport()

func _uses_player_depth(node: Node) -> bool:
	if is_instance_valid(game) and (node==game.player or game.player.is_ancestor_of(node)):return true
	# Editor preview reads the authored player directly, without starting gameplay.
	var branch := node
	while branch:
		var source: Script=branch.get_script()
		if branch.is_in_group("player") or (source and source.resource_path=="res://scripts/player.gd"):return true
		branch=branch.get_parent()
	return false

func _is_anime_character(node: Node) -> bool:
	var branch := node
	while branch:
		if branch is CharacterBody3D or branch.is_in_group("psx_anime_character"):return true
		branch=branch.get_parent()
	return false

func _is_moving_branch(node: Node) -> bool:
	var branch := node
	while branch:
		if branch.is_in_group("psx_dynamic_geometry") or branch is CharacterBody3D or branch is RigidBody3D or branch is AnimatableBody3D:return true
		if branch==_geometry_root:break
		branch=branch.get_parent()
	return false

func _is_world_surface(node: Node) -> bool:
	if node.is_in_group("psx_sprite") or not _geometry_root.is_ancestor_of(node): return false
	var branch := node
	while branch:
		if branch.is_in_group("psx_no_light_occluder"): return false
		if branch is CharacterBody3D: return false
		if branch==_geometry_root: break
		branch=branch.get_parent()
	return true

func cache_mesh(node: MeshInstance3D) -> void:
	if not node.mesh or node.mesh is ImmediateMesh:
		return
	for entry in entries:
		if entry.node==node:return
	var local_player := _uses_player_depth(node)
	var skinned := node.skin!=null and not node.skeleton.is_empty()
	if not editor_preview and local_player and skinned:_local_aim_meshes.append(node)
	for surface in node.mesh.get_surface_count():
		var unlit_light_id: int=int(node.get_meta("psx_unlit_light_id",0)) if surface in node.get_meta("psx_unlit_surfaces",PackedInt32Array()) else 0
		var arrays := node.mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		var mat: Material=node.get_active_material(surface)
		var unlit := mat is UnlitMaterial or mat is ShaftMaterial
		var tint := Color.WHITE
		var emission := Color.BLACK
		var texture: Texture2D=blank
		if mat is ShaderMaterial:
			tint=mat.get_shader_parameter("tint")
			var e = mat.get_shader_parameter("emission_color")
			if e is Vector3:
				emission=Color(e.x,e.y,e.z)
			elif e is Color:
				emission=e
			if mat.get_shader_parameter("has_texture"):
				texture=mat.get_shader_parameter("albedo_texture")
		elif mat is StandardMaterial3D:
			tint=mat.albedo_color
			if mat is ShaftMaterial:tint=mat.color*mat.strength
			if mat.emission_enabled:
				emission=mat.emission
			if mat.albedo_texture:
				texture=mat.albedo_texture
		var skeleton: Skeleton3D=null
		var bind_indices := PackedInt32Array()
		var binds: Array[Transform3D]=[]
		if node.skin and not node.skeleton.is_empty():
			skeleton=node.get_node_or_null(node.skeleton)
			if skeleton:
				for b in node.skin.get_bind_count():
					var bone := node.skin.get_bind_bone(b)
					if bone<0:
						bone=skeleton.find_bone(node.skin.get_bind_name(b))
					bind_indices.append(bone)
					binds.append(node.skin.get_bind_pose(b))
		var static_positions := PackedVector3Array()
		var source_color := tint; var source_emission := emission
		tint=_material_color(tint,texture!=blank); emission=_material_color(emission,texture!=blank)
		var static_normals := PackedVector3Array()
		var static_light := PackedVector3Array()
		# Editor transforms stay live, including parents moved by a gizmo.
		var fixed: bool=not editor_preview and skeleton==null and _geometry_root.is_ancestor_of(node) and not _is_moving_branch(node)
		if fixed:
			var normal_matrix := node.global_basis.inverse().transposed()
			var ns: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
			for i in vertices.size():
				var p: Vector3=(node.global_transform*vertices[i]*UNITS).round()/UNITS
				var n: Vector3=(normal_matrix*(ns[i] if i<ns.size() else Vector3.UP)).normalized()
				static_positions.append(p)
				static_normals.append(n)
				static_light.append(Vector3.ZERO if unlit or unlit_light_id else bake_light(p,n,tint,emission))
		var face_part: int=TexturePages.FaceTextures.part(node.mesh.surface_get_material(surface))
		var translucent: bool=mat is StandardMaterial3D and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA
		var world_surface := _is_world_surface(node) and skeleton==null
		var skin_data := CharacterSkinning.restore(node,arrays,bind_indices,skeleton)
		entries.append({"node":node,"surface":surface,"face_part":face_part,"vertices":vertices,"normals":arrays[Mesh.ARRAY_NORMAL],"uvs":arrays[Mesh.ARRAY_TEX_UV],"indices":indices,
			"color":tint,"emission":emission,"source_color":source_color,"source_emission":source_emission,"texture":texture,"skeleton":skeleton,"bind_indices":bind_indices,"binds":binds,
			"bones":skin_data.bones,"weights":skin_data.weights,"aabb":node.mesh.get_aabb(),
			"fixed":fixed,"sprite":node.is_in_group("psx_sprite"),"translucent":translucent,"anime_character":_is_anime_character(node),
			"ignore_self_shadow":_is_modular_door_leaf(node),
			"light_occluder":world_surface and not translucent and unlit_light_id==0,"light_static_receiver":world_surface and not unlit and unlit_light_id==0,"unlit_light_id":unlit_light_id,"unlit":unlit,"blend_mode":1 if mat is ShaftMaterial else 0,
			"torch_receiver":not local_player,"depth_correct":local_player,"static_positions":static_positions,"static_normals":static_normals,"static_light":static_light})
		_cache_reflection(entries.back(),mat)
		if node.has_meta(&"psx_clothing_source_mesh"):
			entries.back()["clothing_mesh"]=node.mesh

func _cache_reflection(entry: Dictionary, mat: Material) -> void:
	entry.erase("reflection_texture")
	entry.erase("scene_reflection")
	if not mat is ReflectiveMaterial or entry.sprite:
		return
	if mat.reflection_texture and mat.reflection_strength>0:entry.reflection_texture=mat.reflection_texture
	if not entry.skeleton and mat.scene_reflection>0 and (mat.reflection_projection==1 or mat.reflection_projection==2):
		entry.scene_reflection=mat.scene_reflection
	if not entry.has("reflection_texture") and entry.get("scene_reflection",0)<=0:return
	entry.reflection_projection=int(mat.reflection_projection)
	entry.reflection_strength=mat.reflection_strength
	entry.reflection_light_response=mat.reflection_light_response
	entry.reflection_motion=mat.reflection_motion
	entry.reflection_width=mat.reflection_width
	entry.reflection_scale=mat.reflection_scale
	entry.reflection_angle=deg_to_rad(mat.reflection_angle)
	entry.reflection_offset=mat.reflection_offset
	if entry.has("reflection_bounds"):
		return
	var positions: PackedVector3Array=entry.vertices
	if positions.is_empty():
		entry.reflection_bounds=AABB()
		return
	var bounds := AABB(positions[0],Vector3.ZERO)
	for position in positions:
		bounds=bounds.expand(position)
	entry.reflection_bounds=bounds

func _is_modular_door_leaf(node: Node) -> bool:
	var branch := node.get_parent()
	while branch and branch != _geometry_root:
		if branch.is_in_group("psx_door_leaf_lighting"): return true
		branch = branch.get_parent()
	return false

func _sync_clothing_geometry() -> void:
	var changed := false
	for entry in _clothing_entries:
		var node: MeshInstance3D=entry.node
		if not is_instance_valid(node) or not node.mesh or node.mesh==entry.clothing_mesh:
			continue
		var arrays := node.mesh.surface_get_arrays(entry.surface)
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for index in entry.vertices.size():
				indices.append(index)
		entry.indices=indices
		entry.clothing_mesh=node.mesh
		changed=true
	if changed:
		_configure_native_geometry()

func _update_shot_visuals() -> void:
	var weapon=game.player.motion.weapon
	shot_light_energy=0.0
	if weapon:
		weapon.update_flash(camera)
		_set_raster_parameter("flash_opacity",weapon.flash_opacity)
		if weapon.flash_time_left>0:
			shot_light_position=weapon.flash_position
			shot_light_color=_rgb(Grade.color(weapon.flash_light_color,saturation))
			shot_light_range=weapon.flash_light_range
			shot_light_energy=weapon.flash_light_energy*clampf(weapon.flash_time_left/maxf(weapon.flash_duration,.001),0,1)
	if native_geometry:native_geometry.set_shot_light(shot_light_position,shot_light_color,shot_light_energy,shot_light_range)

func _update_flashlight() -> void:
	var player=game.player
	var mount: Transform3D=player.get_flashlight_transform()
	torch_pos=mount.origin
	torch_dir=mount.basis.z.normalized()
	torch_on=player.flashlight
	torch_color=_rgb(Grade.color(player.flashlight_color,saturation))
	torch_energy=player.flashlight_energy
	torch_range=maxf(player.flashlight_range,.001)
	var half_angle := deg_to_rad(player.flashlight_cone_degrees)*.5
	torch_outer_cos=cos(half_angle)
	torch_inner_cos=cos(half_angle*.6)
	if native_geometry:
		native_geometry.set_torch_light(torch_pos,torch_dir,torch_color,torch_energy,torch_range,torch_outer_cos,torch_inner_cos)

func _process(_delta: float) -> void:
	_render_scene(false)

func _render_scene(keep_view: bool) -> void:
	if Engine.is_editor_hint() and not editor_preview:return
	if editor_preview and not native_restart_required.is_empty():return
	var start_us := Time.get_ticks_usec()
	if not is_instance_valid(camera):
		return
	_sync_clothing_geometry()
	_orthographic_size=camera.size if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else 0.0
	if _render_signature()!=_render_settings:
		apply_render_settings()
	_sync_world_lights()
	var view_transform := _last_view_transform
	if not keep_view:
		view_transform=game.player.get_render_camera_transform() if not editor_preview and camera==game.player.camera else camera.get_camera_transform()
		_last_view_transform=view_transform
		_has_rendered_view=true
	view_position=view_transform.origin
	inverse_camera=view_transform.affine_inverse()
	camera_matrix=inverse_camera.basis
	for col in 3:
		camera_matrix[col]=(camera_matrix[col]*4096.0).round()/4096.0
	focal=HEIGHT/_orthographic_size if _orthographic_size>0 else 120.0/tan(deg_to_rad(camera.fov)*.5)
	if not editor_preview:
		_update_flashlight();powered=game.power;_update_shot_visuals()
		for emitter in _glass_dust_emitters:
			if is_instance_valid(emitter):emitter.update_glass_dust(view_transform.basis)
	var hide_local_meshes: bool=not editor_preview and camera==game.player.camera and game.player.should_hide_aim_meshes(view_transform)
	primitives.clear()
	vertex_count=0
	_frame_has_cel=false
	if native_geometry:
		if not _mirror_entries.is_empty():_render_mirror(view_transform)
		else:_set_raster_parameter("mirror_enabled",false)
		var hidden: Array[MeshInstance3D]=[]
		if hide_local_meshes:hidden=_hide_local_aim_meshes()
		primitives.assign(native_geometry.frame(view_transform,camera.fov,torch_on,powered,vertex_snapping))
		for node in hidden:node.show()
		_frame_has_cel=not primitives.is_empty() and primitives[0].get("cel_channels",false)
		_set_raster_parameter("cel_enabled",_frame_has_cel)
		if _has_reflections:
			_set_raster_parameter("reflection_light_colors",native_geometry.get_reflection_light_colors())
		var statistics: Dictionary=native_geometry.get_statistics()
		triangle_count=statistics.triangles
		vertex_count=statistics.vertices
		batch_count=statistics.batches
		_player_depth_active=int(statistics.get("player_depth_pixels",0))>0 and native_geometry.has_method("get_player_depth_texture")
		_set_raster_parameter("player_depth_correction",_player_depth_active)
		_set_raster_parameter("world_depth_correction",_player_depth_active and statistics.get("general_depth",false))
		if _player_depth_active:_set_raster_parameter("player_depth_texture",native_geometry.get_player_depth_texture())
		_prepare_perspective_meshes()
		last_process_us=Time.get_ticks_usec()-start_us
		_queue_frame()
		return
	_player_depth_active=false
	_set_raster_parameter("cel_enabled",false)
	_set_raster_parameter("mirror_enabled",false)
	_set_raster_parameter("player_depth_correction",false)
	_set_raster_parameter("world_depth_correction",false)
	var hidden: Array[MeshInstance3D]=[]
	if hide_local_meshes:hidden=_hide_local_aim_meshes()
	for entry in entries:
		if is_instance_valid(entry.node) and entry.node.is_visible_in_tree():
			transform_entry(entry)
	for node in hidden:node.show()
	primitives.sort_custom(func(a: Dictionary,b: Dictionary): return a.bucket>b.bucket if a.bucket!=b.bucket else a.order>b.order)
	_prepare_perspective_meshes()
	triangle_count=primitives.size()
	last_process_us=Time.get_ticks_usec()-start_us
	_queue_frame()

func _hide_local_aim_meshes() -> Array[MeshInstance3D]:
	# This only affects the player's rendered view. World effects, other
	# cameras and the mirror pass keep their normal scene visibility.
	var hidden: Array[MeshInstance3D]=[]
	for node in _local_aim_meshes:
		if not is_instance_valid(node) or not node.is_visible_in_tree():continue
		node.hide()
		hidden.append(node)
	return hidden

func _queue_frame() -> void:
	_frame_atlas_uniforms=_atlas_uniforms
	_frame_atlas_revision=geometry_revision
	_frame_uses_mesh=extended_texture_pages or _has_reflections or _frame_has_cel or affine_texture_strength<1.0 or _player_depth_active
	queue_redraw()

func _render_mirror(view: Transform3D) -> void:
	# One reflected view per frame. Only authored planar mirrors request it.
	var mirror: Dictionary={}
	var closest := INF
	for entry in _mirror_entries:
		if entry.get("scene_reflection",0.0)<=0.0 or not is_instance_valid(entry.node) or not entry.node.is_visible_in_tree():
			continue
		var node: MeshInstance3D=entry.node
		if _hover_unlit_ids.has(node.get_instance_id()):continue
		var bounds: AABB=entry.reflection_bounds
		var center := node.global_transform*bounds.get_center()
		var axis := Vector3.BACK if entry.reflection_projection==1 else Vector3.UP
		var normal := (node.global_basis.inverse().transposed()*axis).normalized()
		if absf(normal.dot(view.origin-center))<camera.near:continue
		var relative := inverse_camera*center
		var depth := -relative.z
		var scale := node.global_basis.get_scale().abs()
		var radius := bounds.size.length()*.5*scale[scale.max_axis_index()]
		var extent := 1.0 if _orthographic_size>0 else maxf(depth,0)
		if depth+radius<camera.near or depth-radius>draw_distance or absf(relative.x)>extent*160/focal+radius or absf(relative.y)>extent*120/focal+radius:
			continue
		var distance := center.distance_squared_to(view.origin)
		if distance<closest:
			closest=distance
			mirror=entry
	if mirror.is_empty():
		native_geometry.set_mirror_surface(0,-1)
		_set_raster_parameter("mirror_enabled",false)
		return
	var node: MeshInstance3D=mirror.node
	var bounds: AABB=mirror.reflection_bounds
	var center := node.global_transform*bounds.get_center()
	var normal := (node.global_basis.inverse().transposed()*(Vector3.BACK if mirror.reflection_projection==1 else Vector3.UP)).normalized()
	if normal.dot(view.origin-center)<0:normal=-normal
	var reflected := view
	reflected.origin-=2.0*normal*normal.dot(view.origin-center)
	for axis in 3:reflected.basis[axis]-=2.0*normal*normal.dot(view.basis[axis])
	# Keep the virtual camera right-handed. The texture is sampled horizontally
	# flipped to compensate for the extra axis reversal.
	reflected.basis.x=-reflected.basis.x
	if not is_instance_valid(_mirror_viewport):_create_mirror_viewport()
	native_geometry.set_mirror_surface(node.get_instance_id(),mirror.surface)
	var packets: Array=native_geometry.mirror_frame(reflected,camera.fov,torch_on,powered,vertex_snapping,
		center,normal)
	var canvas := _mirror_canvas.get_canvas_item()
	var shader := _mirror_canvas.material as ShaderMaterial
	shader.set_shader_parameter("texture_page_lookup",_atlas_uniforms.texture_page_lookup)
	shader.set_shader_parameter("dither_enabled",dithering)
	var depth: Texture2D=native_geometry.get_mirror_depth_texture()
	shader.set_shader_parameter("player_depth_correction",depth!=null)
	shader.set_shader_parameter("world_depth_correction",true)
	shader.set_shader_parameter("affine_texture_strength",affine_texture_strength)
	shader.set_shader_parameter("explicit_perspective_uvs",true)
	var mirror_has_cel: bool=not packets.is_empty() and packets[0].get("cel_channels",false)
	shader.set_shader_parameter("cel_enabled",mirror_has_cel)
	if depth:shader.set_shader_parameter("player_depth_texture",depth)
	RenderingServer.canvas_item_clear(canvas)
	while _mirror_meshes.size()<packets.size():_mirror_meshes.append(ArrayMesh.new())
	for index in packets.size():
		var packet: Dictionary=packets[index]
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=packet.points
		arrays[Mesh.ARRAY_COLOR]=packet.colors
		arrays[Mesh.ARRAY_TEX_UV]=packet.uvs
		arrays[Mesh.ARRAY_INDEX]=packet.indices
		arrays[Mesh.ARRAY_CUSTOM0]=packet.depth_channels
		arrays[Mesh.ARRAY_CUSTOM1]=packet.perspective_uvs
		var mesh := _mirror_meshes[index]
		mesh.clear_surfaces()
		var uv_format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT if mirror_has_cel else Mesh.ARRAY_CUSTOM_RG_FLOAT
		var flags := Mesh.ARRAY_FLAG_USE_2D_VERTICES|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(uv_format<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
		RenderingServer.canvas_item_add_mesh(canvas,mesh.get_rid(),Transform2D.IDENTITY,Color.WHITE,packet.texture.get_rid())
	_mirror_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	_set_raster_parameter("mirror_texture",_mirror_viewport.get_texture())
	_set_raster_parameter("mirror_mix",mirror.scene_reflection)
	_set_raster_parameter("mirror_enabled",true)

func _create_mirror_viewport() -> void:
	_mirror_viewport=SubViewport.new()
	_mirror_viewport.size=Vector2i(160,120)
	_mirror_viewport.disable_3d=true
	_mirror_viewport.world_2d=World2D.new()
	_mirror_viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	add_child(_mirror_viewport)
	_mirror_viewport.canvas_transform=Transform2D(0,Vector2(.5,.5),0,Vector2.ZERO)
	_mirror_canvas=Node2D.new()
	_mirror_canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var shader := ShaderMaterial.new()
	shader.shader=raster.shader
	shader.set_shader_parameter("extended_texture_pages",true)
	shader.set_shader_parameter("raster_pixel_scale",2.0)
	_configure_cel_raster(shader)
	shader.set_shader_parameter("cel_orthographic_size",_orthographic_size)
	_mirror_canvas.material=shader
	_mirror_viewport.add_child(_mirror_canvas)

func transform_entry(entry: Dictionary) -> void:
	var node: MeshInstance3D=entry.node
	var transform := node.global_transform
	var center: Vector3=transform*entry.aabb.get_center()
	var scale_factor: float=transform.basis.get_scale().max_axis_index()
	var radius: float=entry.aabb.size.length()*.5*transform.basis.get_scale()[int(scale_factor)]
	var c: Vector3=inverse_camera*center
	var depth := -c.z
	var extent := 1.0 if _orthographic_size>0 else depth
	if depth+radius<camera.near or depth-radius>minf(draw_distance,camera.far) or absf(c.x)>extent*(160.0/focal)+radius or absf(c.y)>extent*(120.0/focal)+radius:
		return
	var skin_transforms: Array[Transform3D]=[]
	var skeleton: Skeleton3D=entry.skeleton
	if skeleton:
		for b in entry.binds.size():
			skin_transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(entry.bind_indices[b])*entry.binds[b])
	var vertices: PackedVector3Array=entry.vertices
	var normals: PackedVector3Array=entry.normals if entry.normals!=null else PackedVector3Array()
	var uvs: PackedVector2Array=entry.uvs if entry.uvs!=null else PackedVector2Array()
	var view_positions := PackedVector3Array()
	var lighting := PackedColorArray()
	var texcoords := PackedVector2Array()
	view_positions.resize(vertices.size())
	lighting.resize(vertices.size())
	texcoords.resize(vertices.size())
	var normal_matrix := transform.basis.inverse().transposed()
	var texture_size: Vector2=entry.logical_texture_size
	var additive: bool=int(entry.get("blend_mode",0))==1
	var face: int=entry.get("face_part",0)
	var face_frame: int=clampi(int(node.get_meta("psx_face_top_frame" if face==1 else "psx_face_bottom_frame",0)),0,7) if face else 0
	var page_index: int=entry.face_pages[face_frame/4] if face else entry.page_index
	var texture_page: int=(int(entry.texture_page)&~31)|(page_index&31)
	var unlit_light_id: int=int(entry.get("unlit_light_id",0))
	var hovered := _hover_unlit_ids.has(node.get_instance_id())
	var reflection_page: int=0 if hovered else entry.get("reflection_page",0)
	var reflection_size := Vector2.ONE
	var view_to_local := Basis.IDENTITY
	var reflection_uvs := PackedVector2Array()
	var reflection_amounts := PackedFloat32Array()
	if reflection_page:
		var page: Vector4=entry.atlas_pages[reflection_page]
		reflection_size=Vector2(page.z,page.w)
		view_to_local=transform.basis.orthonormalized().transposed()*_last_view_transform.basis
		reflection_uvs.resize(vertices.size())
		reflection_amounts.resize(vertices.size())
	var unlit: bool=entry.get("unlit",false) or hovered
	var unlit_color := _rgb(entry.color) if unlit else Vector3.ZERO
	if unlit_light_id and not hovered:
		for light in world_lights:
			if int(light.id)==unlit_light_id:unlit_color=Vector3(entry.color.r,entry.color.g,entry.color.b)*Vector3(light.get("fixture_emission",Vector3.ZERO));break
	for v in vertices.size():
		var p: Vector3=vertices[v]
		var n: Vector3=normals[v] if not normals.is_empty() else Vector3.UP
		var world_pos := Vector3.ZERO
		var world_normal := Vector3.ZERO
		if entry.fixed:
			world_pos=entry.static_positions[v]
			world_normal=entry.static_normals[v]
		elif skeleton:
			var stride: int=entry.bones.size()/vertices.size()
			for weight_index in stride:
				var bone: int=entry.bones[v*stride+weight_index]
				var weight: float=entry.weights[v*stride+weight_index]
				if weight>0 and bone<skin_transforms.size():
					world_pos+=(skin_transforms[bone]*p)*weight
					world_normal+=(skin_transforms[bone].basis*n)*weight
		else:
			world_pos=transform*p
			world_normal=normal_matrix*n
		world_pos=(world_pos*UNITS).round()/UNITS
		world_normal=world_normal.normalized()
		var view_pos := camera_matrix*(world_pos-view_position)
		view_pos=(view_pos*UNITS).floor()/UNITS
		view_positions[v]=view_pos
		var base_light: Vector3=unlit_color if unlit or unlit_light_id else (entry.static_light[v] if entry.fixed else bake_light(world_pos,world_normal,entry.color,entry.emission))
		var lit := _vertex_light(world_pos,world_normal,entry.color,base_light,unlit or unlit_light_id!=0,entry.get("torch_receiver",true))
		var fog := _fog_weight(-view_pos.z)
		lighting[v]=_packet_color(lit,fog,entry.textured,additive)
		if reflection_page:
			var eye := Vector3.BACK if _orthographic_size>0 else -view_pos.normalized()
			reflection_uvs[v]=_project_reflection(entry,v,eye,camera_matrix*world_normal,view_to_local,reflection_size)
			var luma := clampf(lit.dot(Vector3(.299,.587,.114))*2.25,0,1)
			reflection_amounts[v]=reflection_page*32+.125+entry.reflection_strength*(1.0-entry.reflection_light_response)*luma*(1.0-fog)*.25
		if entry.sprite:lighting[v]=Color(128.0/255,128.0/255,128.0/255,1)
		lighting[v].a=float(texture_page)/255.0
		var uv: Vector2=uvs[v] if not uvs.is_empty() else Vector2.ZERO
		texcoords[v]=(uv*(texture_size-Vector2.ONE)).round()/texture_size
		if face:texcoords[v]=texcoords[v]*.5+Vector2((face_frame%2)*.5,(face_frame%4/2)*.5)
		if entry.sprite:
			var frame: int=node.get_meta("psx_sprite_frame",0)
			texcoords[v]=((uv*63).round()+Vector2((frame%4)*64,(frame/4)*64))/256.0
	vertex_count+=vertices.size()
	var indices: PackedInt32Array=entry.indices
	for triangle in range(0,indices.size(),3):
		var a := indices[triangle]
		var b := indices[triangle+1]
		var d := indices[triangle+2]
		if view_positions[a].z>=-camera.near and view_positions[b].z>=-camera.near and view_positions[d].z>=-camera.near:
			continue
		var polygon: Array=[{"p":view_positions[a],"c":lighting[a],"uv":texcoords[a]},
			{"p":view_positions[b],"c":lighting[b],"uv":texcoords[b]},
			{"p":view_positions[d],"c":lighting[d],"uv":texcoords[d]}]
		if reflection_page:
			for corner in 3:
				var index: int=indices[triangle+corner]
				polygon[corner].reflection_uv=reflection_uvs[index]
				polygon[corner].reflection_packet=reflection_amounts[index]
		if view_positions[a].z>=-camera.near or view_positions[b].z>=-camera.near or view_positions[d].z>=-camera.near:
			polygon=clip_near(polygon)
		for j in range(1,polygon.size()-1):
			submit_triangle(polygon[0],polygon[j],polygon[j+1],atlas_texture,page_index,int(entry.get("blend_mode",0)))

func _project_reflection(entry: Dictionary,index: int,eye: Vector3,normal: Vector3,view_to_local: Basis,size: Vector2) -> Vector2:
	var uv := Vector2.ZERO
	var mode: int=entry.reflection_projection
	if mode==ReflectiveMaterial.ReflectionProjection.ENVIRONMENT:
		var direction := 2*normal.dot(eye)*normal-eye
		var diameter := 2.0*sqrt(maxf(direction.length_squared()+2*direction.z+1,.00001))
		uv=Vector2(.5+direction.x/diameter,.5-direction.y/diameter)
	else:
		if mode==ReflectiveMaterial.ReflectionProjection.UV:
			if entry.uvs and index<entry.uvs.size():uv=entry.uvs[index]
		else:
			var bounds: AABB=entry.reflection_bounds
			var position: Vector3=entry.vertices[index]-bounds.position
			uv.x=position.x/maxf(bounds.size.x,.001)
			uv.y=1-position.y/maxf(bounds.size.y,.001) if mode==ReflectiveMaterial.ReflectionProjection.PLANAR_XY else position.z/maxf(bounds.size.z,.001)
		var local_eye := view_to_local*eye
		uv+=Vector2(local_eye.x,local_eye.z if mode==ReflectiveMaterial.ReflectionProjection.PLANAR_XZ else -local_eye.y)*float(entry.reflection_motion)
	uv=(uv-Vector2(.5,.5)).rotated(entry.reflection_angle)*float(entry.reflection_scale)+Vector2(.5,.5)+Vector2(entry.reflection_offset)
	return (uv*size).round()/size

func bake_light(p: Vector3,n: Vector3,tint: Color,emission: Color) -> Vector3:
	var light := _rgb(Grade.color(ambient_light_color,saturation))
	for source in world_lights:
		if int(source.get("type",0))==2:
			light+=Vector3(source.color)*float(source.energy)*maxf(n.dot(-Vector3(source.direction)),0)
			continue
		var delta: Vector3=source.position-p
		var distance := delta.length()
		var falloff := maxf(1-distance/float(source.range),0)
		if falloff>0:
			var direction := delta/maxf(distance,.001)
			var cone := smoothstep(float(source.outer_cos),float(source.inner_cos),-direction.dot(Vector3(source.direction))) if int(source.get("type",0))==1 else 1.0
			light+=Vector3(source.color)*float(source.energy)*maxf(n.dot(direction),0)*falloff*falloff*cone
	return Vector3(tint.r,tint.g,tint.b)*light+Vector3(emission.r,emission.g,emission.b)

func shade(p: Vector3,n: Vector3,depth: float,tint: Color,base: Vector3,textured: bool=true,unlit := false,torch_receiver := true,additive := false) -> Color:
	return _packet_color(_vertex_light(p,n,tint,base,unlit,torch_receiver),_fog_weight(depth),textured,additive)

func _vertex_light(p: Vector3,n: Vector3,tint: Color,base: Vector3,unlit: bool,torch_receiver: bool) -> Vector3:
	var rgb := base
	if torch_on and torch_receiver and not unlit:
		var delta := p-torch_pos
		var distance := delta.length()
		var direction := delta/maxf(distance,.001)
		var cone := smoothstep(torch_outer_cos,torch_inner_cos,direction.dot(torch_dir))
		var attenuation := maxf(1-distance/torch_range,0)
		rgb+=Vector3(tint.r,tint.g,tint.b)*torch_color*cone*attenuation*maxf(n.dot(-direction),.12)*torch_energy
	if shot_light_energy>0 and not unlit:
		var delta := shot_light_position-p
		var square := delta.length_squared()
		var range_squared := shot_light_range*shot_light_range
		if square<range_squared:
			var attenuation := 1.0-square/range_squared
			rgb+=Vector3(tint.r,tint.g,tint.b)*shot_light_color*shot_light_energy*attenuation*attenuation*maxf(n.dot(delta/maxf(sqrt(square),.001)),0)
	return rgb

func _fog_weight(depth: float) -> float:
	return clampf((depth-fog_start)/maxf(fog_end-fog_start,.001),0,.88) if fog_enabled else 0.0

func _packet_color(lit: Vector3,fog: float,textured: bool,additive: bool) -> Color:
	var rgb := lit.lerp(Vector3.ZERO if additive else _rgb(Grade.color(fog_color,saturation)),fog)
	rgb=(rgb*(128 if textured else 255)).floor().clamp(Vector3.ZERO,Vector3.ONE*255)/255.0
	return Color(rgb.x,rgb.y,rgb.z,1)

func clip_near(polygon: Array) -> Array:
	var clipped: Array=[]
	var previous: Dictionary=polygon[-1]
	for current: Dictionary in polygon:
		var inside: bool=current.p.z < -camera.near
		var previous_inside: bool=previous.p.z < -camera.near
		if inside!=previous_inside:
			var ratio: float=(-camera.near-previous.p.z)/(current.p.z-previous.p.z)
			var vertex := {"p":previous.p.lerp(current.p,ratio),"c":previous.c.lerp(current.c,ratio),"uv":previous.uv.lerp(current.uv,ratio)}
			if current.has("reflection_uv"):
				vertex.reflection_uv=previous.reflection_uv.lerp(current.reflection_uv,ratio)
				vertex.reflection_packet=lerpf(previous.reflection_packet,current.reflection_packet,ratio)
			clipped.append(vertex)
		if inside:
			clipped.append(current)
		previous=current
	return clipped

func submit_triangle(a: Dictionary,b: Dictionary,c: Dictionary,texture: Texture2D,page_index := 0,blend_mode := 0) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray([a.c,b.c,c.c])
	var texcoords := PackedVector2Array([a.uv,b.uv,c.uv])
	var average_z := 0.0
	for vertex: Dictionary in [a,b,c]:
		var p: Vector3=vertex.p
		var divisor := 1.0 if _orthographic_size>0 else -p.z
		var screen := Vector2(160+p.x*focal/divisor,120-p.y*focal/divisor)
		if vertex_snapping:
			screen=screen.floor()
		points.append(screen)
		average_z-=p.z/3
	var cross := (points[1]-points[0]).cross(points[2]-points[0])
	if cross<=0:
		return
	var rect := Rect2(points[0],Vector2.ZERO).expand(points[1]).expand(points[2])
	if not rect.intersects(Rect2(0,0,WIDTH,HEIGHT)):
		return
	primitives.append({"points":points,"colors":colors,"uvs":texcoords,"texture":texture,"page_index":page_index,"blend_mode":blend_mode,
		"inverse_depths":PackedFloat32Array([1,1,1]) if _orthographic_size>0 else PackedFloat32Array([1.0/-a.p.z,1.0/-b.p.z,1.0/-c.p.z]),
		"bucket":clampi(int(average_z/minf(draw_distance,camera.far)*(ordering_table_size-1)),0,ordering_table_size-1),"order":primitives.size()})
	if a.has("reflection_uv"):
		primitives.back().reflection_uvs=PackedVector2Array([a.reflection_uv,b.reflection_uv,c.reflection_uv])
		primitives.back().reflection_packets=PackedFloat32Array([a.reflection_packet,b.reflection_packet,c.reflection_packet])

func _draw() -> void:
	if Engine.is_editor_hint() and not editor_preview:return
	var start_us := Time.get_ticks_usec()
	if _drawn_atlas_revision!=_frame_atlas_revision:
		for parameter in _frame_atlas_uniforms:
			_set_raster_parameter(parameter,_frame_atlas_uniforms[parameter])
		_drawn_atlas_revision=_frame_atlas_revision
	if draw_background: draw_rect(Rect2(0,0,WIDTH,HEIGHT),Color(1.0/31,1.0/31,1.0/31,0))
	var batches := primitives.any(func(primitive: Dictionary):return int(primitive.get("blend_mode",0))==1)
	if batches:
		_draw_blend_batches()
	else:
		for item in _batch_canvases:RenderingServer.canvas_item_set_visible(item,false)
		if _effects_canvas.is_valid():RenderingServer.canvas_item_set_visible(_effects_canvas,false)
	for i in primitives.size():
		if not batches:_draw_primitive(get_canvas_item(),i)
	for effect in effects:
		if Time.get_ticks_msec()>effect.until:
			continue
		var pos: Vector3=inverse_camera*effect.position
		if pos.z>=-NEAR:
			continue
		var p := Vector2(160+pos.x*focal/-pos.z,120-pos.y*focal/-pos.z).floor()
		var radius: float=effect.radius
		var color: Color=effect.color
		color.a=0 # untextured Gouraud packet, page 0
		var diamond := PackedVector2Array([p+Vector2(-radius,0),p+Vector2(0,-radius),p+Vector2(radius,0),p+Vector2(0,radius)])
		if batches:RenderingServer.canvas_item_add_triangle_array(_effects_canvas,PackedInt32Array([0,1,2,0,2,3]),diamond,PackedColorArray([color,color,color,color]))
		else:draw_colored_polygon(diamond,color)
	last_draw_us=Time.get_ticks_usec()-start_us
func _draw_primitive(canvas: RID,index: int) -> void:
	var primitive: Dictionary=primitives[index]
	if _frame_uses_mesh and primitive.has("inverse_depths"):
		RenderingServer.canvas_item_add_mesh(canvas,_perspective_meshes[index].get_rid(),Transform2D.IDENTITY,Color.WHITE,primitive.texture.get_rid())
	else:
		RenderingServer.canvas_item_add_triangle_array(canvas,primitive.get("indices",PackedInt32Array([0,1,2])),primitive.points,primitive.colors,primitive.uvs,PackedInt32Array(),PackedFloat32Array(),primitive.texture.get_rid())
func _draw_blend_batches() -> void:
	while _batch_canvases.size()<primitives.size():
		var item := RenderingServer.canvas_item_create();RenderingServer.canvas_item_set_parent(item,get_canvas_item());_batch_canvases.append(item)
	for index in _batch_canvases.size():
		var item := _batch_canvases[index];RenderingServer.canvas_item_clear(item);RenderingServer.canvas_item_set_visible(item,index<primitives.size())
		if index>=primitives.size():continue
		RenderingServer.canvas_item_set_draw_index(item,index)
		RenderingServer.canvas_item_set_material(item,(_add_quarter_raster if int(primitives[index].get("blend_mode",0))==1 else raster).get_rid())
		_draw_primitive(item,index)
	if not _effects_canvas.is_valid():
		_effects_canvas=RenderingServer.canvas_item_create();RenderingServer.canvas_item_set_parent(_effects_canvas,get_canvas_item())
	RenderingServer.canvas_item_set_draw_index(_effects_canvas,_batch_canvases.size());RenderingServer.canvas_item_clear(_effects_canvas);RenderingServer.canvas_item_set_visible(_effects_canvas,true);RenderingServer.canvas_item_set_material(_effects_canvas,raster.get_rid())
func _exit_tree() -> void:
	for item in _batch_canvases:RenderingServer.free_rid(item)
	_batch_canvases.clear()
	if _effects_canvas.is_valid():RenderingServer.free_rid(_effects_canvas);_effects_canvas=RID()

func _prepare_perspective_meshes() -> void:
	if not extended_texture_pages and not _has_reflections and not _frame_has_cel and affine_texture_strength>=1.0 and not _player_depth_active:return
	_set_raster_parameter("explicit_perspective_uvs",not primitives.is_empty() and primitives[0].has("perspective_uvs"))
	while _perspective_meshes.size()<primitives.size():_perspective_meshes.append(ArrayMesh.new())
	for i in primitives.size():
		var primitive: Dictionary=primitives[i]
		if not primitive.has("inverse_depths"):continue
		var arrays: Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=primitive.points
		arrays[Mesh.ARRAY_TEX_UV]=primitive.uvs
		arrays[Mesh.ARRAY_COLOR]=primitive.colors
		var depth_channels: bool=primitive.has("depth_channels")
		var native_reflection_channels: bool=primitive.get("reflection_channels",false)
		var cel_channels: bool=primitive.get("cel_channels",false)
		var wide_channels := extended_texture_pages or _has_reflections or cel_channels
		if wide_channels:
			if primitive.get("extended_pages",false) or native_reflection_channels or cel_channels:arrays[Mesh.ARRAY_CUSTOM0]=primitive.depth_channels
			else:
				var channels := PackedFloat32Array();channels.resize(primitive.points.size()*4)
				for vertex in primitive.points.size():
					channels[vertex*4]=primitive.inverse_depths[vertex]
					channels[vertex*4+2]=primitive.get("page_index",0)
					if primitive.has("reflection_packets"):channels[vertex*4+3]=primitive.reflection_packets[vertex]
				arrays[Mesh.ARRAY_CUSTOM0]=channels
		else:arrays[Mesh.ARRAY_CUSTOM0]=primitive.depth_channels if depth_channels else primitive.inverse_depths
		if primitive.has("indices"):arrays[Mesh.ARRAY_INDEX]=primitive.indices
		if primitive.has("perspective_uvs"):arrays[Mesh.ARRAY_CUSTOM1]=primitive.perspective_uvs
		elif primitive.has("reflection_uvs"):
			var coords := PackedFloat32Array()
			for uv: Vector2 in primitive.reflection_uvs:coords.append_array(PackedFloat32Array([0,0,uv.x,uv.y]))
			arrays[Mesh.ARRAY_CUSTOM1]=coords
		var custom_format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT if wide_channels else (Mesh.ARRAY_CUSTOM_RG_FLOAT if depth_channels else Mesh.ARRAY_CUSTOM_R_FLOAT)
		var flags := Mesh.ARRAY_FLAG_USE_2D_VERTICES|Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE|(custom_format<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		if arrays[Mesh.ARRAY_CUSTOM1]!=null:
			var uv_format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT if native_reflection_channels or cel_channels or primitive.has("reflection_uvs") else Mesh.ARRAY_CUSTOM_RG_FLOAT
			flags|=uv_format<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		var mesh := _perspective_meshes[i]
		mesh.clear_surfaces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)

func add_shot(muzzle: Vector3,impact: Vector3,hit: bool) -> void:
	var time := Time.get_ticks_msec()
	effects=effects.filter(func(effect: Dictionary): return effect.until>time)
	if hit:
		effects.append({"position":impact,"radius":1.0,"color":Color(.7,.62,.44),"until":time+130})
