extends SceneTree
var game: Node3D
var view: SubViewport
var results: Array[Dictionary]=[]

func _initialize() -> void:
	call_deferred("run")

func summary(values: Array[float]) -> Dictionary:
	values.sort()
	var total := 0.0
	for v in values:
		total+=v
	return {"mean":total/values.size(),"p95":values[mini(int(values.size()*.95),values.size()-1)],
		"p99":values[mini(int(values.size()*.99),values.size()-1)],"max":values[-1]}

func scenario(label: String,pos: Vector3,yaw: float,rotate: bool=false,run_forward: bool=false) -> void:
	var p=game.player
	p.position=pos
	p.rotation.y=yaw
	p.velocity=Vector3.ZERO
	p.health=100000
	if run_forward:
		Input.action_press("forward")
		Input.action_press("sprint")
	for i in 20:
		await process_frame
	var frame_ms: Array[float]=[]
	var cpu_ms: Array[float]=[]
	var submit_ms: Array[float]=[]
	var draws: Array[float]=[]
	var triangle_counts: Array[float]=[]
	var previous := Time.get_ticks_usec()
	for i in 180:
		if rotate:
			p.rotation.y=yaw+TAU*i/180.0
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now-previous)/1000.0)
		previous=now
		cpu_ms.append(game.psx_renderer.last_process_us/1000.0)
		submit_ms.append(game.psx_renderer.last_draw_us/1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		triangle_counts.append(game.psx_renderer.triangle_count)
	Input.action_release("forward")
	Input.action_release("sprint")
	var row := {"scenario":label,"frame_ms":summary(frame_ms),"geometry_ms":summary(cpu_ms),"submit_ms":summary(submit_ms),"draw_calls":summary(draws),"triangles":summary(triangle_counts)}
	results.append(row)
	print(JSON.stringify(row))

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	view=SubViewport.new()
	view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	Engine.max_fps=0
	await create_timer(1.0).timeout
	await scenario("spawn",Vector3(0,.05,6.2),0)
	await scenario("corridor",Vector3(0,.05,-8),0)
	await scenario("exit",Vector3(0,.05,-27),0)
	await scenario("side_room",Vector3(4,.05,-19),-PI/2)
	await scenario("rotate_spawn",Vector3(0,.05,6.2),0,true)
	await scenario("rotate_center",Vector3(0,.05,-13),0,true)
	await scenario("running",Vector3(0,.05,5),0,false,true)
	var name := "stress-baseline" if "--baseline" in OS.get_cmdline_user_args() else "stress-optimized"
	var worst_p99 := 0.0
	var worst_frame := 0.0
	for row in results:
		worst_p99=maxf(worst_p99,row.frame_ms.p99)
		worst_frame=maxf(worst_frame,row.frame_ms.max)
	var report := {"camera_fov":game.player.camera_fov,"camera_offset":str(game.player.camera_offset),"resolution":[320,240],
		"samples_per_scenario":180,"worst_p99_ms":worst_p99,"worst_frame_ms":worst_frame,"all_p99_under_60fps_budget":worst_p99<1000.0/60.0,"results":results}
	FileAccess.open("res://docs/%s.json" % name,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):
		audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	quit(1 if "--assert-budget" in OS.get_cmdline_user_args() and worst_p99>=1000.0/60.0 else 0)
