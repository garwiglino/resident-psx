extends RefCounted
const Grade=preload("res://scripts/levels/palette_grade.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 8) -> void:
	for frame in count:await plugin.get_tree().process_frame
func run(plugin: EditorPlugin) -> void:
	await settle(plugin,30)
	var root := Node3D.new();root.name="LampeTest"
	var lamp: Node3D=load("res://scenes/lighting/neon.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE);lamp.name="Neon";root.add_child(lamp);lamp.owner=root;lamp.position.y=1;lamp.light_color=Color.WHITE
	var floor := MeshInstance3D.new();floor.name="Sol";floor.mesh=PlaneMesh.new();floor.mesh.size=Vector2(3,3);root.add_child(floor);floor.owner=root
	var settings: Node=load("res://scripts/levels/psx_level_settings.gd").new();settings.name="ReglagesNiveau";settings.ambient_light_color=Color(.15,.15,.15);settings.fog_enabled=false;root.add_child(settings);settings.owner=root
	var packed := PackedScene.new();packed.pack(root)
	var path := "res://exports/editor_tests/lamp_editor.tscn";ResourceSaver.save(packed,path);root.free()
	EditorInterface.get_resource_filesystem().update_file(path);EditorInterface.open_scene_from_path(path);EditorInterface.set_main_screen_editor("3D")
	await settle(plugin,20);root=EditorInterface.get_edited_scene_root();lamp=root.get_node("Neon")
	plugin.toggle.button_pressed=true
	var driver: Node=load("res://tools/validate_editor_preview.gd").new();plugin.add_child(driver);driver.process_priority=999
	driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();driver.forced_fov=45
	driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(0,.1,2.5)).looking_at(Vector3(0,.95,0))
	await settle(plugin,15)
	check(plugin.views.has(0) and plugin.views[0].renderer.native_geometry.get_statistics().version>=17,"Editor preview loads native fixture emission support")
	if not plugin.views.has(0):plugin.get_tree().quit(1);return
	var view=plugin.views[0];var rebuilds: int=view.rebuilds;var atlas: int=view.renderer.atlas_texture.get_instance_id()
	check(lamp._surface_count==2 and lamp.local_audio==null and root.find_children("*","AudioStreamPlayer3D",true,false).is_empty(),"Editor displays the fixture model without starting its assigned hum")
	var on: PackedByteArray=view.buffer.get_texture().get_image().get_data()
	lamp.flicker=true;lamp.flicker_amount=0;lamp.flicker_minimum=.25;lamp.flicker_maximum=.25
	await settle(plugin,12)
	var dim: PackedByteArray=view.buffer.get_texture().get_image().get_data()
	check(on!=dim,"Flicker changes the real native editor framebuffer")
	check(view.rebuilds==rebuilds and view.renderer.atlas_texture.get_instance_id()==atlas,"Editor flicker does not rebuild geometry or texture pages")
	var source: Dictionary=view.renderer.world_lights[0]
	var expected: Color=Grade.color(lamp.get_surface_emission(),view.renderer.saturation)
	check(absf(float(source.energy)/lamp.light_energy-.25)<.00001 and Vector3(source.fixture_emission).distance_to(Vector3(expected.r,expected.g,expected.b))<.00001,"Editor glow and vertex lighting share one flicker sample: "+str(source))
	EditorInterface.inspect_object(lamp)
	var fields := {}
	for property in lamp.get_property_list():fields[property.name]=property
	check(fields.has("model_scene") and fields.has("emissive_material_names") and fields.has("local_sound") and fields.has("audio_follows_flicker"),"Inspector exposes model, luminous parts and spatial audio settings")
	check(String(fields.light_type.hint_string).contains("Omni") and String(fields.light_type.hint_string).contains("Spot"),"Existing Omni/Spot/Directional selector remains on the fixture")
	lamp.model_scene=load("res://assets/lighting/models/applique.tscn");await settle(plugin,12)
	check(lamp._surface_count==1 and view.rebuilds>rebuilds and view.renderer.triangle_count>0,"Replacing the fixture model refreshes the actual PSX editor geometry")
	lamp.model_scene=load("res://assets/lighting/models/neon.tscn");lamp.flicker=false;await settle(plugin,12)
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://docs/lamp-editor-preview.png")
	check(not EditorInterface.is_playing_scene(),"Lamp preview works without launching the game")
	check(FileAccess.get_file_as_string(path).length()<6000,"Fixture authoring keeps the scene small")
	driver.free()
	FileAccess.open("res://docs/lamp-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("LAMP_EDITOR_OK " if failures.is_empty() else "LAMP_EDITOR_FAILED ",JSON.stringify(failures));plugin.get_tree().quit(0 if failures.is_empty() else 1)
