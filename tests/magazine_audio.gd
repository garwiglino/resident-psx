extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={"assets":[],"players":[]}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func audit_assets(directory: String) -> void:
	for child in DirAccess.get_directories_at(directory):audit_assets(directory.path_join(child))
	for file in DirAccess.get_files_at(directory):
		if file.get_extension().to_lower() not in ["wav","ogg","mp3"]:continue
		var path := directory.path_join(file)
		var config := ConfigFile.new();config.load(path+".import")
		if config.get_value("remap","importer","")=="wav":check(int(config.get_value("params","compress/mode",-1))==0,"WAV reaches the SPU encoder without extra Godot compression: "+path)
		var source: AudioStream=load(path)
		var prepared: AudioStream=root.get_node("PSXAudio").prepare(source)
		check(prepared.is_class("AudioStreamPSX") and prepared.get("adpcm_left").size()>0,"Every sound asset has actual SPU ADPCM data: "+path)
		check(prepared.get("mix_rate")<=44100,"SPU source rate is at most 44100 Hz")
		report.assets.append({"path":path,"rate":prepared.get("mix_rate"),"adpcm_bytes":prepared.get("adpcm_left").size()})
func place(drop: Dictionary,position: Vector3,velocity: Vector3,rotation := Vector3.ZERO) -> void:
	drop.body.freeze=true;drop.body.disarm_impact()
	drop.body.global_transform=Transform3D(Basis.from_euler(rotation),position)
	drop.body.linear_velocity=Vector3.ZERO;drop.body.angular_velocity=Vector3.ZERO
	drop.body.arm_impact();drop.body.freeze=false;drop.body.sleeping=false
	drop.body.linear_velocity=velocity;drop.life=8.0
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.position=Vector3(0,.05,4);p.rotation=Vector3.ZERO;p.reset_camera_follow()
	var m=p.motion;var weapon=m.weapon;var magazines=weapon.magazines
	await create_timer(.1).timeout
	audit_assets("res://assets/audio")
	check(AudioServer.get_mix_rate()==44100,"Game output is 44100 Hz")
	var reverb := false
	for slot in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0,slot).is_class("AudioEffectPSXReverb"):reverb=true
	check(reverb,"All buses reach the shared SPU output stage")
	check(AudioServer.get_bus_index(&"PSX Reverb")>0,"Weapon sounds retain the shared SPU reverb send")
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D","AudioStreamPlayer3D"]:
		for audio in game.find_children("*",type,true,false):
			if not audio.stream:continue
			check(audio.stream.is_class("AudioStreamPSX"),"Every configured gameplay player uses native PSX audio: "+String(audio.name))
			report.players.append(String(audio.get_path()))
	check(p.weapon_definition().reload_sound.resource_path=="res://assets/audio/weapons/d_eagle/deagle_reload.wav","Desert Eagle uses the requested reload source")
	check(load("res://scripts/audio/psx_audio_routing.gd").source_of(p.sounds.reload.stream)==root.get_node("PSXAudio").prepare(p.weapon_definition().reload_sound),"Reload plays the prepared SPU version of deagle_reload")
	check(weapon.magazine_floor_sound.resource_path=="res://assets/audio/weapons/mag_floor.wav","Magazine impact uses the supplied mag_floor recording")
	check(weapon._magazine_floor_players.size()==4,"Magazine floor voices are bounded and preallocated")
	var voice_ids: Array=[]
	for audio in weapon._magazine_floor_players:voice_ids.append(audio.get_instance_id())
	p.ammo=1;p.reserve=5
	check(p.reload_weapon() and p.sounds.reload.playing,"Accepted reload starts the new reload sound")
	check(weapon._magazine_floor_cursor==0,"Reload start does not play the floor impact")
	m.advance_motion(0,5.0/24);p._apply_upper_body_look()
	var drop: Dictionary=magazines.drops[0]
	for tick in 10:await physics_frame
	check(weapon._magazine_floor_cursor==0 and not drop.body.floor_sound_played,"Airborne magazine remains silent")
	var fall_ticks := 10
	while weapon._magazine_floor_cursor==0 and fall_ticks<120:
		await physics_frame;fall_ticks+=1
	check(weapon._magazine_floor_cursor==1 and drop.body.floor_sound_played,"Actual first rigid-body floor contact plays one sound")
	var impact: Vector3=weapon._magazine_floor_players[0].global_position
	check(absf(impact.y)<.025 and impact.distance_to(drop.body.impact_position)<.001,"Sound is placed at the actual ground contact")
	check(weapon._magazine_floor_players[0].playing,"Magazine impact starts the actual 3D audio voice")
	p.position.x+=.5;p._apply_upper_body_look()
	check(weapon._magazine_floor_players[0].global_position.is_equal_approx(impact),"Impact audio stays at the floor when the player moves")
	for tick in 45:await physics_frame
	check(weapon._magazine_floor_cursor==1,"Resting contacts and bounces never replay the sample")
	var wall := StaticBody3D.new();var collider := CollisionShape3D.new();var shape := BoxShape3D.new()
	shape.size=Vector3(.1,2,1);collider.shape=shape;wall.add_child(collider);wall.position=Vector3(.35,1,2);root.add_child(wall)
	await physics_frame;await physics_frame
	var walls: Array=[];var second: Dictionary=magazines.drops[1]
	second.body.body_entered.connect(func(body: Node):
		if body==wall:walls.append(body.get_instance_id()))
	place(second,Vector3(0,1.3,2),Vector3(3,0,0))
	for tick in 15:await physics_frame
	check(not walls.is_empty(),"Magazine wall collision was actually exercised")
	check(weapon._magazine_floor_cursor==1 and not second.body.floor_sound_played,"A wall hit cannot trigger the floor recording")
	var ticks := 0
	while weapon._magazine_floor_cursor==1 and ticks<120:await physics_frame;ticks+=1
	check(weapon._magazine_floor_cursor==2 and second.body.floor_sound_played,"Floor contact after a wall still produces its one impact")
	for index in 4:
		var pooled: Dictionary=magazines.drops[index]
		var before: int=weapon._magazine_floor_cursor
		place(pooled,Vector3(-.5,.65,2),Vector3(0,-1,0),Vector3(.4,.2,1.7))
		ticks=0
		while weapon._magazine_floor_cursor==before and ticks<120:await physics_frame;ticks+=1
		check(weapon._magazine_floor_cursor==(before+1)%4 and pooled.body.floor_sound_played,"A reused, rotating magazine resets its one-shot impact")
	for index in 4:check(weapon._magazine_floor_players[index].get_instance_id()==voice_ids[index],"Impacts reuse the prepared audio pool")
	var before: int=weapon._magazine_floor_cursor
	place(drop,Vector3(-.5,.4,2),Vector3(0,-3,0));weapon.deactivate()
	for tick in 30:await physics_frame
	check(weapon._magazine_floor_cursor==before and not drop.body.impact_armed,"Clearing a magazine cancels any future floor event")
	report.first_floor_tick=fall_ticks;report.impact=str(impact);report.voice_pool=voice_ids.size();report.failures=failures
	FileAccess.open("res://docs/magazine-audio-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;wall.queue_free();game.queue_free();await process_frame;await create_timer(.08).timeout
	print("MAGAZINE_AUDIO_OK: deagle reload, physical ground-only one-shot impact, world position, reused voices, cancellation and complete gameplay SPU audit" if failures.is_empty() else "MAGAZINE_AUDIO_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
