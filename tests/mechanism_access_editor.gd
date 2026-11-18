@tool
extends RefCounted
func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree();tree.create_timer(30).timeout.connect(func():push_error("Access editor validation timeout");tree.quit(2))
	var scene: Node3D=load("res://scenes/inventory/placement_access_example.tscn").instantiate();tree.root.add_child(scene)
	var other: Node3D=load("res://scenes/inventory/placement_access_example.tscn").instantiate();tree.root.add_child(other)
	assert(scene.configuration_error().is_empty() and scene._access==null,"Editor validation never creates runtime components")
	assert(scene.access_settings!=other.access_settings,"Instances keep separately editable access settings")
	var lid: Node3D=scene.get_node("Modele/Charniere");var initial := lid.transform
	assert(scene.get_node("Emplacements/Roue/PointInsertion/PieceInstallee").visible,"Editor keeps authored pieces visible")
	var properties: Dictionary={}
	for property in scene.access_settings.get_property_list():properties[property.name]=property
	for name in ["enabled","initially_open","open_on_interaction","close_policy","animation_player_path","opening_animation","closing_animation","playback_speed","animated_root_path","bone_names","open_event","close_event"]:
		assert(properties.has(name) and properties[name].usage&PROPERTY_USAGE_EDITOR,"Setting must be editable: "+name)
	assert(String(properties.close_policy.hint_string).split(",").size()==4,"Four explicit closing choices")
	var action := WorldAction.new();action.kind=WorldAction.Kind.MECHANISM_STATE;action.mechanism_path=NodePath(".")
	assert(action.validation_error(scene).is_empty(),"Mechanism world action validates without running it in the editor")
	var condition := WorldCondition.new();condition.kind=WorldCondition.Kind.MECHANISM_OPEN;condition.id=&"fixture"
	assert(condition.key()==&"mechanism.fixture.open")
	var buffer := SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;tree.root.add_child(buffer)
	var camera := Camera3D.new();buffer.add_child(camera);camera.global_transform=scene.get_node("CameraFixe").global_transform;camera.fov=45
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();buffer.add_child(renderer);renderer.ambient_light_color=Color(.6,.6,.6);renderer.fog_enabled=false
	renderer.setup_editor(scene,camera);renderer.render_editor();await tree.process_frame;await RenderingServer.frame_post_draw
	assert(renderer.triangle_count>0 and lid.transform.is_equal_approx(initial),"Native PSX editor preview preserves authored lid pose")
	var picture := buffer.get_texture().get_image();picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/mechanism-access-editor.png")
	for model in [scene,other]:
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):mesh.mesh=null
	buffer.queue_free();scene.queue_free();other.queue_free();await tree.process_frame;await tree.process_frame
	print("MECHANISM_ACCESS_EDITOR_OK");tree.quit()
