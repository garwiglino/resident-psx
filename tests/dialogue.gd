extends SceneTree
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Controller=preload("res://scripts/dialogue/dialogue_controller.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
var failures: Array[String]=[]
var letters: Array[String]=[]
var opened := 0
var closed := 0
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func sequence(lines: Array[String],id: StringName=&"test") -> Resource:
	var result := Sequence.new();result.id=id
	for text in lines:
		var line := Line.new();line.speaker="Policière";line.text=text;result.lines.append(line)
	return result
func advance_time(controller: Node,seconds: float) -> void:
	var left := seconds
	while left>.000001:
		var step := minf(left,.01);controller._process(step);left-=step
func action(pressed: bool) -> InputEventAction:
	var event := InputEventAction.new();event.action=&"dialogue_advance";event.pressed=pressed;return event
func finish_all(controller: Node) -> void:
	var limit := 0
	while controller.is_active() and limit<200:controller.advance();limit+=1
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.psx_renderer.set_process(false)
	var controller=game.dialogue;var player=game.player
	check(not controller.is_active() and not controller.view.visible and game.state=="playing","No unsolicited dialogue or intro window at startup")
	controller.session_started.connect(func():opened+=1)
	controller.session_finished.connect(func():closed+=1)
	controller.letter_revealed.connect(func(character: String):letters.append(character))
	controller.style=controller.style.duplicate()
	controller.style.characters_per_second=20
	game.enemies[1].set_physics_process(false)
	# Let the player settle onto the floor before checking blocked controls.
	for index in 5:await physics_frame
	var actor_position: Vector3=player.position
	check(not game.play_dialogue(sequence([" ","\n"])) and not controller.is_active(),"Empty content is refused without opening a modal session")
	var first=sequence(["Ab c! 12...","Deuxieme ligne."])
	check(game.play_dialogue(first),"Typed resource starts a dialogue")
	controller.set_process(false)
	check(game.state=="dialogue" and player.enabled and player.controls_blocked and player.is_physics_processing(),"Dialogue blocks controls without disabling player simulation")
	check(game.enemies[0].is_physics_processing() and not paused,"Enemies and the rest of the world keep simulating")
	check(Routing.source_of(controller.window_audio.stream)==controller._opening_stream and controller.window_audio.playing,"Opening plays its own quiet one-shot")
	for source in [controller._opening_stream,controller._closing_stream]:
		check(source.is_class("AudioStreamPSX") and source.get("mix_rate")==22050 and not source.get("loop") and source.get_length()<.1,"Window tones are short real SPU samples")
		var window_playback=source.instantiate_playback();window_playback.start()
		var window_samples: PackedVector2Array=window_playback.mix_audio(1,4096);var window_peak := 0.0
		for sample in window_samples:window_peak=maxf(window_peak,maxf(absf(sample.x),absf(sample.y)))
		window_playback.stop()
		check(window_peak>.01 and window_peak*db_to_linear(controller.window_audio.volume_db)<.04,"Both SPU window sounds contain a restrained audible signal")
	check(player.process_mode==Node.PROCESS_MODE_PAUSABLE,"Player collisions and sensors stay registered")
	check(controller.view.visible and controller.view.speaker.text=="POLICIERE" and controller.view.body.visible_characters==0,"Window and speaker appear before the first text glyph, without accents")
	controller._process(.06)
	check(controller.view.body.visible_characters==0,"Opening delay keeps the text empty")
	advance_time(controller,1.5)
	check(controller.state==Controller.State.WAITING and "".join(letters)=="Abc12","Typewriter reveals letters in order and does not beep on spaces or punctuation")
	check(controller.view.indicator==controller.View.Indicator.NEXT,"Completed page shows next marker")
	check(controller.letter_audio.stream.is_class("AudioStreamPSX") and controller.letter_audio.stream.get("mix_rate")==22050 and not controller.letter_audio.stream.get("loop"),"Letter sample uses the real PSX SPU source path, not a procedural mixer bypass")
	check(controller.letter_audio.volume_db<=-30 and controller.letter_audio.max_polyphony==1,"Very quiet letter sound cannot stack into loud bursts")
	var playback=Routing.source_of(controller.letter_audio.stream).instantiate_playback();playback.start()
	var samples: PackedVector2Array=playback.mix_audio(1,1024);var peak := 0.0
	for sample in samples:peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	playback.stop()
	check(peak>.01 and peak*db_to_linear(controller.letter_audio.volume_db)<.025,"Decoded SPU letter tick has real signal at a deliberately quiet output level")
	var elapsed_before: float=game.elapsed
	var animation_before: float=player.motion.mixer.current_animation_position
	var enemy=game.enemies[0];enemy.active=true
	var enemy_position: Vector3=enemy.position
	var yaw_before: float=player.look_yaw;var pitch_before: float=player.pitch
	var ammo_before: int=player.ammo
	Input.action_press("forward");Input.action_press("aim");Input.action_press("fire")
	var mouse := InputEventMouseMotion.new();mouse.relative=Vector2(90,70)
	player._unhandled_input(mouse)
	check(not player.shoot() and not player.reload_weapon(),"Dialogue refuses new gun actions")
	for index in 15:await physics_frame
	check(player.look_yaw==yaw_before and player.pitch==pitch_before and not player.aiming and player.ammo==ammo_before,"Mouse, movement, aim and fire inputs remain blocked")
	check(Vector2(player.position.x-actor_position.x,player.position.z-actor_position.z).length()<.001,"Held movement cannot move the player during dialogue")
	check(game.elapsed>elapsed_before and not is_equal_approx(player.motion.mixer.current_animation_position,animation_before),"World time and the idle animation advance during dialogue")
	check(enemy.position.distance_to(enemy_position)>.01 and enemy.phase>0,"Active enemy AI, physics and animation continue")
	Input.action_release("forward");Input.action_release("aim");Input.action_release("fire")
	var period: float=controller.style.indicator_period
	var descent: float=controller.style.indicator_descent_ratio
	var view=controller.view
	check(is_zero_approx(view.indicator_offset_at(0)) and is_equal_approx(view.indicator_offset_at(period*descent),controller.style.indicator_travel) and is_zero_approx(view.indicator_offset_at(period)),"Triangle completes a continuous down/up cycle")
	check(descent<.5 and is_equal_approx(view.indicator_offset_at(period*descent*.5),view.indicator_offset_at(period*(descent+(1-descent)*.5))),"Descent covers the same travel faster than ascent")
	controller._process(period*.9)
	check(view.indicator_visible,"Ready marker animates without blinking off")
	game.pause_game();var old_text: int=controller.view.body.visible_characters
	controller.advance();controller._process(5)
	check(not controller.view.visible and controller.view.body.visible_characters==old_text,"Pause hides the dialogue and suspends its timers and confirmation")
	game.start_game()
	check(game.state=="dialogue" and player.enabled and player.controls_blocked and controller.view.visible,"Resume restarts simulation while keeping dialogue controls blocked")
	controller.advance()
	check(controller.line_index==1 and controller.state==Controller.State.OPENING,"Advancing a ready page switches line and speaker phase")
	var beep_count := letters.size();controller._input(action(true))
	check(controller.state==Controller.State.WAITING and letters.size()==beep_count,"Confirm during typewriter reveals the page silently")
	controller._input(action(true))
	check(controller.is_active(),"Holding confirmation cannot skip another page")
	controller._input(action(false))
	Input.action_press("fire");Input.action_press("aim")
	var ammo: int=player.ammo
	controller._input(action(true))
	check(not controller.is_active() and game.state=="playing" and opened==1 and closed==1,"Final marker closes the window and restores the modal session exactly once")
	check(not player.controls_blocked and player.is_physics_processing() and not game.enemies[1].is_physics_processing(),"Existing callback states are never changed by dialogue")
	check(Routing.source_of(controller.window_audio.stream)==controller._closing_stream and controller.window_audio.playing,"Final close plays the matching one-shot")
	for index in 3:await physics_frame
	check(player.ammo==ammo and not player.aiming,"Held fire and aim cannot leak out of dialogue confirmation")
	Input.action_release("fire");Input.action_release("aim")
	await physics_frame;await physics_frame
	check(not player.action_input_blocked(),"Action input guard clears once buttons are released")
	var long_text := "Le porte-parole regarde anticonstitutionnellement l'arriere-plan du couloir.\nEncore une phrase pour verifier les pages sans couper aucun mot."
	var pages := Text.paginate(long_text,controller.view.text_font,controller.style.font_size,controller.view.text_rect().size.x,2)
	check(pages.size()>1,"Long dialogue automatically paginates")
	var rebuilt := "";var output_words: Array[String]=[]
	for page in pages:
		var rows := page.split("\n")
		check(rows.size()<=2,"Pages respect the two-line reference layout")
		for row in rows:
			check(controller.view.text_font.get_string_size(row,HORIZONTAL_ALIGNMENT_LEFT,-1,controller.style.font_size).x<=controller.view.text_rect().size.x+1,"Wrapped whole words fit the window")
			for word in row.split(" ",false):output_words.append(word)
		rebuilt+=page.replace(" ","").replace("\n","")
	check(rebuilt==long_text.replace(" ","").replace("\n",""),"Pagination never loses text between pages")
	check(" ".join(output_words)==long_text.replace("\n"," "),"Words, apostrophes and hyphenated terms are never split between lines or pages")
	check(not game.play_dialogue(sequence(["A".repeat(120)])) and not controller.is_active(),"Impossible single-word layout is refused before taking control rather than cut or clipped")
	controller.maximum_queue=2
	game.play_dialogue(sequence(["Premier."]));controller.set_process(false)
	check(controller.play(sequence(["Deuxieme."],&"two")) and controller.play(sequence(["Troisieme."],&"three")),"Conversations can queue in order")
	check(not controller.play(sequence(["Refuse."])) and not controller.play(sequence(["Occupe."]),false),"Busy policy and bounded queue prevent uncontrolled overlap")
	var previous_open := opened;var previous_close := closed
	controller.advance();controller.advance()
	check(Routing.source_of(controller.window_audio.stream)==controller._opening_stream,"Queued sequences do not close and reopen the window sound")
	finish_all(controller)
	check(opened==previous_open and closed==previous_close+1,"Queue shares one modal session without briefly restoring movement")
	controller.line_started.connect(func(_line: Resource,_index: int):controller.cancel(),CONNECT_ONE_SHOT)
	check(game.play_dialogue(sequence(["Annule tout de suite."])) and not controller.is_active() and player.enabled,"Cancellation inside a line callback cannot leave the player frozen")
	var page_events: Array=[]
	var listener := func(_line: Resource,_page: int):page_events.append(true)
	controller.page_revealed.connect(listener)
	controller.letter_revealed.connect(func(_character: String):controller.advance(),CONNECT_ONE_SHOT)
	game.play_dialogue(sequence(["Un seul evenement."]));controller.set_process(false);advance_time(controller,.2)
	check(page_events.size()==1,"Reentrant reveal callbacks cannot emit page completion twice")
	controller.cancel();controller.page_revealed.disconnect(listener)
	# Blocking commands does not cancel a shot or reload already in progress.
	await physics_frame;await physics_frame
	var fired_events: Array=[]
	player.fired.connect(func(_origin: Vector3,_direction: Vector3):fired_events.append(true),CONNECT_ONE_SHOT)
	check(player.shoot(),"Shot can start before conversation")
	game.play_dialogue(sequence(["Action en cours."]));controller.set_process(false)
	for index in 8:await physics_frame
	check(fired_events.size()==1 and controller.is_active(),"A pending frame-2 shot event completes while dialogue controls are blocked")
	controller.cancel();await physics_frame;await physics_frame
	player.ammo=player.magazine_capacity-2;player.reserve=20
	check(player.reload_weapon(),"Reload can start before conversation")
	game.play_dialogue(sequence(["Rechargement en cours."]));controller.set_process(false)
	await create_timer(player.motion.get_reload_duration()+player.reload_pose_return_time+.05).timeout
	check(controller.is_active() and player.ammo==player.magazine_capacity and player.motion.aim_pose.reload_time<0,"Current body/gun reload and magazine timing finish without freezing during dialogue")
	controller.cancel()
	# Real physics trigger: changing control availability keeps colliders intact.
	var trigger=load("res://scenes/dialogue/dialogue_trigger.tscn").instantiate()
	trigger.sequence=sequence(["Zone."]);trigger.once=false
	game.level.add_child(trigger);trigger.global_position=player.global_position
	var contacts: Array=[]
	trigger.body_entered.connect(func(body: Node):
		if body==player:contacts.append(true))
	for index in 5:await physics_frame
	check(controller.is_active() and trigger.used and contacts.size()==1,"Actual player entry starts an assigned dialogue")
	controller.set_process(false);finish_all(controller)
	for index in 5:await physics_frame
	check(not controller.is_active() and contacts.size()==1,"Closing dialogue does not retrigger the same occupied zone")
	trigger.queue_free();await process_frame
	game.play_dialogue(sequence(["Fin de niveau."]));player.invincible=0;player.take_damage(player.max_health)
	await process_frame;await process_frame
	check(not controller.is_active() and not player.enabled and game.state=="dead","World damage during dialogue is processed and closes the conversation on death")
	paused=false
	FileAccess.open("res://docs/dialogue-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"sessions_opened":opened,"sessions_closed":closed,"letter_events":letters.size(),"long_text_pages":pages.size()},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;game.queue_free();await process_frame;await create_timer(.1).timeout
	var preview=load("res://scenes/dialogue/dialogue_preview.tscn").instantiate();root.add_child(preview)
	await process_frame;await physics_frame;await process_frame
	var preview_game=preview.get_node("Level")
	check(preview_game.dialogue.is_active() and not Input.is_action_pressed("aim") and not preview_game.player.aiming,"Actual F6 preview starts dialogue without synthesizing an aim command")
	preview_game.dialogue.cancel()
	for audio in preview.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in preview.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	preview.queue_free();await process_frame;await create_timer(.1).timeout
	print("DIALOGUE_OK: whole-word pagination, quiet SPU window/tick samples, asymmetric triangle, living world with blocked controls, pause, held-input guards, queue, cancellation and real zone triggers" if failures.is_empty() else "DIALOGUE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
