extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 15) -> void:
	for frame in count:await plugin.get_tree().process_frame
func run(plugin: EditorPlugin) -> void:
	await settle(plugin,30)
	var path := "res://scenes/player.tscn";var original := FileAccess.get_sha256(path)
	var profile_hash := FileAccess.get_sha256("res://assets/rendering/anime_psx.tres")
	EditorInterface.open_scene_from_path(path);EditorInterface.set_main_screen_editor("3D");await settle(plugin,20)
	var player := EditorInterface.get_edited_scene_root()
	var module := PSXLevelSettings.new();module.name="ReviewOnlySettings";module.anime_style=load("res://assets/rendering/anime_psx.tres").duplicate();module.anime_style.enabled=false;module.fog_enabled=false;module.ambient_light_color=Color(.3,.3,.35);player.add_child(module)
	var key := PSXLight3D.new();key.light_energy=1.5;key.light_range=6;player.add_child(key);key.position=Vector3(-.8,2.2,-.9)
	var driver: Node=load("res://tools/validate_editor_preview.gd").new();plugin.add_child(driver);driver.process_priority=999;driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(.5,1.5,-1.1)).looking_at(Vector3(0,1.4,0))
	plugin.toggle.button_pressed=true;await settle(plugin,24)
	var view=plugin.views[0]
	check(plugin.settings_node==module and plugin._settings().anime_style==module.anime_style,"Level inspector exposes the exact style used by editor and game")
	var before: Image=view.buffer.get_texture().get_image();var rebuilds: int=view.rebuilds
	module.anime_style.enabled=true;await settle(plugin,20);await RenderingServer.frame_post_draw
	var after: Image=view.buffer.get_texture().get_image()
	var stats: Dictionary=view.renderer.native_geometry.get_statistics()
	check(after.get_data()!=before.get_data() and stats.anime_triangles>0 and stats.outline_triangles>0,"Editor preview renders native cel shading and skinned contour without launching the game")
	module.anime_style.outline_width=.018;module.anime_style.shadow_tint=Color(.7,1,.7);await settle(plugin,20);await RenderingServer.frame_post_draw
	check(view.buffer.get_texture().get_image().get_data()!=after.get_data(),"Inspector edits update colour and geometric contour live")
	check(view.rebuilds==rebuilds,"Editing anime style does not rebuild level geometry or textures")
	plugin._open_settings();check(EditorInterface.get_inspector().get_edited_object()==module,"Reglages niveau opens the module containing the style")
	await settle(plugin,12)
	EditorInterface.edit_resource(module.anime_style);await settle(plugin,12)
	check(EditorInterface.get_inspector().get_edited_object()==module.anime_style,"The shared style opens directly with its editable controls in the inspector")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://docs/anime-settings-inspector.png")
	check(FileAccess.get_sha256(path)==original and FileAccess.get_sha256("res://assets/rendering/anime_psx.tres")==profile_hash,"Preview keeps artist scenes and the shared style intact")
	driver.free();player.remove_child(module);module.free();player.remove_child(key);key.free()
	var result := {"ok":failures.is_empty(),"errors":failures,"stats":stats}
	FileAccess.open("res://docs/anime-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ANIME_EDITOR_OK " if failures.is_empty() else "ANIME_EDITOR_FAILED ",JSON.stringify(result));plugin.get_tree().quit(0 if failures.is_empty() else 1)
