extends SceneTree
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Pages=preload("res://scripts/dialogue/automatic_pages.gd")
const Cine=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func tone(seconds: float) -> AudioStreamWAV:
	var result := AudioStreamWAV.new();result.format=AudioStreamWAV.FORMAT_16_BITS;result.mix_rate=22050
	var data := PackedByteArray();data.resize(roundi(seconds*22050)*2)
	for frame in data.size()/2:data.encode_s16(frame*2,roundi(sin(TAU*400*frame/22050)*6000))
	result.data=data;return result
func resource(text: String,seconds := 0.0,automatic := true) -> Resource:
	var value := Sequence.new();value.mode=Sequence.Mode.EXPLORATION_CALL if automatic else Sequence.Mode.CONVERSATION
	var line := Line.new();line.text=text;line.audio=tone(seconds) if seconds>0 else null;value.lines.append(line);return value
func finish_manual(controller: Node) -> void:
	for step in 50:
		if not controller.is_active():return
		controller.advance()
func finish_automatic(controller: Node,max_steps := 3000) -> int:
	var steps := 0
	while controller.is_active() and steps<max_steps:
		controller._process(.1)
		if not controller._voice_pending and not controller.voice_audio.speech_complete:controller.voice_audio._voice_finished()
		steps+=1
	return steps
