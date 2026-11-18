@tool
extends EditorPlugin
const Renderer=preload("res://scripts/psx_renderer.gd")
const PreviewView=preload("res://addons/psx_viewport/view.gd")
const LevelSettings=preload("res://scripts/levels/psx_level_settings.gd")
const SHARED_GAME := "res://scenes/systemes_jeu.tscn"
var toolbar: HBoxContainer
var toggle: Button
var settings_button: Button
var views: Dictionary={}
var preview_worlds: Dictionary={}
var active_scene: Node3D
var settings_node: Node
var defaults: Dictionary={}
var main_settings: Dictionary={}
var geometry_dirty := false
var watched_meshes: Dictionary={}
var watched_resources: Array[Resource]=[]
var refresh_clock := 0.0
var main_stamp := -1
var main_path := ""
var _installed := false
var _lamp_gizmo: EditorNode3DGizmoPlugin
var restart_notice: Label
var _preview_version_checked := false

func _update_restart_notice(problem: Dictionary) -> void:
	if not is_instance_valid(restart_notice):
		restart_notice=Label.new();toolbar.add_child(restart_notice)
		restart_notice.tooltip_text="Enregistrer les scenes, fermer puis rouvrir Godot pour charger le moteur PSX actuel. La vue 3D normale reste disponible."
	restart_notice.visible=not problem.is_empty()
	if restart_notice.visible:restart_notice.text="PSX v%d chargee : rouvrir Godot pour la v%d" % [problem.loaded,problem.required]

func _install_lamp_gizmo() -> void:
	if _lamp_gizmo:return
	_lamp_gizmo=preload("res://addons/psx_viewport/lamp_gizmo.gd").new()
	add_node_3d_gizmo_plugin(_lamp_gizmo)

func _enter_tree() -> void:
	if DisplayServer.get_name()=="headless":set_process(false);return
	_installed=true
	_install_lamp_gizmo()
	process_priority=1000
	var initial := Renderer.new()
	for property in Renderer.PREVIEW_PROPERTIES:defaults[property]=initial.get(property)
	initial.free()
	toolbar=HBoxContainer.new()
	toggle=Button.new();toggle.text="PSX";toggle.toggle_mode=true
	toggle.tooltip_text="Rendu PSX dans la vue 3D, sans lancer le jeu."
	toggle.button_pressed=EditorInterface.get_editor_settings().get_project_metadata("psx_viewport","enabled",true)
	toggle.toggled.connect(_toggle_preview);toolbar.add_child(toggle)
	settings_button=Button.new();settings_button.text="Reglages niveau"
	settings_button.tooltip_text="Atmosphere PSX, fog, couleurs, ambiance et musiques du niveau."
	settings_button.pressed.connect(_open_settings);toolbar.add_child(settings_button)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU,toolbar)
	scene_changed.connect(_scene_changed)
	EditorInterface.get_inspector().property_edited.connect(_property_edited)
	get_tree().node_added.connect(_node_added);get_tree().node_removed.connect(_node_removed)
	call_deferred("_scene_changed",EditorInterface.get_edited_scene_root())
	set_process(true)
	if "--psx-preview-test" in OS.get_cmdline_user_args():call_deferred("_run_validation")
	if "--anime-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_anime_validation")
	if "--interphone-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_interphone_validation")
	if "--level-settings-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_level_validation")
	if "--inventory-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_inventory_validation")
	if "--animated-export-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_animated_export_validation")
	if "--mechanism-access-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_mechanism_access_validation")
	if "--psx-unlit-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_unlit_validation")
	if "--light-shafts-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_light_shafts_validation")
	if "--interactive-parts-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_interactive_parts_validation")
	if "--lamp-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_lamp_validation")
	if "--neon-export-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_neon_validation")
	if "--neon-performance-editor-test" in OS.get_cmdline_user_args():call_deferred("_run_neon_performance_validation")
	if "--repair-jacket-import" in OS.get_cmdline_user_args():call_deferred("_repair_jacket_import")

func _repair_jacket_import() -> void:
	await load("res://tools/repair_jacket_import.gd").new().run(self)

func _run_anime_validation() -> void:
	await load("res://tests/anime_psx_editor.gd").new().run(self)

func _run_interphone_validation() -> void:
	await load("res://tests/interphone_calls_editor.gd").new().run(self)

func _run_inventory_validation() -> void:
	await load("res://tests/inventory_editor.gd").new().run(self)

