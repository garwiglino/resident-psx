@tool
extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(plugin: EditorPlugin,count := 12) -> void:
	for frame in count:await plugin.get_tree().process_frame
func box(root: Node3D,name: String,size: Vector3,position: Vector3,material: Material) -> void:
	var node := MeshInstance3D.new();node.name=name;node.mesh=BoxMesh.new();node.mesh.size=size;node.position=position;node.material_override=material;root.add_child(node);node.owner=root
func run(plugin: EditorPlugin) -> void:
	plugin.get_tree().create_timer(50).timeout.connect(func():push_error("Shaft editor validation timeout");plugin.get_tree().quit(2));await settle(plugin,20)
	var root := Node3D.new();root.name="FenetreAvecFaisceaux"
	var material: Material=load("res://scripts/psx_materials.gd").make(Color(.28,.32,.35))
	box(root,"Sol",Vector3(6,.15,6),Vector3(0,-.075,-2.9),material)
	box(root,"MurBas",Vector3(6,1,.15),Vector3(0,.5,.08),material)
	box(root,"MurHaut",Vector3(6,.7,.15),Vector3(0,2.65,.08),material)
	for x in [-2.4,0.0,2.4]:box(root,"Pan"+str(x),Vector3(1.2,1.3,.15),Vector3(x,1.65,.08),material)
	var outside: Material=load("res://assets/materials/psx_unlit.tres").duplicate();outside.color=Color(.35,.4,.5)
	for index in 2:
		var x := -1.2 if index==0 else 1.2
		box(root,"Exterieur"+str(index),Vector3(1.2,1.3,.02),Vector3(x,1.65,.18),outside)
		var effect: Node3D=load("res://scenes/effects/window_light_shaft.tscn" if index==0 else "res://scenes/effects/window_light_rays.tscn").instantiate();effect.name="Faisceau" if index==0 else "Rayons";effect.position=Vector3(x,1.65,-.03);root.add_child(effect);effect.owner=root
	var settings: Node=load("res://scripts/levels/psx_level_settings.gd").new();settings.name="ReglagesNiveau";settings.ambient_light_color=Color(.35,.35,.35);settings.fog_enabled=false;settings.color_tint=Color.WHITE;settings.saturation=1;settings.brightness=1;root.add_child(settings);settings.owner=root
	var packed := PackedScene.new();packed.pack(root);var path := "res://exports/editor_tests/window_light_shafts.tscn";ResourceSaver.save(packed,path);root.free()
	EditorInterface.get_resource_filesystem().update_file(path);EditorInterface.open_scene_from_path(path);EditorInterface.set_main_screen_editor("3D");await settle(plugin,20)
	root=EditorInterface.get_edited_scene_root();plugin.toggle.button_pressed=true
	var driver: Node=load("res://tools/validate_editor_preview.gd").new();plugin.add_child(driver);driver.process_priority=999;driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d();driver.forced_fov=55
	driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(3.8,2.05,-5)).looking_at(Vector3(0,1.1,-1.3));await settle(plugin,20)
	check(plugin.views.has(0),"Window effects render in the real PSX editor viewport")
	if not plugin.views.has(0):plugin.get_tree().quit(1);return
	var view=plugin.views[0];var effect: MeshInstance3D=root.get_node("Faisceau");var ray: MeshInstance3D=root.get_node("Rayons")
	check(view.renderer.native_geometry!=null and view.renderer.native_geometry.get_statistics().version>=21,"Editor uses native ordered quarter-add transparency")
	check(effect.mesh!=null and ray.mesh!=null and view.renderer.primitives.any(func(packet: Dictionary):return packet.blend_mode==1),"All prefab meshes and their additive materials appear without playing the game")
	var before: PackedByteArray=view.buffer.get_texture().get_image().get_data();var rebuilds: int=view.rebuilds
	EditorInterface.inspect_object(effect);effect.length=2.4;effect.end_offset=Vector2(0,-.6);await settle(plugin)
	check(view.rebuilds>rebuilds and view.buffer.get_texture().get_image().get_data()!=before,"Changing dimensions rebuilds UV geometry and the PSX preview live")
	EditorInterface.inspect_object(effect.shaft_material);effect.shaft_material.color=Color(1,.65,.35);effect.shaft_material.strength=1.1;await settle(plugin)
	var fields := PackedStringArray()
	for property in effect.shaft_material.get_property_list():
		if property.usage&PROPERTY_USAGE_EDITOR and property.usage&PROPERTY_USAGE_STORAGE:fields.append(property.name)
	check("color" in fields and "texture" in fields and "strength" in fields,"Inspector offers texture, color and strength on the ray material")
	check(ray.shaft_material.color!=effect.shaft_material.color,"Each instance keeps its own material color")
	effect.shape=1;effect.ray_count=2;await settle(plugin)
	var fields_node := PackedStringArray()
	for property in effect.get_property_list():
		if property.usage&PROPERTY_USAGE_EDITOR:fields_node.append(property.name)
	check("ray_count" in fields_node and "ray_width" in fields_node,"Choosing narrow rays exposes count and width")
	check(not EditorInterface.is_playing_scene(),"Window ray authoring never launches gameplay")
	effect.shape=0;effect.length=4;effect.end_offset=Vector2(0,-1.5);effect.shaft_material.color=Color(.8,.86,1);effect.shaft_material.strength=.8;await settle(plugin)
	await RenderingServer.frame_post_draw;var picture: Image=view.buffer.get_texture().get_image();picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/window-light-shafts-editor.png")
	driver.free();FileAccess.open("res://docs/light-shafts-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures},"\t"))
	print("LIGHT_SHAFTS_EDITOR_OK " if failures.is_empty() else "LIGHT_SHAFTS_EDITOR_FAILED ",str(failures));plugin.get_tree().quit(0 if failures.is_empty() else 1)
