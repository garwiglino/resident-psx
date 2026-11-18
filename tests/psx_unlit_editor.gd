@tool
extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 12) -> void:
	for frame in count:await plugin.get_tree().process_frame
func run(plugin: EditorPlugin) -> void:
	plugin.get_tree().create_timer(40).timeout.connect(func():push_error("Unlit editor test timeout");plugin.get_tree().quit(2))
	await settle(plugin,20)
	var root := Node3D.new();root.name="UnlitEditor"
	for index in 2:
		var mesh := MeshInstance3D.new();mesh.name="Unlit" if index==0 else "VertexLit";mesh.mesh=QuadMesh.new();mesh.position.x=-.65 if index==0 else .65
		mesh.material_override=load("res://assets/materials/psx_unlit.tres").duplicate() if index==0 else load("res://scripts/psx_materials.gd").make(Color.WHITE)
		root.add_child(mesh);mesh.owner=root
	var settings: Node=load("res://scripts/levels/psx_level_settings.gd").new();settings.name="ReglagesNiveau";settings.ambient_light_color=Color.BLACK;settings.fog_enabled=false;settings.color_tint=Color.WHITE;settings.saturation=1;settings.brightness=1;root.add_child(settings);settings.owner=root
	var packed := PackedScene.new();packed.pack(root);var path := "res://exports/editor_tests/psx_unlit_scene.tscn";ResourceSaver.save(packed,path);root.free()
	EditorInterface.get_resource_filesystem().update_file(path);EditorInterface.open_scene_from_path(path);EditorInterface.set_main_screen_editor("3D");await settle(plugin,20)
	root=EditorInterface.get_edited_scene_root();plugin.toggle.button_pressed=true
	var driver: Node=load("res://tools/validate_editor_preview.gd").new();plugin.add_child(driver);driver.process_priority=999
	driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();driver.forced_fov=45;driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(0,0,3))
	await settle(plugin,20)
	check(plugin.views.has(0),"PSX viewport opens without starting the game")
	if not plugin.views.has(0):plugin.get_tree().quit(1);return
	var view=plugin.views[0];var mesh: MeshInstance3D=root.get_node("Unlit");var material: Material=mesh.material_override
	check(view.renderer.native_geometry!=null and view.renderer.native_geometry.get_statistics().version>=20,"Real editor viewport loads autonomous-unlit native support")
	var before: Image=view.buffer.get_texture().get_image()
	check(before.get_pixel(100,120).r>.8 and before.get_pixel(220,120).r<.1,"Material is visible without any lamp while ordinary surfaces stay dark")
	EditorInterface.inspect_object(material);var rebuilds: int=view.rebuilds
	material.color=Color(.2,.7,.4);await settle(plugin)
	var colored: Image=view.buffer.get_texture().get_image();check(colored.get_pixel(100,120).g>.6 and colored.get_pixel(100,120).r<.3 and view.rebuilds>rebuilds,"Color inspector control immediately updates the native PSX viewport")
	var image := Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(Color(1,.25,.25,1));material.texture=ImageTexture.create_from_image(image);await settle(plugin)
	var textured: Image=view.buffer.get_texture().get_image();check(textured.get_pixel(100,120).g<colored.get_pixel(100,120).g*.4,"Texture inspector control updates the viewport without an extra checkbox")
	var property_names := PackedStringArray()
	for property in material.get_property_list():
		if property.usage&PROPERTY_USAGE_EDITOR and property.usage&PROPERTY_USAGE_STORAGE:property_names.append(property.name)
	check("color" in property_names and "texture" in property_names and "emission" not in property_names,"Material inspector exposes the autonomous color/texture controls")
	# Dropping the .tres on a mesh assigns a Material override through Godot's normal inspector.
	var other: MeshInstance3D=root.get_node("VertexLit");EditorInterface.inspect_object(other);other.material_override=load("res://assets/materials/psx_unlit.tres");plugin._property_edited(&"material_override");await settle(plugin)
	check(view.buffer.get_texture().get_image().get_pixel(220,120).r>.8,"Assigning the draggable preset to another mesh activates its unlit path")
	check(root.find_children("*","PSXLamp3D",true,false).is_empty() and view.renderer.world_lights.is_empty(),"Editor authoring adds no lamp or helper node")
	check(not EditorInterface.is_playing_scene(),"All material controls work without launching gameplay")
	await RenderingServer.frame_post_draw;var picture: Image=view.buffer.get_texture().get_image();picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/psx-unlit-editor.png")
	driver.free();FileAccess.open("res://docs/psx-unlit-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("PSX_UNLIT_EDITOR_OK " if failures.is_empty() else "PSX_UNLIT_EDITOR_FAILED ",str(failures));plugin.get_tree().quit(0 if failures.is_empty() else 1)
