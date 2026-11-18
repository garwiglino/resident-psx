extends SceneTree
const Manager=preload("res://scripts/audio/level_audio_manager.gd")
const Profile=preload("res://scripts/audio/level_audio_profile.gd")
const Layer=preload("res://scripts/audio/ambience_layer.gd")
const Cue=preload("res://scripts/audio/audio_cue.gd")
var failures: Array[String]=[]
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func tone(frequency: float) -> AudioStreamWAV:
	var source := AudioStreamWAV.new();source.format=AudioStreamWAV.FORMAT_16_BITS;source.mix_rate=22050
	var bytes := PackedByteArray();bytes.resize(22050*2)
	for i in 22050:bytes.encode_s16(i*2,roundi(sin(i*TAU*frequency/22050)*3000))
	source.data=bytes;return source
func layer(source: AudioStream) -> Resource:
	var result := Layer.new();result.stream=source;result.volume_db=-12;return result
func gain(manager: Node,source: AudioStream) -> float:
	for slot in manager._ambience:
		if slot.source==source:return slot.gain
	return 0
func advance(manager: Node,seconds: float) -> void:
	var remaining := seconds
	while remaining>.000001:
		var step := minf(remaining,.01);manager._process(step);remaining-=step
func physics(count := 4) -> void:
	for index in count:await physics_frame
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false)
	game.player.set_process(false);game.player.set_physics_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.active=false
	var manager=game.level_audio;manager.set_process(false)
	check(manager!=null and manager==game.level.get_node("ReglagesNiveau"),"Level module owns its editable audio manager")
	check(manager.profile.ambience_layers[0].stream.resource_path.ends_with("ambiance/room_tone.wav"),"Main ambience is the supplied room tone")
	# The artist can now assign real music; validate the configured profile
	# instead of requiring the original empty music slots.
	for index in 2:
		var source: AudioStream=manager.profile.exploration_music if index==0 else manager.profile.combat_music
		var prepared: AudioStream=manager._music[index].stream
		if source:check(prepared!=null and prepared.is_class("AudioStreamPSX") and prepared.get("loop") and absf(prepared.get_length()-source.get_length())<.001,"Configured music keeps its source duration and native PSX loop")
		else:check(prepared==null,"An empty music slot never gains an arbitrary track")
	check(manager._ambience[0].player.stream.is_class("AudioStreamPSX"),"Real level ambience uses the native SPU path")
	var imported: AudioStream=manager.profile.ambience_layers[0].stream
	check(not imported.get("loop") and manager._ambience[0].player.stream.get("loop"),"Looping does not mutate the shared imported sound")
	manager.stop_level()
	var main_source := tone(220);var zone_source := tone(330);var priority_source := tone(440)
	var profile := Profile.new();profile.ambience_layers=[layer(main_source)]
	profile.exploration_music=tone(550);profile.combat_music=tone(660)
	profile.crossfade_seconds=.4;profile.combat_release_delay=.5
	var cue := Cue.new();cue.variants=[tone(880),tone(990)];cue.cooldown_seconds=.15;cue.duck_seconds=.3
	profile.cues=[cue];manager.profile=profile;manager.start_level();advance(manager,.5)
	check(absf(gain(manager,main_source)-db_to_linear(-12))<.00001,"Main ambience fades in to its configured level")
	check(manager._music[0].playing and not manager._music[1].playing,"Exploration music plays without combat")
	var zone=load("res://scenes/audio/ambience_zone.tscn").instantiate()
	check(zone.ambience_layers.is_empty(),"Zone template is generic and has no exterior sound assignment")
	zone.ambience_layers.assign([layer(zone_source)]);zone.transition_seconds=.4;zone.position=Vector3(50,0,0)
	game.level.add_child(zone)
	var priority=load("res://scenes/audio/ambience_zone.tscn").instantiate()
	priority.ambience_layers.assign([layer(priority_source)]);priority.audio_priority=5;priority.transition_seconds=.4
	priority.position=Vector3(50,0,0);game.level.add_child(priority)
	# The real player and Area3D physics drive both overlapping zones.
	game.player.global_position=Vector3(50,.05,0);game.player.velocity=Vector3.ZERO;await physics()
	check(manager.active_zone==priority,"Overlapping physics zones select the highest audio priority")
	var before := gain(manager,main_source);advance(manager,.2)
	check(gain(manager,main_source)>0 and gain(manager,main_source)<before and gain(manager,priority_source)>0,"Main and zone overlap during the crossfade")
	check(manager._music[0].playing and not manager.in_combat,"Ambience zones do not replace or restart exploration music")
	manager.leave_zone(zone)
	check(manager.active_zone==priority,"Leaving a covered lower-priority zone does not restore main ambience early")
	manager.enter_zone(zone)
	check(manager.active_zone==priority,"A lower-priority zone cannot take over just by entering later")
	priority.enabled=false;manager._process(0)
	check(manager.active_zone==zone,"Disabling the winning zone reveals the covered zone")
	priority.enabled=true;manager._process(0)
	check(manager.active_zone==priority,"Re-enabling an occupied zone restores its priority")
	priority.free();advance(manager,.5)
	check(manager.active_zone==zone and gain(manager,main_source)==0,"Removing a zone restores the underlying zone, with no default ambience left under it")
	var voice_ids: Array=[]
	for slot in manager._ambience:voice_ids.append(slot.player.get_instance_id())
	for index in 30:
		manager.leave_zone(zone);advance(manager,.005)
		var ongoing := gain(manager,main_source)
		manager.enter_zone(zone)
		check(absf(gain(manager,main_source)-ongoing)<.000001,"An interrupted fade continues from its current gain")
		advance(manager,.005)
	check(manager._ambience.size()==Manager.AMBIENCE_VOICES,"Rapid zone changes never allocate more ambience players")
	for index in voice_ids.size():check(voice_ids[index]==manager._ambience[index].player.get_instance_id(),"Ambience players are reused")
	game.player.global_position=Vector3(45,.05,0);await physics();advance(manager,.5)
	check(manager.active_zone==null and gain(manager,zone_source)==0 and gain(manager,main_source)>0,"Exiting the final zone restores only the main ambience")
	zone.ambience_layers.clear();manager.enter_zone(zone);advance(manager,.5)
	check(gain(manager,main_source)==0,"An intentionally empty zone fades ambience to silence")
	manager.leave_zone(zone);advance(manager,.5)
	# Actual gameplay combat state, not the aim or fire button, controls music.
	var enemy=game.enemies[0];enemy.active=true;enemy.global_position=game.player.global_position+Vector3(0,0,-3)
	game._update_level_audio();advance(manager,.2)
	check(manager.in_combat and manager._music[0].playing and manager._music[1].playing,"A real engaged enemy starts a music crossfade")
	advance(manager,.3)
	check(not manager._music[0].playing and manager._music[1].playing,"Outgoing music stops when its fade reaches zero")
	enemy.dead=true;game._update_level_audio();advance(manager,.3)
	check(manager.in_combat,"Combat release delay avoids abrupt musical changes after the last threat")
	advance(manager,.7)
	check(not manager.in_combat and manager._music[0].playing and not manager._music[1].playing,"Exploration returns after the final enemy and release delay")
	enemy.dead=false;enemy.active=true;enemy.global_position=game.player.global_position+Vector3(0,0,-20)
	game._update_level_audio();advance(manager,.1)
	check(not manager.in_combat,"An alerted enemy far outside the encounter does not keep combat music indefinitely")
	manager.combat_mode=Manager.CombatMode.COMBAT;advance(manager,.5)
	check(manager.in_combat,"Scripted scenes can force combat music")
	manager.combat_mode=Manager.CombatMode.CALM;advance(manager,.5)
	check(not manager.in_combat,"A safe room can force calm music")
	check(manager.play_cue(&"scare") and not manager.play_cue(&"scare"),"Named one-shot effects respect their cooldown")
	var first: AudioStream=manager._global_effects[0].stream
	check(first.is_class("AudioStreamPSX") and not first.get("loop"),"Stingers use one-shot native PSX streams")
	advance(manager,.2)
	check(manager._duck_db< -1 and manager._music[0].playing,"Fear effect ducks music smoothly without stopping its playback")
	check(manager.play_cue(&"scare"),"Effect becomes available again after cooldown")
	check(manager._global_effects[1].stream!=first,"Random effect variants avoid immediate repetition")
	var spatial := Cue.new();spatial.spatial=true;spatial.variants=[tone(770)];spatial.music_duck_db=0
	var point := Vector3(3,2,4)
	check(manager.play_effect(spatial,point) and manager._spatial_effects[0].global_position.is_equal_approx(point),"A spatial scare plays at the actual event position")
	var trigger=load("res://scenes/audio/scare_trigger.tscn").instantiate();trigger.position=Vector3(60,0,0)
	trigger.cue=spatial;game.level.add_child(trigger)
	advance(manager,1.1);check(trigger.trigger() and not trigger.trigger(),"An armed scare trigger fires only once")
	trigger.reset();advance(manager,1.1);check(trigger.trigger(),"A scripted reset can rearm a one-shot trigger")
	trigger.reset();advance(manager,1.1);game.player.global_position=Vector3(60,.05,0);await physics()
	check(trigger.used,"The real player entering a scare volume also triggers its effect")
	for player in manager._global_effects:player.stop()
	cue.cooldown_seconds=0
	for index in Manager.EFFECT_VOICES:check(manager.play_effect(cue),"Available one-shot voice starts")
	check(not manager.play_effect(cue),"Full one-shot pool refuses overlap instead of allocating unbounded voices")
	advance(manager,3)
	check(absf(manager._duck_db)<.05,"Music recovers smoothly after the final duck request expires")
	manager.set_process(true);game.pause_game();await process_frame;await process_frame
	var paused_time: float=manager._ambience_time
	await process_frame;await process_frame
	check(manager._music[0].stream_paused and manager._ambience_time==paused_time,"Pause suspends music, ambience and transition clocks together")
	game.start_game();await process_frame
	check(not manager._music[0].stream_paused,"Resume continues the same audio playback")
	manager.set_process(false)
	var save_path := "user://level-audio-validation.tres"
	check(ResourceSaver.save(profile,save_path)==OK,"Level audio settings serialize as editable resources")
	var restored=ResourceLoader.load(save_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.ambience_layers.size()==1 and restored.cues.size()==1 and restored.combat_music!=null,"Layer, music and cue settings survive save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	game.finish("won")
	check(not manager._running and not manager._music[0].playing,"Leaving the level stops its audio before the game pauses")
	paused=false
	report={"failures":failures,"ambience_pool":manager._ambience.size(),"effect_pools":[manager._global_effects.size(),manager._spatial_effects.size()],"music_players":manager._music.size(),"native_stream":first.get_class()}
	FileAccess.open("res://docs/level-audio-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.1).timeout
	print("LEVEL_AUDIO_OK: SPU ambience, real priority zones, interrupted fades, combat music/release, random stingers, ducking, bounded voices, pause, serialization and cleanup" if failures.is_empty() else "LEVEL_AUDIO_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
