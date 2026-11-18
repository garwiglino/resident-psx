extends SceneTree
var game: Node3D
var view: SubViewport

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	view=SubViewport.new()
	view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_game()
	var started := Time.get_ticks_msec()
	for i in 5:
		await process_frame
	RenderingServer.force_draw(false)
	view.get_texture().get_image().save_png("res://docs/gameplay.png")
	Input.action_press("aim")
	for i in 15:
		await process_frame
	RenderingServer.force_draw(false)
	view.get_texture().get_image().save_png("res://docs/aim.png")
	Input.action_release("aim")
	game.pause_game()
	for i in 2:
		await process_frame
	RenderingServer.force_draw(false)
	view.get_texture().get_image().save_png("res://docs/menu.png")
	print("RENDER_REVIEW_OK triangles=",game.psx_renderer.triangle_count," vertices=",game.psx_renderer.vertex_count," elapsed_ms=",Time.get_ticks_msec()-started," cpu_us=",game.psx_renderer.last_process_us)
	paused=false
	game.queue_free()
	await process_frame
	quit()