func _run_animated_export_validation() -> void:
	await load("res://tests/animated_export_editor.gd").new().run(self)

func _run_mechanism_access_validation() -> void:
	await load("res://tests/mechanism_access_editor.gd").new().run(self)

func _run_unlit_validation() -> void:
	await load("res://tests/psx_unlit_editor.gd").new().run(self)

func _run_light_shafts_validation() -> void:
	await load("res://tests/light_shafts_editor.gd").new().run(self)

func _run_interactive_parts_validation() -> void:
	await load("res://tests/interactive_parts_editor.gd").new().run(self)

func _run_lamp_validation() -> void:
	await load("res://tests/lamp_fixtures_editor.gd").new().run(self)

func _run_neon_validation() -> void:
	await load("res://tests/neon_export_editor.gd").new().run(self)

func _run_neon_performance_validation() -> void:
	await load("res://tests/neon_performance_editor.gd").new().run(self)

func _run_level_validation() -> void:
	await load("res://tests/level_settings_editor.gd").new().run(self)

func _run_validation() -> void:
	var test=load("res://tools/validate_editor_preview.gd").new()
	add_child(test);test.run(self)

func _exit_tree() -> void:
	if not _installed:return
	if _lamp_gizmo:remove_node_3d_gizmo_plugin(_lamp_gizmo);_lamp_gizmo=null
	_clear_views();_unwatch_resources()
	Renderer.TexturePages.FaceTextures.clear_cache()
	load("res://scripts/audio/psx_audio_routing.gd").release_cached_effects()
	if ResourceLoader.has_cached("res://scripts/dialogue/intercom_filter.gd"): load("res://scripts/dialogue/intercom_filter.gd").clear_cache()
	if EditorInterface.get_inspector().property_edited.is_connected(_property_edited):EditorInterface.get_inspector().property_edited.disconnect(_property_edited)
	if get_tree().node_added.is_connected(_node_added):get_tree().node_added.disconnect(_node_added)
	if get_tree().node_removed.is_connected(_node_removed):get_tree().node_removed.disconnect(_node_removed)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU,toolbar)
	if is_instance_valid(toolbar):toolbar.free()

