extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var map: Node3D=load("res://scenes/examples/inventory_demo.tscn").instantiate();viewport.add_child(map)
	var camera := Camera3D.new();camera.fov=55;viewport.add_child(camera)
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();viewport.add_child(renderer);renderer.ambient_light_color=Color(.7,.7,.7);renderer.fog_enabled=false;renderer.dithering=false
	var stairs: Node3D=map.get_node("stairs_01")
	var model: MeshInstance3D=stairs.get_node("Modele")
	print("STAIRS_MAP_BOUNDS ",model.mesh.get_aabb()," TRANSFORM ",stairs.transform)
	var center := model.mesh.get_aabb().get_center()
	var views := [["map",Vector3(-3,3,4),center], ["isolated",Vector3(-3,3,4),center], ["back",Vector3(3,4,-6),center],["side",Vector3(-4,2.5,-2),center]]
	for view: Array in views:
		camera.position=stairs.to_global(view[1]);camera.look_at(stairs.to_global(view[2]));renderer.setup_editor(map if view[0]=="map" else stairs,camera)
		for frame in 4:renderer.render_editor();await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://docs/stairs-"+view[0]+"-review.png")
	viewport.queue_free();await process_frame;await process_frame;quit()
