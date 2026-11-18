@tool
extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 12) -> void:
	for frame in count:await plugin.get_tree().process_frame
func fields(object: Object) -> PackedStringArray:
	var result := PackedStringArray()
	for property in object.get_property_list():
		if property.usage&PROPERTY_USAGE_EDITOR:result.append(property.name)
	return result
func run(plugin: EditorPlugin) -> void:
	plugin.get_tree().create_timer(40).timeout.connect(func():push_error("Interactive editor validation timeout");plugin.get_tree().quit(2));await settle(plugin,20)
	var source: Node3D=load("res://scenes/interactions/interphone_example.tscn").instantiate();source.interaction_id=&"test.editor.interphone"
	var packed := PackedScene.new();packed.pack(source);var path := "res://exports/editor_tests/interphone.tscn";ResourceSaver.save(packed,path);source.free()
	EditorInterface.get_resource_filesystem().update_file(path);EditorInterface.open_scene_from_path(path);EditorInterface.set_main_screen_editor("3D");await settle(plugin,20)
	var root: Node3D=EditorInterface.get_edited_scene_root();var part: Node3D=root.get_node("Parties/Appeler");var button: Node3D=root.get_node("Modele/BoutonAppel");var pose := button.transform
	check(root.configuration_error().is_empty() and not root.once,"Interphone scene validates with no inventory piece or per-device script")
	var incomplete: Node3D=load("res://scenes/interactions/action_part.tscn").instantiate();incomplete.name="SansDialogue";incomplete.visual_path=NodePath("../../Modele");root.get_node("Parties").add_child(incomplete)
	check(root.configuration_error().is_empty() and Array(root._get_configuration_warnings()).any(func(warning: String):return warning.begins_with("SansDialogue :")),"Root warns about the named incomplete button without blocking inspection")
	check(not incomplete._get_configuration_warnings().is_empty(),"Incomplete button retains its own inspector warning");incomplete.free()
	check(part._state_pose==null and root._access==null and root.find_children("*","AudioStreamPlayer3D",true,false).is_empty(),"Editor inspection never plays actions, animations or audio")
	var properties := fields(part)
	for name in ["behaviour","after_interaction","dialogue","actions","requirements","once","selection_area_path","highlight_paths","activation_animation"]:check(name in properties,"Part inspector exposes "+name)
	check("required_item" not in properties and "installed_visual_path" not in properties,"Button inspector contains no irrelevant inventory fields")
	check("off_actions" not in properties and "close_when_complete" not in fields(root),"Button-only scene hides switch and assembly-only controls")
	EditorInterface.inspect_object(part);part.behaviour=1;await settle(plugin,3);properties=fields(part)
	check("off_actions" in properties and "state_flag" in properties and "initially_active" in properties and "off_selection_label" in properties,"Selecting switch behaviour exposes ON/OFF actions and saved state controls")
	part.behaviour=0;check(button.transform.is_equal_approx(pose),"Inspector behaviour changes never alter the authored model pose")
	check(root.get_node("Parties/Appeler/ZoneSelection/Volume").owner==root,"Example selection volume is an ordinary editable scene node")
	plugin.toggle.button_pressed=true;var driver: Node=load("res://tools/validate_editor_preview.gd").new();plugin.add_child(driver);driver.process_priority=999
	driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();driver.forced_fov=45;driver.forced_transform=root.get_node("CameraFixe").global_transform;await settle(plugin,20)
	check(plugin.views.has(0) and plugin.views[0].renderer.triangle_count>0,"Universal interactive scene remains visible in native PSX editor preview")
	check(not EditorInterface.is_playing_scene(),"Part authoring runs without starting gameplay")
	await RenderingServer.frame_post_draw;var picture: Image=plugin.views[0].buffer.get_texture().get_image();picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/interphone-editor.png")
	driver.free();FileAccess.open("res://docs/interactive-parts-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("INTERACTIVE_PARTS_EDITOR_OK " if failures.is_empty() else "INTERACTIVE_PARTS_EDITOR_FAILED ",str(failures));plugin.get_tree().quit(0 if failures.is_empty() else 1)
