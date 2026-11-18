extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new(); viewport.size=Vector2i(320,240)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg=false; viewport.world_3d=World3D.new(); root.add_child(viewport)
	var map: Node3D=load("res://scenes/maps/modular_example.tscn").instantiate(); viewport.add_child(map)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.near=.08; camera.far=45; camera.fov=65
	var renderer: Node2D=load("res://scripts/psx_renderer.gd").new(); viewport.add_child(renderer)
	renderer.ambient_light_color=Color(.55,.55,.55)
	renderer.fog_start=12; renderer.fog_end=35; renderer.setup_editor(map,camera)
	var views := [
		["overview",Vector3(16,17,18),Vector3(6,0,5)],
		["corner",Vector3(3,1.6,3),Vector3(0,1.2,0)],
		["door",Vector3(3,1.6,3),Vector3(6,1.2,3)],
		["window",Vector3(9,1.6,3),Vector3(9,1.6,0)]]
	for entry in views:
		camera.position=entry[1]; camera.look_at(entry[2])
		for frame in 4: renderer.render_editor(); await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.save_png("res://docs/modular-map-"+entry[0]+".png")
	print("MODULAR_RENDER_OK ",renderer.native_geometry.get_statistics())
	viewport.free(); quit()
