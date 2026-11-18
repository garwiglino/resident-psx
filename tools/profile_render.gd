extends SceneTree
var game: Node3D
var view: SubViewport
var report: Array[Dictionary]=[]

func _initialize() -> void:
	call_deferred("run")

func stats(values: Array[float]) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values:
		total+=value
	return {"mean":total/maxi(values.size(),1),"p50":values[values.size()/2],"p95":values[mini(int(values.size()*.95),values.size()-1)],"max":values[-1]}

func sample(label: String, count: int) -> void:
	for i in 15:
		await process_frame
	# Performance's physics monitor updates once per second; exclude first scene load.
	await create_timer(1.1).timeout
	var frame_ms: Array[float]=[]
	var geometry_ms: Array[float]=[]
	var submission_ms: Array[float]=[]
	var physics_ms: Array[float]=[]
	var draws: Array[float]=[]
	var previous := Time.get_ticks_usec()
	for i in count:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now-previous)/1000.0)
		previous=now
		geometry_ms.append(game.psx_renderer.last_process_us/1000.0)
		submission_ms.append(game.psx_renderer.last_draw_us/1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var result := {"scenario":label,"native":game.psx_renderer.native_geometry!=null,"triangles":game.psx_renderer.triangle_count,
		"frame_ms":stats(frame_ms),"geometry_ms":stats(geometry_ms),"submission_ms":stats(submission_ms),"physics_ms":stats(physics_ms),"draw_calls":stats(draws)}
	report.append(result)
	print(JSON.stringify(result))

func run() -> void:
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	view=SubViewport.new()
	view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	if not "--current-camera" in OS.get_cmdline_user_args():
		# Compare to the original baseline even if the user is tuning the editor meanwhile.
		game.player.import_blender_camera()
		game.psx_renderer.dithering=true
		game.psx_renderer.apply_render_settings()
	Engine.max_fps=0
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.player.enabled=false
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	await sample("spawn",90)
	game.player.position=Vector3(0,.05,-8)
	await sample("corridor",90)
	game.player.position=Vector3(4,.05,-19)
	game.player.rotation.y=-PI/2
	await sample("atelier",90)
	if "--fallback" in OS.get_cmdline_user_args():
		game.psx_renderer.native_geometry=null
		await sample("script_fallback",6)
	var path := "res://docs/performance-after.json" if "--after" in OS.get_cmdline_user_args() else "res://docs/performance-before.json"
	if "--current-camera" in OS.get_cmdline_user_args():
		path="res://docs/performance-current-camera.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.queue_free()
	await process_frame
	quit()
