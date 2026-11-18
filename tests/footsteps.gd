extends SceneTree
const Sync=preload("res://scripts/footstep_sync.gd")
var failures: Array[String]=[]
var report: Dictionary={"clips":[],"controller":[]}
var played: Array=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.set_process_unhandled_input(false)
	var m=p.motion;var sk: Skeleton3D=m.body_skeleton
	await create_timer(.1).timeout
	var configurations: Array=[]
	for clip in m.WALK_DIRECTIONS:configurations.append([clip,1.0,false])
	configurations.append_array([["run",1.0,false],["run",1.1,false],["run",2.0,false],["walk",.5,false],["strafe_left",1.0,true],["backward_right",1.7,true]])
	for config in configurations:
		var clip: String=config[0];var speed: float=config[1];var aiming: bool=config[2]
		m.current="";m.blend_time=0;m.set_aiming(aiming,0);m.play(clip,speed);m.advance_motion(0)
		var sync := Sync.new();sync.setup(sk)
		sync.advance(0,false,p.footstep_contact_height,p.footstep_lift_height,p.footstep_min_interval)
		var duration: float=m.mixer.get_animation(clip).length
		var contacts: Array=[];var count := 0;var previous := -INF;var side := &""
		for tick in ceili(duration*2/speed*60):
			m.advance_motion(1.0/60)
			var index := sync.advance(1.0/60,true,p.footstep_contact_height,p.footstep_lift_height,p.footstep_min_interval)
			if index<0:continue
			var foot: Dictionary=sync.feet[index]
			var time := (tick+1)/60.0
			check(foot.height<=p.footstep_contact_height+.00001,"Every step happens with a sole at ground level: "+clip)
			check(time-previous>=p.footstep_min_interval-.00001,"Transitions cannot create overlapping step bursts")
			previous=time
			if time*speed>duration+.00001:
				count+=1
				check(side==&"" or foot.side!=side,"Steady gait alternates physical feet: "+clip)
				side=foot.side
			contacts.append({"time":time,"source_frame":1+fmod(time*speed,duration)*30,"foot":foot.side,"sole_height_m":foot.height})
		var expected := 10 if clip=="run" else 8
		check(count==expected,"One sound per actual footfall across a full settled loop: %s at %.2fx (%d != %d)" % [clip,speed,count,expected])
		report.clips.append({"clip":clip,"speed":speed,"aiming":aiming,"settled_loop_steps":count,"events":contacts})
	# Keep the same detector through interrupted fades: it reads the visible mix.
	var sync := Sync.new();sync.setup(sk);m.blend_time=.5
	var transitions := ["walk","strafe_left","backward_right","run","forward_left","strafe_right","idle"]
	var mixed := 0
	for tick in 360:
		if tick%30==0:m.play(transitions[(tick/30)%transitions.size()])
		m.advance_motion(1.0/60)
		var index := sync.advance(1.0/60,true,p.footstep_contact_height,p.footstep_lift_height,p.footstep_min_interval)
		if index>=0:
			mixed+=1;check(sync.feet[index].height<=p.footstep_contact_height+.00001,"A crossfade step follows the displayed sole, rather than an incoming clip timer")
	check(mixed>2 and mixed<30,"Interrupted transitions retain a bounded and audible foot-contact cadence")
	m.play("idle")
	for tick in 60:
		m.advance_motion(1.0/60)
		sync.advance(1.0/60,false,p.footstep_contact_height,p.footstep_lift_height,p.footstep_min_interval)
	for tick in 120:
		m.advance_motion(1.0/60)
		check(sync.advance(1.0/60,true,p.footstep_contact_height,p.footstep_lift_height,p.footstep_min_interval)<0,"Idle sway cannot trigger footsteps")
	m.play("run");m.advance_motion(0)
	for tick in 240:
		m.advance_motion(1.0/60)
		check(sync.advance(1.0/60,false,p.footstep_contact_height,p.footstep_lift_height,p.footstep_min_interval)<0,"Silent contacts are consumed instead of queued")
	for tick in 30:check(sync.advance(1.0/60,true,p.footstep_contact_height,p.footstep_lift_height,p.footstep_min_interval)<0,"A frozen pose cannot replay old contacts")
	report.crossfade_steps=mixed
	# Verify the actual controller and audio stream, not just the detector.
	p.footsteps.setup(sk);m.current="";m.blend_time=0;m.set_aiming(false,0);m.play("idle");m.advance_motion(0)
	p.position=Vector3(0,.05,6.2);p.velocity=Vector3.ZERO;p.rotation=Vector3.ZERO;p.reset_camera_follow()
	p.footstepped.connect(func(foot: StringName,position: Vector3):
		check(p.sounds.step.playing,"Contact starts the actual footstep player immediately")
		check(p.sounds.step.stream.is_class("AudioStreamPSX"),"Footsteps keep the existing PS1 source path")
		check(p.is_on_floor() and Vector2(p.get_real_velocity().x,p.get_real_velocity().z).length()>.02,"Footstep requires grounded actual movement")
		played.append({"clip":m.current,"time":m.mixer.current_animation_position,"foot":foot,"position":str(position)}))
	Input.action_press("forward")
	for stage in ["walk","run","aim_walk"]:
		if stage=="run":Input.action_press("sprint")
		if stage=="aim_walk":Input.action_press("aim")
		var before := played.size()
		for tick in 90:await physics_frame;p._physics_process(1.0/60)
		check(played.size()>before,"Actual "+stage+" plays contact-synchronized steps")
		report.controller.append({"stage":stage,"steps":played.size()-before})
	Input.action_release("forward");Input.action_release("sprint");Input.action_release("aim")
	for tick in 60:await physics_frame;p._physics_process(1.0/60)
	var before := played.size()
	for tick in 60:await physics_frame;p._physics_process(1.0/60)
	check(played.size()==before,"Stationary actual controller stays silent")
	p.position=Vector3(100,4,2);p.velocity=Vector3.ZERO;Input.action_press("forward")
	before=played.size()
	for tick in 30:await physics_frame;p._physics_process(1.0/60)
	check(not p.is_on_floor() and played.size()==before,"Airborne controller produces no walking sounds")
	Input.action_release("forward");Input.action_press("left")
	p.position=Vector3(0,.05,2);p.velocity=Vector3.ZERO;p.rotation=Vector3.ZERO;p.reset_camera_follow()
	for tick in 150:await physics_frame;p._physics_process(1.0/60)
	check(absf(p.get_real_velocity().x)<.02,"Wall blocking was actually exercised")
	before=played.size()
	for tick in 60:await physics_frame;p._physics_process(1.0/60)
	check(played.size()==before,"Pushing against a wall does not play in-place footstep loops")
	Input.action_release("left")
	report.played=played;report.failures=failures
	FileAccess.open("res://docs/footsteps-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.08).timeout
	print("FOOTSTEPS_OK: all eight walks, jog speeds, aimed locomotion, actual blended soles, no timer drift, real SPU audio and idle/air/wall guards" if failures.is_empty() else "FOOTSTEPS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
