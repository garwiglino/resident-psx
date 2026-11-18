extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view := SubViewport.new()
	view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	var perspective := "--perspective" in OS.get_cmdline_user_args()
	if perspective:
		game.psx_renderer.affine_texture_strength=0.0
		game.psx_renderer.apply_render_settings()
	game.set_process_input(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player
	p.set_physics_process(false)
	p.set_process(false)
	var views := [["entry",Vector3(0,.05,6.2),0.0],["corridor",Vector3(0,.05,-1),0.0],
		["left-room",Vector3(-5,.05,-5),-PI/2],["right-room",Vector3(5,.05,-13),PI/2],["end-room",Vector3(0,.05,-23),0.0]]
	for setting in views:
		p.position=setting[1]
		p.rotation.y=setting[2]
		p.reset_camera_follow()
		for frame in 3:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/map-%s%s.png" % ["perspective-" if perspective else "",setting[0]])
	print("SIMPLE_MAP_REVIEW_OK triangles=",game.psx_renderer.triangle_count," cpu_us=",game.psx_renderer.last_process_us," texture_pages=",game.psx_renderer.texture_page_count)
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.08).timeout
	view.queue_free()
	await process_frame
	quit()
