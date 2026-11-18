extends SceneTree
const Sequence=preload("res://scripts/cinematics/cinematic_sequence_3d.gd")
const Trigger=preload("res://scripts/cinematics/cinematic_trigger_3d.gd")
var failures: Array[String]=[]
var reasons: Array[StringName]=[]
var events: Array[StringName]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func close_dialogue(dialogue: Node) -> void:
	var limit := 0
	while dialogue.is_active() and limit<40:dialogue.advance();limit+=1
func new_sequence(game: Node) -> Node3D:
	var result=load("res://scenes/cinematics/cinematic_sequence.tscn").instantiate()
	result.classic_timeline=true
	game.add_child(result)
	return result
func start(game: Node,sequence: Node) -> bool:
	var accepted: bool=game.play_cinematic(sequence)
	game.cinematics.set_process(false)
	return accepted
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.psx_renderer.set_process(false)
	var manager=game.cinematics;var dialogue=game.dialogue;var player=game.player
	manager.finished.connect(func(_sequence: Node3D,reason: StringName):reasons.append(reason))
	manager.event_reached.connect(func(_sequence: Node3D,event: StringName):events.append(event))
	var sequence=new_sequence(game);var timeline: AnimationPlayer=sequence.get_node("Timeline")
	var original_callback := timeline.callback_mode_process
	var original_method := timeline.callback_mode_method
	check(not manager.is_active() and game.psx_renderer.camera==player.camera,"No automatic cinematic on main-scene startup")
	# Keep this regression independent of the artist adding/removing sequences.
	var placed_sequence=new_sequence(game.get_node("Map"))
	check(start(game,placed_sequence),"A cinematic placed inside the map starts")
	check(is_zero_approx(manager._blend_left) and manager.camera.global_transform.is_equal_approx(placed_sequence.get_node("CameraA").get_camera_transform()) and is_equal_approx(manager.camera.fov,placed_sequence.get_node("CameraA").fov),"Actual in-map entry cuts immediately, including position, rotation and FOV")
	manager.cancel()
	var invalid := Sequence.new();game.add_child(invalid)
	check(not start(game,invalid) and not player.controls_blocked,"Invalid scene is refused before taking controls")
	check(not game.play_cinematic(player),"A non-cinematic node is rejected cleanly")
	invalid.queue_free()
	game.play_dialogue(load("res://assets/dialogue/couloir_example.tres"));dialogue.set_process(false)
	check(not start(game,sequence) and dialogue.is_active(),"A cinematic cannot steal an already active conversation")
	close_dialogue(dialogue)
	check(start(game,sequence),"Native timeline cinematic starts")
	check(game.state=="cinematic" and player.enabled and player.controls_blocked and player.is_physics_processing(),"Cinematic blocks controls while the world keeps processing")
	check(manager.camera==game.psx_renderer.camera and root.get_camera_3d()==manager.camera,"Native viewport and PSX renderer use the same cinematic camera")
	check(manager.camera.global_transform.is_equal_approx(sequence.get_node("CameraA").global_transform),"Entry camera pose is applied without touching the player camera")
	check(not start(game,sequence) and not game.play_dialogue(sequence.dialogues[0]),"Overlaps and unrelated trigger dialogue cannot steal the session")
	manager._process(.4);dialogue.set_process(false)
	check(dialogue.is_active() and not manager.waiting_for_dialogue,"Asynchronous dialogue can reveal while the camera timeline moves")
	var time_before := timeline.current_animation_position
	manager._process(.7);dialogue.set_process(false)
	check(timeline.current_animation_position>time_before and manager.waiting_for_dialogue,"Second dialogue cue can wait for the whole conversation queue")
	check(absf(timeline.current_animation_position-1.1)<.00001,"Blocking cue stops exactly on its key without consuming the rest of a long frame")
	check(manager.camera.global_transform.is_equal_approx(sequence.get_node("CameraB").global_transform),"Camera cut during dialogue follows the second animated camera")
	var held_time := timeline.current_animation_position
	manager._process(2)
	check(timeline.current_animation_position==held_time,"Dialogue wait freezes only the cinematic timeline")
	var world_time: float=game.elapsed
	for index in 5:await physics_frame
	# Physics may catch up several ticks before the first idle update after load.
	# elapsed belongs to _process, so let the idle clock advance as well.
	await process_frame;await process_frame
	check(game.elapsed>world_time and player.is_physics_processing(),"World and player animation continue during a cinematic dialogue wait")
	game.pause_game();manager._process(5)
	check(paused and not dialogue.view.visible and timeline.current_animation_position==held_time,"Real pause suspends camera, timeline, dialogue and world")
	game.start_game()
	check(game.state=="cinematic" and player.controls_blocked and player.enabled and dialogue.view.visible,"Resume keeps cinematic ownership of controls and camera")
	close_dialogue(dialogue)
	check(game.state=="cinematic" and player.controls_blocked and not manager.waiting_for_dialogue,"Closing the dialogue does not release cinematic controls")
	manager._process(1.95)
	check(not manager.is_active() and not player.controls_blocked and game.psx_renderer.camera==player.camera,"Completion cuts directly to gameplay and releases cinematic controls in the same update")
	check(not manager.is_active() and game.state=="playing" and not player.controls_blocked and reasons.back()==&"completed","Natural completion restores gameplay exactly once")
	check(game.psx_renderer.camera==player.camera and root.get_camera_3d()==player.camera,"Renderer and viewport both return to the gameplay camera")
	check(timeline.callback_mode_process==original_callback and timeline.callback_mode_method==original_method,"Timeline callback settings are restored")
	check(dialogue.reservation_owner()==null and events.has(&"opening") and events.has(&"closing"),"Cues are emitted and dialogue reservation is released")
	# Blend to a moving source and interpolate lens parameters, without mutating it.
	check(start(game,sequence),"Sequence is reusable")
	var camera_b: Camera3D=sequence.get_node("CameraB")
	var old_fov := camera_b.fov;var old_mask := camera_b.cull_mask
	manager.change_camera(camera_b,1);manager._process(.1)
	check(manager.camera.fov<52 and manager.camera.fov>46,"Camera blends interpolate FOV")
	manager.cancel()
	check(camera_b.fov==old_fov and camera_b.cull_mask==old_mask and not manager.is_active(),"Cancellation restores control without changing artist cameras")
	check(start(game,sequence),"Sequence restarts for skip")
	manager._process(.4);dialogue.set_process(false)
	var old_closing_events := events.count(&"closing")
	check(manager.skip(),"Skip is available on a skippable cinematic")
	manager._process(.3)
	check(not dialogue.is_active() and not manager.is_active() and events.count(&"closing")==old_closing_events and reasons.back()==&"skipped","Skip applies final property values without firing skipped dialogue/method cues")
	check(game.psx_renderer.camera==player.camera and not player.controls_blocked,"Skip restores gameplay camera and controls")
	sequence.skippable=false;start(game,sequence)
	check(not manager.skip() and manager.is_active(),"Unskippable setting is respected")
	manager.cancel();sequence.skippable=true
	# Last asynchronous dialogue may outlive the timeline, but not its controls.
	var asynchronous=new_sequence(game)
	var async_clip: Animation=asynchronous.get_node("Timeline").get_animation(&"cinematic").duplicate(true)
	async_clip.track_set_key_value(2,3,{"method":"show_dialogue","args":[1,false]})
	asynchronous.get_node("Timeline").get_animation_library(&"").add_animation(&"cinematic",async_clip)
	start(game,asynchronous);manager._process(3.1);dialogue.set_process(false)
	check(manager.is_active() and manager._timeline_done and dialogue.is_active() and player.controls_blocked,"Final asynchronous dialogue can finish after the native timeline ends")
	close_dialogue(dialogue);manager._process(.3)
	check(not manager.is_active() and not player.controls_blocked,"Final asynchronous conversation releases control only after camera return")
	asynchronous.queue_free()
	player.controls_blocked=true;start(game,sequence);manager.cancel()
	check(player.controls_blocked,"Pre-existing external control lock is preserved")
	player.controls_blocked=false
	# Removal and invalid camera paths must never leave the player locked.
	start(game,sequence);manager.change_camera(player,0)
	check(not manager.is_active() and reasons.back()==&"missing_camera" and not player.controls_blocked,"Invalid camera safely interrupts the cinematic")
	var temporary=new_sequence(game);start(game,temporary);temporary.queue_free();await process_frame
	manager._process(.01)
	check(not manager.is_active() and game.psx_renderer.camera==player.camera and not player.controls_blocked,"Deleting a playing sequence restores camera and controls")
	# Callback cancellation while skipping cannot resume an obsolete sequence.
	start(game,sequence);manager._process(.4);dialogue.set_process(false)
	dialogue.session_finished.connect(func():manager.cancel(&"callback_cancel"),CONNECT_ONE_SHOT)
	manager.skip()
	check(not manager.is_active() and not player.controls_blocked,"Cancellation from a dialogue callback during skip cannot leave stale camera work")
	# Native physics entry, with a generated cube even when added as a class.
	var trigger := Trigger.new();game.add_child(trigger)
	trigger.sequence_path=trigger.get_path_to(sequence);trigger.position=player.position
	check(trigger.get_node("Volume").shape is BoxShape3D,"Cinematic trigger also has a default visible cube")
	for index in 6:await physics_frame
	check(trigger.used and manager.is_active(),"Actual player entry activates the cinematic zone")
	manager.set_process(false);manager.cancel()
	for index in 5:await physics_frame
	check(not manager.is_active() and not trigger.trigger(),"Once trigger does not retrigger while the player remains inside")
	trigger.reset();trigger.enabled=false
	check(not trigger.trigger(),"Disabled trigger refuses activation")
	trigger.queue_free()
	# Ending the level while waiting on dialogue cancels both owners.
	start(game,sequence);manager._process(.4);dialogue.set_process(false)
	game.finish("won")
	check(game.state=="won" and not player.enabled and not player.controls_blocked and not dialogue.is_active() and not manager.is_active(),"Level result cancels camera/dialogue without re-enabling gameplay")
	paused=false
	game.state="playing";player.enabled=true
	start(game,sequence);manager._process(.4);dialogue.set_process(false)
	manager.queue_free();await process_frame
	check(game.state=="playing" and not dialogue.is_active() and not player.controls_blocked and game.psx_renderer.camera==player.camera,"Removing the manager itself releases camera, dialogue and controls")
	FileAccess.open("res://docs/cinematic-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"finish_reasons":reasons,"events":events},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free();await process_frame;await create_timer(.1).timeout
	print("CINEMATICS_OK: native timelines, camera/FOV cuts and blends, nested dialogue, living world, pause, skip, interruption, level end and real trigger volume" if failures.is_empty() else "CINEMATICS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
