@tool
extends RefCounted
func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree();tree.create_timer(30).timeout.connect(func():push_error("Animated asset editor validation timed out");tree.quit(2))
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/animated-export-validation.json"))
	var path: String=String(report.fixture).path_join("assets/props/generic_machine/generic_machine.model.scn")
	var packed: PackedScene=load(path);var model: Node3D=packed.instantiate();tree.root.add_child(model)
	var old_scene=plugin.active_scene;var old_settings=plugin.settings_node;plugin.active_scene=model;plugin.settings_node=null
	var settings: Dictionary=plugin._settings();plugin.active_scene=old_scene;plugin.settings_node=old_settings
	assert(settings.ambient_light_color==Color(.6,.6,.6) and not settings.fog_enabled)
	assert(model.find_children("*","Skeleton3D",true,false).size()==1 and model.find_children("*","AnimationPlayer",true,false).size()==1)
	var buffer := SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;tree.root.add_child(buffer)
	var camera := Camera3D.new();buffer.add_child(camera);camera.global_position=Vector3(1.3,1.4,2);camera.look_at(Vector3(0,.7,0));camera.fov=45
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();buffer.add_child(renderer)
	for property in settings:renderer.set(property,settings[property])
	renderer.setup_editor(model,camera);renderer.render_editor()
	await tree.process_frame;await RenderingServer.frame_post_draw
	var picture := buffer.get_texture().get_image();var colored := 0
	for y in 240:
		for x in 320:
			var c := picture.get_pixel(x,y)
			if c.g>c.r+.02 and c.g>c.b+.02:colored+=1
	assert(renderer.triangle_count>0 and colored>20,"Animated model must be visible in the native PSX editor preview")
	picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/animated-export-editor.png")
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):mesh.mesh=null
	buffer.queue_free();model.queue_free();await tree.process_frame;await tree.process_frame
	print("ANIMATED_EXPORT_EDITOR_OK ",colored);tree.quit()
