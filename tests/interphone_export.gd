extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	create_timer(20).timeout.connect(func():push_error("Interphone import validation timeout");quit(2));root.get_node("InventoryState").persist_collection=false
	var info: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/props/interphone/source.json"))
	var model: Node3D=load("res://assets/props/interphone/interphone.tscn").instantiate();root.add_child(model)
	var exported: Node3D=model.get_node("Modele");var meshes := model.find_children("*","MeshInstance3D",true,false)
	var buttons: Array=info.nodes.keys().filter(func(name: String):return name.begins_with("interphone_button"))
	check(not meshes.is_empty() and not buttons.is_empty(),"Export contains the body and independently named buttons")
	for name: String in info.nodes:check(exported.has_node(NodePath(info.nodes[name])),"Source node survived export: "+name)
	var bounds := AABB();var first := true
	for mesh: MeshInstance3D in meshes:
		var part: AABB=mesh.global_transform*mesh.mesh.get_aabb();bounds=part if first else bounds.merge(part);first=false
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface);var material: Material=mesh.get_active_material(surface)
			check(arrays[Mesh.ARRAY_TEX_UV].size()==arrays[Mesh.ARRAY_VERTEX].size(),"UVs are present on every surface")
			check(material is StandardMaterial3D and material.albedo_texture!=null and material.specular_mode==BaseMaterial3D.SPECULAR_DISABLED,"Every source page has its PSX texture and no specular")
	check(model.find_children("*","Skeleton3D",true,false).size()==info.skeletons.size(),"A model without an armature needs no invented skeleton")
	var body: MeshInstance3D=exported.get_node(info.nodes.interphone_base);var button: MeshInstance3D=exported.get_node(info.nodes[buttons[0]])
	var body_center: Vector3=(body.global_transform*body.mesh.get_aabb()).get_center();var button_center: Vector3=(button.global_transform*button.mesh.get_aabb()).get_center()
	var axis := bounds.size.min_axis_index();var direction := Vector3.ZERO;direction[axis]=1 if button_center[axis]>=body_center[axis] else -1
	var center := bounds.get_center();var distance := maxf(bounds.size.length()*1.2,.3)
	var buffer := SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	var camera := Camera3D.new();buffer.add_child(camera);camera.position=center+direction*distance;camera.look_at(center,Vector3.UP if axis!=1 else Vector3.FORWARD);camera.fov=45
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();buffer.add_child(renderer);renderer.ambient_light_color=Color(.7,.7,.7);renderer.fog_enabled=false;renderer.setup_editor(model,camera);renderer.render_editor()
	await process_frame;await RenderingServer.frame_post_draw
	var picture := buffer.get_texture().get_image();var visible := 0
	for y in 240:
		for x in 320:
			var color := picture.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b))>.1:visible+=1
	check(renderer.triangle_count>0 and visible>100,"Recovered model is visible in the actual native PSX preview")
	picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/interphone-imported.png")
	for mesh: MeshInstance3D in meshes:mesh.mesh=null
	buffer.queue_free();model.queue_free();await process_frame;await process_frame
	FileAccess.open("res://docs/interphone-import-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures,"meshes":meshes.size(),"buttons":buttons.size(),"visible_pixels":visible,"animations":info.animations.size()},"\t"))
	print("INTERPHONE_IMPORT_OK " if failures.is_empty() else "INTERPHONE_IMPORT_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
