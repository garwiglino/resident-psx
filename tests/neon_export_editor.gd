extends RefCounted
const Lamp=preload("res://scripts/lighting/psx_lamp_3d.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 8) -> void:
	for frame in count:await plugin.get_tree().process_frame
func click_model(plugin: EditorPlugin,lamp: Node3D,driver: Node) -> void:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var panel := viewport.get_parent()
	if panel is SubViewportContainer:panel=panel.get_parent()
	var surface: Control
	var diagnostic := []
	for child in panel.find_children("*","Control",true,false):
		for connection in child.get_signal_connection_list("gui_input"):
			var callback: Callable=connection.callable
			diagnostic.append(str(child.get_path())+" "+str(callback))
			if callback.get_method()==&"_sinput" or str(callback).ends_with("::_sinput"):surface=child
	if not surface:print("NATIVE_CLICK_SURFACES ",viewport.get_path()," / ",panel.get_path()," ",diagnostic)
	check(surface!=null,"Native editor viewport receives synthetic test clicks")
	if not surface:return
	EditorInterface.get_selection().clear();await settle(plugin)
	# Click a face, away from the origin marker and transform handles.
	var at: Vector2=driver.forced_camera.unproject_position(lamp.to_global(Vector3(.35,-.06,0)))
	var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=surface.get_global_rect().position+at
	event.pressed=true;surface.gui_input.emit(event);await settle(plugin,2)
	event.pressed=false;surface.gui_input.emit(event);await settle(plugin)
	check(EditorInterface.get_selection().get_selected_nodes()==[lamp],"Clicking the real model selects its lamp root through native editor picking")
func run(plugin: EditorPlugin) -> void:
	await settle(plugin,30)
	var artist_path := "res://scenes/examples/inventory_demo.tscn"
	var artist_digest := FileAccess.get_sha256(artist_path)
	var root: Node3D=load("res://scripts/modular_map/map_3d.gd").new();root.name="NeonSelectionTest"
	root.layout=load("res://scripts/modular_map/layout.gd").new()
	root.kit=load("res://assets/environment/modular_2m/default_kit.tres")
	var lamp: Node3D=load("res://scenes/lighting/neon.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE);lamp.name="Neon"
	lamp.model_scene=load("res://assets/props/neon_light_01/neon_light_01.tscn");lamp.light_color=Color.WHITE;lamp.flicker=false
	root.add_child(lamp);lamp.owner=root
	var settings: Node=load("res://scripts/levels/psx_level_settings.gd").new();settings.name="ReglagesNiveau";settings.fog_enabled=false;settings.ambient_light_color=Color(.15,.15,.15);root.add_child(settings);settings.owner=root
	var path := "res://exports/editor_tests/neon_export_editor.tscn"
	var packed := PackedScene.new();packed.pack(root);ResourceSaver.save(packed,path);root.free()
	EditorInterface.get_resource_filesystem().update_file(path);EditorInterface.open_scene_from_path(path);EditorInterface.set_main_screen_editor("3D")
	await settle(plugin,20);root=EditorInterface.get_edited_scene_root();lamp=root.get_node("Neon")
	plugin.toggle.button_pressed=true
	var driver: Node=load("res://tools/validate_editor_preview.gd").new();plugin.add_child(driver);driver.process_priority=999
	driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();driver.forced_fov=40
	driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(1,-1.4,1.7)).looking_at(Vector3(0,-.05,0))
	await settle(plugin,20)
	check(lamp._surface_count==1,"Actual exported M_light binds in the real editor")
	check(plugin._lamp_gizmo!=null and plugin._lamp_gizmo._has_gizmo(lamp),"Lamp picking plugin is registered")
	lamp.update_gizmos();await settle(plugin)
	var owns_pick := false
	for gizmo in lamp.get_gizmos():
		if gizmo.get_plugin()==plugin._lamp_gizmo:owns_pick=true
	check(owns_pick,"Authorable lamp root owns its actual editor selection gizmo")
	await click_model(plugin,lamp,driver)
	check(lamp.model.owner==null,"Generated model remains temporary rather than bloating the saved level")
	var view=plugin.views.get(0)
	check(view!=null,"PSX viewport is available")
	if view:
		var unlit := 0;var lit := 0
		for entry in view.renderer.entries:
			if int(entry.get("unlit_light_id",0))==lamp.get_instance_id():unlit+=1
			else:lit+=1
		check(unlit==1 and lit==4,"Native editor renderer receives one luminous surface and four lit housing surfaces")
		var on: Image=view.buffer.get_texture().get_image();lamp.enabled=false;await settle(plugin,12)
		var off: Image=view.buffer.get_texture().get_image()
		check(on.get_data()!=off.get_data(),"The actual exported neon changes visibly when powered off")
		lamp.enabled=true;await settle(plugin,12)
		var sheet := Image.create(640,240,false,Image.FORMAT_RGBA8)
		sheet.blit_rect(on,Rect2i(0,0,320,240),Vector2i.ZERO);sheet.blit_rect(off,Rect2i(0,0,320,240),Vector2i(320,0));sheet.save_png("res://docs/neon-export-on-off.png")
	var map_plugin: EditorPlugin
	for candidate: Node in plugin.get_tree().root.find_children("*","EditorPlugin",true,false):
		if candidate.get_script() and candidate.get_script().resource_path=="res://addons/modular_map/plugin.gd":map_plugin=candidate
	check(map_plugin!=null,"Map authoring plugin is available")
	if map_plugin:
		map_plugin._set_map(root);map_plugin.paint_3d.button_pressed=true
		var selection := EditorInterface.get_selection();selection.clear();selection.add_node(lamp);await settle(plugin)
		var camera: Camera3D=driver.forced_camera
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=camera.unproject_position(lamp.global_position)
		check(not map_plugin._can_paint_3d() and map_plugin._forward_3d_gui_input(camera,event)==EditorPlugin.AFTER_GUI_INPUT_PASS,"Active map painter allows normal lamp manipulation when a lamp is selected")
		check(root.layout.cells.is_empty(),"Manipulating a lamp does not paint accidental walls or floors")
		selection.clear();selection.add_node(root)
		check(map_plugin._can_paint_3d(),"Selecting the Map restores 3D painting")
		selection.clear();selection.add_node(lamp)
		var undo := plugin.get_undo_redo();var before: Transform3D=lamp.transform
		var after := Transform3D(Basis.from_euler(Vector3(.1,.4,0)),Vector3(.3,1.2,.5))
		undo.create_action("Deplacer neon",UndoRedo.MERGE_DISABLE,root);undo.add_do_property(lamp,"transform",after);undo.add_undo_property(lamp,"transform",before);undo.commit_action();await settle(plugin)
		check(lamp.global_transform==after and lamp.model.global_transform==after,"Root manipulation moves the visible model and PSX light together")
		var history := undo.get_history_undo_redo(undo.get_object_history_id(root));history.undo();await settle(plugin)
		check(lamp.transform==before,"Undo restores lamp placement")
		history.redo();await settle(plugin);EditorInterface.save_scene();await settle(plugin)
		var saved: Node3D=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		check(saved.get_node("Neon").transform==after and saved.get_node("Neon").model_scene.resource_path.ends_with("neon_light_01.tscn"),"Saving preserves placement and original model assignment")
		saved.free()
	check(FileAccess.get_file_as_string(path).length()<6500,"Editor fixture saves no generated mesh data")
	check(FileAccess.get_sha256(artist_path)==artist_digest,"Artist's actual map remains untouched")
	driver.free()
	FileAccess.open("res://docs/neon-export-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("NEON_EXPORT_EDITOR_OK " if failures.is_empty() else "NEON_EXPORT_EDITOR_FAILED ",JSON.stringify(failures));plugin.get_tree().quit(0 if failures.is_empty() else 1)