func cinematic(game: Node) -> Node:
	var node := Cine.new();node.name="ExplorationPriorityFixture";game.add_child(node)
	var camera := Camera3D.new();camera.name="CameraA";node.add_child(camera)
	var timeline := AnimationPlayer.new();timeline.name="Timeline";node.add_child(timeline)
	var clip := Animation.new();clip.length=.3;var library := AnimationLibrary.new();library.add_animation(&"cinematic",clip);timeline.add_animation_library(&"",library)
	var shot := Shot.new();shot.progression=Shot.Progression.MANUAL;node.plans.append(shot);return node
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	# Policy: a long recording sets the pace; a short one cannot erase unread text.
	var policy := Pages.new();var settings := Sequence.new();var samples: Array[String]=["Page courte.","Une page plus longue avec davantage de mots a lire."]
	policy.configure(samples,settings,12)
	check(absf(policy.deadlines[-1]-12)<.0001 and policy.durations[1]>policy.durations[0],"Page timing is distributed across the actual WAV duration by text length")
	policy.advance(10,12,true,true);check(not policy.page_ready(0),"A delayed frame cannot count ten invisible seconds as reading time")
	policy.configure(samples,settings,.1)
	check(policy.deadlines[-1]>.1 and policy.minimums[0]>=1.2,"Short audio extends caption reading instead of dropping pages")
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.psx_renderer.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player;var call=game.exploration_dialogue;var manual=game.dialogue
	p.set_process_unhandled_input(false);p.position=Vector3(0,.05,6.2);p.velocity=Vector3.ZERO
	for frame in 30:await physics_frame
	check(call!=manual and call.exploration_channel and call.layer<manual.layer,"Background calls have their own lower-priority presentation channel")
	var source=resource("Appel pendant l'exploration.",4);source.id=&"exploration_actions"
	Input.action_press("aim");Input.action_press("forward")
	for frame in 3:await physics_frame
	var before: Vector3=p.position
	check(game.play_dialogue(source),"Game.play_dialogue dispatches the mode to the proper channel")
	call.set_process(false)
	check(call.is_active() and not manual.is_active() and game.state=="playing" and not p.controls_blocked,"A call leaves gameplay state and controls untouched")
	for frame in 18:call._process(1.0/60);await physics_frame
	check(p.aiming and p.position.distance_to(before)>.1,"Held aim and root-motion walking continue when a call starts")
	check(p.shoot(),"Shooting remains available during the call")
	for frame in 25:call._process(1.0/60);await physics_frame
	Input.action_release("forward");p.ammo=p.magazine_capacity-2;p.reserve=20
	check(p.reload_weapon(),"Reloading remains available during the call")
	await create_timer(p.motion.get_reload_duration()+.12).timeout
	check(p.ammo==p.magazine_capacity and not p.controls_blocked,"The normal player/gun reload finishes while call controls remain free")
	var old_page: int=call.page_index;var old_line: int=call.line_index;var old_visible: int=call.view.body.visible_characters
	var confirm := InputEventAction.new();confirm.action=&"dialogue_advance";confirm.pressed=true
	call._input(confirm);call.advance()
	check(call.page_index==old_page and call.line_index==old_line and call.view.body.visible_characters==old_visible,"Interaction/confirmation input cannot reveal or skip an automatic call")
	call.cancel();await physics_frame
	check(p.aiming and not p.action_input_blocked() and game.state=="playing","Ending a call does not install a held-action release guard")
	Input.action_release("aim")
	# Natural WAV completion, not an unrelated dialogue timer, permits the next reply.
	var natural=resource("Premiere voix.",1.5);natural.lines.append(resource("Seconde voix.",.3).lines[0])
	game.play_dialogue(natural);call.set_process(false);call._process(.2)
	for frame in 100:call._process(.1)
	check(call.line_index==0 and call.voice_audio.voice.playing,"Fast simulated UI time cannot pass a still-playing WAV")
	var deadline := Time.get_ticks_msec()+7000
	while call.is_active() and Time.get_ticks_msec()<deadline:
		await physics_frame;call._process(1.0/60)
	check(not call.is_active(),"Real WAV completion advances all replies and closes the call automatically")
	# Long reply: every page is shown in order, with one unbroken voice playback.
	var long_text := "Le porte-parole regarde l'arriere-plan du couloir. ".repeat(8)
	var long_call=resource(long_text,.2);var expected: Array[String]=[];var shown: Array[int]=[];var starts: Array[bool]=[]
	var page_listener := func(_line: Resource,index: int):shown.append(index)
	var voice_listener := func(phase: int):if phase==call.voice_audio.Phase.VOICE:starts.append(true)
	call.page_revealed.connect(page_listener);call.voice_audio.phase_changed.connect(voice_listener)
	game.play_dialogue(long_call);call.set_process(false);expected.assign(call._pages)
	check(expected.size()>2,"Long automatic reply uses multiple word-wrapped pages")
	var steps := finish_automatic(call)
	check(not call.is_active() and shown.size()==expected.size() and starts.size()==1,"All long-reply pages complete without replaying their WAV")
	for index in shown.size():check(shown[index]==index,"Automatic page order never skips or repeats a page")
	check(steps*.1>=long_text.length()/long_call.reading_characters_per_second,"Short speech still allows enough time to read the full long reply")
	call.page_revealed.disconnect(page_listener);call.voice_audio.phase_changed.disconnect(voice_listener)
	game.play_dialogue(resource("Une replique sans voix, avec lecture automatique."));call.set_process(false)
	check(finish_automatic(call)<3000 and not call.is_active(),"Missing WAV falls back to a readable text duration without stalling")
	# The simulated UI loops above queue many letter ticks without real frames.
	# Drain those test-only ticks before checking a genuinely playing SPU voice.
	call.letter_audio.stop();await create_timer(.25).timeout
	# Conversations and cinematics preempt the call by pausing, not restarting it.
	var priority=resource("Un appel interrompu temporairement.",5);priority.id=&"priority_call"
	game.play_dialogue(priority);call.set_process(false);call._process(.2);await create_timer(.12).timeout
	check(call.voice_audio.voice.playing,"Priority fixture starts an actual five-second voice")
	var position: float=call.voice_audio.voice.get_playback_position();var page_time: float=call._automatic.page_elapsed
	game.play_dialogue(resource("Conversation manuelle.",0,false));manual.set_process(false)
	check(manual.is_active() and call.suspended and not call.view.visible and p.controls_blocked,"Manual conversation takes priority and pauses the exploration call")
	call._process(2);await create_timer(.15).timeout
	check(call._automatic.page_elapsed==page_time and absf(call.voice_audio.voice.get_playback_position()-position)<.08,"Paused calls preserve their text and audio positions")
	finish_manual(manual)
	check(not call.suspended and call.is_active() and not p.controls_blocked,"The same call resumes after conversation confirmation")
	var cine := cinematic(game)
	check(game.play_cinematic(cine),"A cinematic can start while an exploration call is active")
	game.cinematics.set_process(false)
	check(call.suspended and game.state=="cinematic","Camera ownership temporarily suspends background call presentation")
	var queued=resource("Appel suivant.");queued.id=&"queued_call"
	check(game.play_dialogue(queued),"New calls queue safely behind a paused call")
	game.cinematics.cancel()
	check(not call.suspended and call.current_sequence.id==&"priority_call","Cinematic return resumes the original call rather than starting it over")
	game.pause_game();page_time=call._automatic.page_elapsed;call._process(5)
	check(call._automatic.page_elapsed==page_time and call.voice_audio.voice.stream_paused,"Real pause freezes both automatic page timing and audio: "+str({"suspended":call.suspended,"playing":call.voice_audio.voice.playing,"phase":call.voice_audio.phase,"complete":call.voice_audio.speech_complete,"position":call.voice_audio.voice.get_playback_position(),"paused":call.voice_audio.voice.stream_paused,"page_time":call._automatic.page_elapsed,"old_page_time":page_time}))
	game.start_game();call.set_process(false);finish_automatic(call)
	check(not call.is_active() and call._queue.is_empty() and game.state=="playing","Resumed queued calls finish without leaking control ownership")
	game.play_dialogue(resource("Conversation prioritaire.",0,false));manual.set_process(false)
	check(game.play_dialogue(resource("Appel differe.")) and not call.is_active() and call._queue.size()==1,"A call triggered under a conversation waits without taking over its window")
	finish_manual(manual);call.set_process(false)
	check(call.is_active() and not call.suspended,"The deferred call starts once the conversation releases its presentation")
	finish_automatic(call)
	# Automatic text in a cinematic belongs to its reserved main channel.
	var automatic_cine := cinematic(game);automatic_cine.plans[0].progression=Shot.Progression.LINKED
	automatic_cine.plans[0].dialogue=resource("Texte automatique du plan.")
	check(game.play_cinematic(automatic_cine),"A cinematic accepts a dialogue resource in automatic mode")
	game.cinematics.set_process(false);manual.set_process(false);game.cinematics._process(.4)
	check(manual.is_active() and manual.is_automatic() and not call.is_active(),"Cinematic-owned automatic text stays attached to its camera plan")
	finish_automatic(manual)
	check(not game.cinematics.is_active() and game.state=="playing","Automatic completion advances the linked cinematic without manual confirmation")
	# Actual trigger dispatch and termination during death.
	var trigger=load("res://scenes/dialogue/dialogue_trigger.tscn").instantiate();trigger.sequence=resource("Appel de zone.",3);game.level.add_child(trigger)
	trigger.global_position=p.global_position+Vector3(10,0,0)
	for frame in 3:await physics_frame
	check(not trigger.used and not call.is_active(),"The dialogue zone waits until the player enters its volume")
	trigger.global_position=p.global_position
	for frame in 4:await physics_frame
	check(trigger.used and call.is_active() and not manual.is_active(),"Physical entry into the prefab box starts the exploration call automatically")
	check(not p.controls_blocked and not game.cinematics.is_active() and game.state=="playing" and game.psx_renderer.camera==p.camera,"An exploration dialogue zone keeps gameplay and the player camera, without launching a cinematic")
	call.set_process(false);p.invincible=0;p.take_damage(p.max_health);await process_frame;await process_frame
	check(not call.is_active() and call._queue.is_empty() and game.state=="dead","Death cancels background voices and queued calls")
	paused=false
	FileAccess.open("res://docs/exploration-dialogue-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"long_reply_pages":expected.size(),"long_reply_voice_starts":starts.size(),"long_reply_simulated_seconds":steps*.1},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free();await process_frame;await create_timer(.15).timeout
	print("EXPLORATION_DIALOGUE_OK: two modes, uninterrupted gameplay, WAV-paced automatic replies/pages, fallback reading, priority suspension/resume, queues, pause, triggers and death" if failures.is_empty() else "EXPLORATION_DIALOGUE_FAILED "+str(failures));quit(0 if failures.is_empty() else 1)
