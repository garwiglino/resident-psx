extends SceneTree
var game: Node3D
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game)
	game.psx_renderer.process_mode=Node.PROCESS_MODE_DISABLED
	await frames(3)
	check(game.state=="playing","Game must start directly")
	check(not game.hud.menu.visible,"No introductory UI")
	check(not game.hud.ammo_label.visible,"Ammo hidden outside aiming")
	var p=game.player
	p.set_process_unhandled_input(false)
	var configured_fov: float=p.camera_fov
	check(absf(p.camera.fov-configured_fov)<.0001,"Configured FOV applied")
	check(absf(p.arm.spring_length-p.camera_offset.z)<.0001,"Configured camera distance")
	check(absf(p.arm.position.x-p.camera_offset.x)<.0001,"Configured camera shoulder offset")
	check(absf(p.camera_pivot.global_position.y-p.global_position.y-p.camera_offset.y)<.02,"Configured camera height")
	check(p.motion.mixer.active,"Character animation playback must be active")
	check(p.motion.mixer.has_animation("strafe_left"),"Strafe clip imported")
	var before: Vector3=p.position
	Input.action_press("forward")
	await frames(40)
	Input.action_release("forward")
	await frames(4)
	check(p.position.z<before.z-.65,"Forward motion relative to camera")
	before=p.position
	Input.action_press("right")
	await frames(30)
	Input.action_release("right")
	check(p.position.x>before.x+.4,"Strafe must translate sideways")
	check(absf(p.rotation.y)<.001,"Strafe must preserve facing")
	p.position=Vector3(3.3,.05,6)
	p.velocity=Vector3.ZERO
	Input.action_press("right")
	await frames(60)
	Input.action_release("right")
	check(p.position.x<3.76,"Wall collision stops player")
	p.position=Vector3(0,.05,6)
	p.velocity=Vector3.ZERO
	Input.action_press("aim")
	await frames(18)
	check(p.aiming,"Right click enters aim")
	check(absf(p.camera.fov-p.aim_camera_fov)<.0001 and p.arm.spring_length<p.camera_offset.z,"Aiming narrows the FOV and moves closer to the shoulder")
	var initial_ammo: int=p.ammo
	p.shoot()
	check(p.ammo==initial_ammo-1,"Shooting consumes one round")
	Input.action_release("aim")
	p.ammo=5
	p.reserve=7
	p.reload_weapon()
	await frames(100)
	check(p.ammo==12 and p.reserve==0,"Reload transfers only available ammunition")
	var enemy=game.enemies[0]
	enemy.position=Vector3(0,0,-2)
	enemy.velocity=Vector3.ZERO
	await frames(2)
	var enemy_health: int=enemy.health
	game.shoot_ray(Vector3(0,1.0,1),Vector3(0,0,-1))
	check(enemy.health==enemy_health-1,"Camera/barrel rays hit enemy")
	for i in 2:
		enemy.take_hit(enemy.position)
	check(enemy.dead and enemy.collision_layer==0,"Dead enemy stops blocking")
	game.nearest={"kind":"exit","label":"","pos":Vector3.ZERO,"node":null}
	game.interact()
	check(game.state=="playing","Exit stays locked without power")
	game.nearest=game.interactables[0]
	game.interact()
	check(game.has_fuse,"Fuse pickup changes state")
	for item in game.interactables:
		if item.kind=="power":
			game.nearest=item
	game.interact()
	check(game.power,"Fuse restores power")
	game.pause_game()
	check(paused and not p.enabled,"Pause suspends game")
	game.start_game()
	check(not paused and p.enabled,"Resume restarts game")
	game.nearest={"kind":"exit","label":"","pos":Vector3.ZERO,"node":null}
	game.interact()
	check(game.state=="won","Powered exit completes zone")
	paused=false
	for audio in game.find_children("*","AudioStreamPlayer",true,false):
		audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("SMOKE_OK: camera, animation, movement, strafe, walls, aim, shot, reload, enemy, pickup, power, pause, exit")
	else:
		print("SMOKE_FAILED ",failures)
	quit(0 if failures.is_empty() else 1)
