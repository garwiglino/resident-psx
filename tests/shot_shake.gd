extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.psx_renderer.set_process(false)
	var p=game.player;p.set_process(false);p.set_physics_process(false)
	check(p.get_render_camera_transform().is_equal_approx(p.camera.global_transform),"No shake at rest")
	var aim: Transform3D=p.camera.global_transform
	p.shoot()
	check(p.get_render_camera_transform().is_equal_approx(aim),"Animation image 1 has no early shake")
	p.motion.advance_motion(0,p.motion.weapon.fire_event_delay);p._apply_upper_body_look()
	var kick: Transform3D=p.get_render_camera_transform()
	check(not kick.is_equal_approx(aim),"Animation image 2 produces a visible kick")
	check(kick.origin.distance_to(aim.origin)<.01,"Default kick is less than one centimetre")
	check(kick.basis.get_rotation_quaternion().angle_to(aim.basis.get_rotation_quaternion())<deg_to_rad(.4),"Default rotation kick is subtle")
	check(p.camera.global_transform.is_equal_approx(aim),"Shake leaves aiming camera unchanged")
	var peak := 0.0
	for frame in 20:
		p._shot_shake_left=maxf(p._shot_shake_left-1.0/120,0)
		var current: Transform3D=p.get_render_camera_transform()
		peak=maxf(peak,current.origin.distance_to(aim.origin))
	check(p.get_render_camera_transform().is_equal_approx(aim),"Kick returns exactly to rest within 120 ms")
	p.ammo=0;p.reserve=0;p.shoot()
	check(p._shot_shake_left==0,"Empty magazine does not shake camera")
	p.ammo=5
	for shot in 5:
		p.weapon_inventory.advance(.3)
		check(p.shoot(),"Repeated test shots clear the weapon cooldown")
		p.motion.advance_motion(0,p.motion.weapon.fire_event_delay);p._apply_upper_body_look()
	check(p.get_render_camera_transform().origin.distance_to(aim.origin)<.01,"Repeated shots do not accumulate shake")
	p.shot_shake_strength=0
	check(p.get_render_camera_transform().is_equal_approx(aim),"Shake can be disabled")
	FileAccess.open("res://docs/shot-shake-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"peak_translation_m":peak,"duration_s":p.shot_shake_duration,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.08).timeout
	game.queue_free();await process_frame
	await create_timer(.08).timeout
	print("SHOT_SHAKE_OK: image-2 bounded kick, subtle amplitude, short recovery, unchanged aim, empty magazine, no accumulation" if failures.is_empty() else "SHOT_SHAKE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
