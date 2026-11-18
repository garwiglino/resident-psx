extends SceneTree
var failures: Array[String]=[]
var events: Array=[]
var p: Node
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func step(delta: float) -> void:
	p.motion.advance_motion(0,delta)
	p._apply_upper_body_look()
func clear_shot() -> void:
	p.motion.weapon.deactivate()
	p.weapon_inventory.advance(1)
	p.sounds.shot.stop();p.recoil=0;p._shot_shake_left=0
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.aiming=true;p.motion.set_aiming(true,0);p.motion.advance_motion(0)
	await create_timer(.1).timeout
	var w=p.motion.weapon
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/animations/pistol_fire.json"))
	var delay := 1.0/float(metadata.fps)
	check(absf(w.fire_event_delay-delay)<.00000001,"Shot event uses source image 2: one frame after animation start")
	p.fired.connect(func(_origin: Vector3,_direction: Vector3):
		events.append({"time":w.shot_time,"body_time":p.motion.aim_pose.fire_time,"source_frame":1+w.shot_time*metadata.fps,"sound_playing":p.sounds.shot.playing,"shake":p._shot_shake_left,"flash":w.flash_time_left}))
	clear_shot()
	var ammo_before: int=p.ammo
	check(p.shoot(),"Loaded trigger starts both animations")
	check(p.ammo==ammo_before-1 and w.shot_time==0 and p.motion.aim_pose.fire_time==0,"Trigger consumes one round and starts synchronized animation time zero")
	check(not p.shoot(),"A blocked trigger cannot restart the pending shot")
	game.psx_renderer._process(0)
	check(events.is_empty() and w.flash_time_left==0 and not w.flash_mesh.visible and game.psx_renderer.shot_light_energy==0,"Image 1 contains no flash, light or shot impact")
	check(not p.sounds.shot.playing and p.recoil==0 and p._shot_shake_left==0,"Image 1 contains no firing sound, recoil or shake")
	step(delay-.00001);game.psx_renderer._process(0)
	check(events.is_empty() and w.flash_time_left==0 and not p.sounds.shot.playing and p._shot_shake_left==0,"No effects trigger just before source image 2")
	step(.00001);game.psx_renderer._process(0)
	check(events.size()==1 and absf(w.shot_time-delay)<.000001,"Source image 2 dispatches exactly one shot")
	check(w.flash_time_left>0 and w.flash_mesh.visible and game.psx_renderer.shot_light_energy>0,"Flash and native vertex light begin on image 2")
	check(p.sounds.shot.playing and p.recoil>0 and p._shot_shake_left==p.shot_shake_duration,"Sound, recoil and shake begin with the image-2 event")
	check(not p.get_render_camera_transform().is_equal_approx(p.camera.global_transform),"Image-2 event produces the visual camera kick")
	var flash_origin: Vector3=w.flash_position
	var player_origin: Vector3=p.position
	p.position+=Vector3(.3,0,.2);p.look_yaw+=.2;p._apply_upper_body_look();game.psx_renderer._process(0)
	check(w.flash_mesh.global_position.is_equal_approx(flash_origin),"The flash stays at its world firing position when the player and barrel move")
	check(game.psx_renderer.shot_light_position.is_equal_approx(flash_origin),"The vertex light shares the detached flash position")
	check(w.get_muzzle_transform().origin.distance_to(flash_origin)>.1,"The moving barrel is independent from the flash snapshot")
	check(is_equal_approx(game.psx_renderer.raster.get_shader_parameter("flash_opacity"),.5),"The muzzle flash uses half opacity")
	for entry in game.psx_renderer.entries:
		if entry.node==w.flash_mesh:check((entry.texture_page&32)!=0,"The muzzle sprite carries the translucent packet flag")
	p.position=player_origin;p.look_yaw-=.2;p._apply_upper_body_look()
	for frame in 20:p._apply_upper_body_look()
	check(events.size()==1,"Render updates cannot replay the image-2 event")
	p.sounds.shot.stop();step(.001)
	check(events.size()==1 and not p.sounds.shot.playing,"Shot sound is not restarted after the event")
	var rates: Array=[]
	for fps in [24,30,60,120]:
		clear_shot();var before := events.size()
		check(p.shoot(),"Repeated timing test trigger is accepted")
		var delta: float=1.0/float(fps)
		while w.shot_time+.00000001<delay:
			check(events.size()==before and w.flash_time_left==0 and p._shot_shake_left==0,"Effects never precede the animation event at "+str(fps)+" Hz")
			step(delta)
		check(events.size()==before+1 and w.shot_time>=delay-.00000001 and w.shot_time<delay+delta+.00000001,"First animation step crossing image 2 dispatches the event at "+str(fps)+" Hz")
		check(absf(w.shot_time-p.motion.aim_pose.fire_time)<.000001,"Event and both animation clocks stay synchronized")
		rates.append({"step_hz":fps,"event_time":w.shot_time,"event_key_time":delay})
	# At a fast cadence, the next wind-up must not erase the previous
	# shot's image-2 flash before the renderer can display it.
	clear_shot();p.ammo=8
	var interval: float=p.weapon_definition().shot_interval
	p.weapon_definition().shot_interval=.05
	var burst_before := events.size()
	for tick in 15:
		p.weapon_inventory.advance(1.0/60)
		var before_tick := events.size()
		step(1.0/60)
		if tick%3==0:check(p.shoot(),"Fast-cadence trigger is accepted")
		if events.size()>before_tick:check(w.flash_time_left>0,"The next animation wind-up preserves the previous shot's visible flash")
	step(delay)
	check(events.size()==burst_before+5,"Fast cadence dispatches exactly one image-2 event for each of five triggers")
	p.weapon_definition().shot_interval=interval
	clear_shot();var before := events.size()
	check(p.shoot(),"Cancellation test starts an animation")
	step(delay*.5);w.deactivate();step(delay*2)
	check(events.size()==before and w.flash_time_left==0 and p._shot_shake_left==0 and not p.sounds.shot.playing,"Holstering before image 2 cancels pending shot effects")
	p.ammo=0;p.reserve=0;p.weapon_inventory.advance(1)
	check(not p.shoot() and not w._pending_shot_event,"An empty trigger cannot queue an animation event")
	clear_shot();p.ammo=2;before=events.size()
	check(p.shoot(),"Death-cancellation test starts a valid shot")
	step(delay*.5);p.take_damage(p.health);step(delay)
	game.psx_renderer._process(0)
	check(events.size()==before and w.flash_time_left==0 and game.psx_renderer.shot_light_energy==0 and p._shot_shake_left==0 and not p.sounds.shot.playing,"Death before image 2 cancels flash, light, sound, shake and damage")
	FileAccess.open("res://docs/shot-frame-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"event_frame":2,"source_fps":metadata.fps,"event_time":delay,"events":events,"rates":rates,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.08).timeout
	print("SHOT_FRAME_OK: source image 2 synchronizes flash, vertex light, sound, recoil, shake and shot ray; no early or duplicate event" if failures.is_empty() else "SHOT_FRAME_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
