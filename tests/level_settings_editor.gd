extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message); push_error(message)
func settle(plugin: EditorPlugin,count := 12) -> void:
	for frame in count: await plugin.get_tree().process_frame
func run(plugin: EditorPlugin) -> void:
	print("LEVEL_EDITOR_PHASE boot")
	await settle(plugin,30)
	# The isolated editor has a separate UID cache from the artist's editor.
	var uid := ResourceUID.text_to_id(FileAccess.get_file_as_string("res://scripts/psx_light_3d.gd.uid").strip_edges())
	if not ResourceUID.has_id(uid): ResourceUID.add_id(uid,"res://scripts/psx_light_3d.gd")
	var path := "res://scenes/maps/modular_example.tscn"
	var original := FileAccess.get_sha256(path)
	print("LEVEL_EDITOR_PHASE open")
	EditorInterface.open_scene_from_path(path); EditorInterface.set_main_screen_editor("3D")
	await settle(plugin,20)
	var level := EditorInterface.get_edited_scene_root()
	var settings: Node=level.get_node("ReglagesNiveau")
	print("LEVEL_EDITOR_PHASE local_settings")
	check(plugin.settings_node==settings,"Toolbar selects the local settings module")
	check(not level.has_node("PSXRenderer") and not level.has_node("AudioNiveau"),"Level has no copied renderer or duplicate audio manager")
	check(plugin._settings().fog_start==settings.fog_start,"Editor preview reads local fog")
	var driver: Node=load("res://tools/validate_editor_preview.gd").new(); plugin.add_child(driver)
	driver.process_priority=999; driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(3,1.5,4)).looking_at(Vector3(2,1.4,0))
	plugin.toggle.button_pressed=true; await settle(plugin,20)
	var view=plugin.views[0]
	print("LEVEL_EDITOR_PHASE preview")
	check(view.renderer.triangle_count>0 and view.renderer.world_lights.size()==2,"Actual native editor preview sees artist lights")
	plugin._open_settings()
	check(EditorInterface.get_inspector().get_edited_object()==settings,"Settings button opens the level inspector")
	var before: Image=view.buffer.get_texture().get_image()
	settings.saturation=0; settings.fog_color=Color(.15,.3,.5); settings.fog_start=0; settings.fog_end=6
	print("LEVEL_EDITOR_PHASE changed")
	await settle(plugin,20); await RenderingServer.frame_post_draw
	var after: Image=view.buffer.get_texture().get_image()
	print("LEVEL_EDITOR_PHASE image")
	check(after.get_data()!=before.get_data(),"Inspector colour/fog edits visibly update the native editor preview")
	check(view.renderer.saturation==0 and view.renderer.fog_end==6,"Runtime and editor use identical level values")
	after.save_png("res://docs/level-settings-preview.png")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://docs/level-settings-inspector.png")
	check(FileAccess.get_sha256(path)==original,"Preview does not save or replace artist edits")
	driver.free()
	var result := {"ok":failures.is_empty(),"errors":failures}
	var file := FileAccess.open("res://docs/level-settings-editor-validation.json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	print("LEVEL_SETTINGS_EDITOR_OK " if failures.is_empty() else "LEVEL_SETTINGS_EDITOR_FAILED ",JSON.stringify(result))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