func _toggle_preview(enabled: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata("psx_viewport","enabled",enabled)
	if not enabled:
		_update_restart_notice({})
		for view in views.values():view.suspend()
		_restore_worlds()
	else:geometry_dirty=true

func _scene_changed(scene: Node) -> void:
	_clear_views();_unwatch_resources();watched_meshes.clear()
	_update_restart_notice({})
	active_scene=scene as Node3D;settings_node=null;main_stamp=-1
	if active_scene:
		settings_node=LevelSettings.find_in(active_scene)
		if not settings_node:
			var candidate: Node=active_scene.find_child("PSXRenderer",true,false)
			if candidate and candidate.get_script()==Renderer:settings_node=candidate
	geometry_dirty=true

func _clear_views() -> void:
	_restore_worlds()
	for view in views.values():view.dispose()
	views.clear()

func _restore_worlds(keep: Dictionary={}) -> void:
	for id in preview_worlds:
		if keep.has(id):continue
		var world: World3D=preview_worlds[id]
		# BG_CANVAS scheduling reads the scenario, not the camera override.
		# Restore from the live World3D property, which the plugin never changes.
		RenderingServer.scenario_set_environment(world.scenario,world.environment.get_rid() if world.environment else RID())
	preview_worlds=keep

func _unwatch_resources() -> void:
	for resource in watched_resources:
		if resource.changed.is_connected(_geometry_changed):resource.changed.disconnect(_geometry_changed)
	watched_resources.clear()

func _watch_resource(resource: Resource) -> void:
	if not resource or resource in watched_resources:return
	resource.changed.connect(_geometry_changed);watched_resources.append(resource)

func _watch_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		watched_meshes[node.get_instance_id()]=true;_watch_resource(node.mesh);_watch_resource(node.material_override)
		if node.mesh:
			for surface in node.mesh.get_surface_count():_watch_resource(node.get_active_material(surface))
	for child in node.get_children():_watch_meshes(child)

func _geometry_changed() -> void:geometry_dirty=true

func _node_added(node: Node) -> void:
	if active_scene and node is MeshInstance3D and active_scene.is_ancestor_of(node):geometry_dirty=true
	if active_scene and node is LevelSettings and active_scene.is_ancestor_of(node): settings_node=node

func _node_removed(node: Node) -> void:
	if watched_meshes.has(node.get_instance_id()):geometry_dirty=true
	if node==settings_node: settings_node=null

func _property_edited(_property: StringName) -> void:
	var edited: Object=EditorInterface.get_inspector().get_edited_object()
	if edited is MeshInstance3D or edited is Mesh or edited is Material or edited is CharacterAppearance:geometry_dirty=true

func _settings() -> Dictionary:
	var path: String=SHARED_GAME if ResourceLoader.exists(SHARED_GAME) else ProjectSettings.get_setting("application/run/main_scene","")
	var stamp := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	if main_path!=path or main_stamp!=stamp:
		main_path=path;main_stamp=stamp;main_settings=defaults.duplicate()
		if not path.is_empty():
			var packed: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
			if packed:
				var state := packed.get_state()
				for node in state.get_node_count():
					if state.get_node_name(node)!=&"PSXRenderer":continue
					for index in state.get_node_property_count(node):
						var property := String(state.get_node_property_name(node,index))
						if property in Renderer.PREVIEW_PROPERTIES:main_settings[property]=state.get_node_property_value(node,index)
	var result := main_settings.duplicate()
	if is_instance_valid(settings_node):
		if settings_node is LevelSettings: result.merge(settings_node.render_overrides(),true)
		else:
			for property in Renderer.PREVIEW_PROPERTIES: result[property]=settings_node.get(property)
	elif active_scene and (active_scene is InventoryUseTarget3D or active_scene.has_method("is_placement_scene") or active_scene.get_meta("psx_asset_type","")=="animated"):
		# Asset authoring needs a readable view even outside a lit level. These
		# inspection settings never enter the saved scene or the runtime renderer.
		result.ambient_light_color=Color(.6,.6,.6);result.fog_enabled=false
	return result

func _process(delta: float) -> void:
	if not _installed:return
	_install_lamp_gizmo()
	# Also refresh renderers that were already alive when this script reloaded.
	if not _preview_version_checked:geometry_dirty=true;_preview_version_checked=true
	refresh_clock+=delta
	if refresh_clock<1.0/30:return
	refresh_clock=0
	if not toggle.button_pressed or not is_instance_valid(active_scene):return
	var settings := _settings()
	if geometry_dirty:
		_unwatch_resources();watched_meshes.clear();_watch_meshes(active_scene)
		for view in views.values():view.rebuild_geometry()
		geometry_dirty=false
	var visible_worlds: Dictionary={}
	var version_problem: Dictionary={}
	for index in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(index)
		if not viewport:continue
		var visible := viewport_visible(viewport)
		if not visible:
			if views.has(index):views[index].suspend()
			continue
		if not views.has(index):
			var view := PreviewView.new();view.setup(self,viewport,active_scene,settings);views[index]=view
		if not views[index].renderer.native_restart_required.is_empty():
			version_problem=views[index].renderer.native_restart_required
			views[index].suspend();continue
		views[index].render(settings)
		var world := viewport.find_world_3d()
		visible_worlds[world.get_instance_id()]=world
		RenderingServer.scenario_set_environment(world.scenario,views[index].environment.get_rid())
	_restore_worlds(visible_worlds)
	_update_restart_notice(version_problem)

func viewport_visible(viewport: SubViewport) -> bool:
	# Godot hides this container and displays its texture through a sibling
	# surface. The owning viewport panel determines whether the view is open.
	var panel := viewport.get_parent()
	if panel is SubViewportContainer:panel=panel.get_parent()
	return panel is Control and panel.is_visible_in_tree() and viewport.size.x>1 and viewport.size.y>1

func _open_settings() -> void:
	if is_instance_valid(settings_node):EditorInterface.inspect_object(settings_node);return
	if not is_instance_valid(active_scene): return
	var settings := LevelSettings.new(); settings.name="ReglagesNiveau"
	settings.profile=load("res://scripts/audio/level_audio_profile.gd").new()
	var undo := get_undo_redo(); undo.create_action("Ajouter les reglages du niveau",UndoRedo.MERGE_DISABLE,active_scene)
	undo.add_do_method(active_scene,"add_child",settings); undo.add_do_method(settings,"set_owner",active_scene)
	undo.add_undo_method(active_scene,"remove_child",settings); undo.add_do_reference(settings); undo.commit_action()
	settings_node=settings; EditorInterface.inspect_object(settings)

func _select_settings() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	if not scene:return
	var renderer := scene.find_child("PSXRenderer",true,false)
	if renderer:EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(renderer);EditorInterface.inspect_object(renderer)
