extends SceneTree
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Action=preload("res://scripts/world_events/world_action.gd")
var game: Node3D
var manager: Node
var world: Node
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func settle(count := 3) -> void:
	for frame in count:await process_frame
func begin(phone: Node3D) -> void:
	check(phone.configuration_error().is_empty() and phone.interact(game.player),"Authored interphone opens its fixed view")
	manager.set_process(false);manager.set_physics_process(false)
func cycle() -> Node:
	var current: Node=manager._action_cycle
	if current:current.set_process(false)
	return current
func flag(id: StringName) -> Resource:
	var action := Action.new();action.kind=Action.Kind.SET_FLAG;action.id=id;return action
func loop_setting(stream: AudioStream) -> Variant:
	return stream.get("loop") if stream.is_class("AudioStreamPSX") else stream.loop_mode if stream is AudioStreamWAV else null
func pump() -> void:
	world._process(0);world.set_process(false);manager._process(0)
	game.dialogue.set_process(false);manager.set_process(false)
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("Interphone calls timeout");quit(2))
	root.get_node("InventoryState").persist_collection=false;world=root.get_node("WorldEvents");world.reset_run();AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	var path := "res://scenes/interactions/interphone_interact.tscn";var scene_hash := FileAccess.get_sha256(path)
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.pickup_feedback.enabled=false;game.set_process(false);game.player.set_process(false);game.player.set_physics_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	manager=game.item_placement
	var phone: Node3D=load(path).instantiate();phone.interaction_id=&"test.phone";phone.position=Vector3(1000,0,1000);game.level.add_child(phone);await settle()
	var buttons: Array=phone.placement_targets();check(buttons.size()==12 and buttons.all(func(button: Node):return button.get_script().resource_path=="res://scripts/interactions/interphone_button.gd" and button.configuration_error().is_empty()),"All 12 authored buttons use the dedicated call logic, including unanswered buttons")
	if buttons.size()!=12:quit(1);return
	var first: Node3D=buttons[0];var second: Node3D=buttons[1]
	var camera_pose: Transform3D=phone.get_node("CameraFixe").transform;var button_pose: Transform3D=first.transform
	first.ringing_seconds=.35;second.ringing_seconds=1.25
	var sequence := Sequence.new();sequence.mode=Sequence.Mode.CONVERSATION;sequence.minimum_page_seconds=.5;sequence.reading_characters_per_second=80
	var reply := Line.new();reply.speaker="LE CONCIERGE";reply.text="Allo. ".repeat(40);sequence.lines.append(reply);first.dialogue=sequence
	var original_loop: Variant=loop_setting(phone.ringing_sound)
	var prepared: AudioStream=root.get_node("PSXAudio").prepare(phone.ringing_sound);var prepared_loop: Variant=loop_setting(prepared)
	begin(phone);check(manager.select_part(first),"Pressing the first button starts its call")
	var call := cycle();var ringing_player: AudioStreamPlayer3D=call.player
	check(manager.phase==manager.Phase.ACTION_CYCLE and call.phase==call.Phase.RINGING and not game.dialogue.is_active(),"Ringing starts before any dialogue")
	check(ringing_player.playing and ringing_player.stream.is_class("AudioStreamPSX") and bool(ringing_player.stream.get("loop")),"The ring uses a looping native SPU voice")
	check(ringing_player.get_meta("psx_audio_category")==&"Interactions" and ringing_player.global_position.is_equal_approx(first.get_interaction_position()),"Ringing uses the interactions mix at the selected physical button")
	check(not manager.select_part(second) and not manager.select_part(first),"All buttons reject further clicks during ringing")
	call._process(.34);check(call.phase==call.Phase.RINGING and not game.dialogue.is_active(),"Button-specific duration does not end early")
	manager.set_suspended(true);var paused_elapsed: float=call.elapsed;call._process(4)
	check(call.elapsed==paused_elapsed and not ringing_player.can_process(),"Suspending inspection pauses its timer and native audio, including a pending key-on")
	manager.set_suspended(false);call._process(.02)
	check(not ringing_player.playing and manager.phase==manager.Phase.ACTIONS,"Ringing stops before the reply is dispatched")
	pump();check(game.dialogue.is_active() and game.dialogue.is_automatic() and not game.exploration_dialogue.is_active(),"Assigned reply uses automatic progression on the reserved close-up channel")
	check(sequence.mode==Sequence.Mode.CONVERSATION and sequence.lines[0]==reply and not manager.select_part(second),"Source dialogue stays unchanged and other buttons remain locked throughout the reply")
	# No calls to advance(): long dialogue pages must complete autonomously.
	for step in 240:
		if not game.dialogue.is_active() and manager.phase==manager.Phase.INSPECTING:break
		game.dialogue._process(.1);pump()
		if step%12==0:await process_frame
	check(not game.dialogue.is_active() and manager.phase==manager.Phase.INSPECTING,"Long automatic reply completes and unlocks the other buttons without confirmation")
	check(phone.get_node("CameraFixe").transform.is_equal_approx(camera_pose) and first.transform.is_equal_approx(button_pose),"Call logic preserves the authored camera and button transforms")
	second.response=second.Response.NO_ANSWER;second.dialogue=sequence
	check(manager.select_part(second),"Another button becomes available after the first complete cycle")
	call=cycle();check(is_equal_approx(call.duration,1.25),"The second button has its own independent ringing duration")
	call._process(1.2);check(call.phase==call.Phase.RINGING and not manager.select_part(first),"Second button stays ringing for its configured time")
	call._process(.06);check(call.phase==call.Phase.HANGUP and not game.dialogue.is_active() and not bool(call.player.stream.get("loop")),"No-answer mode plays hangup once and never launches its assigned dialogue")
	check(not manager.select_part(first),"Buttons remain blocked until the hangup sound ends")
	call._process(maxf(call._hangup_length-.01,0));check(manager.phase==manager.Phase.ACTION_CYCLE,"Hangup is part of the locked cycle")
	call._process(.02);pump();check(manager.phase==manager.Phase.INSPECTING and not game.dialogue.is_active(),"No-answer cycle returns to inspection after the full hangup")
	check(loop_setting(phone.ringing_sound)==original_loop and loop_setting(prepared)==prepared_loop,"Loop flags never leak into the source WAV or cached shared SPU sample")
	# Explicit exit cancels ringing immediately and cannot fire its actions later.
	first.dialogue=null;first.actions.assign([flag(&"test.phone.cancelled")]);first.ringing_seconds=4
	manager.select_part(first);call=cycle();var cancelled_player: AudioStreamPlayer3D=call.player;manager.request_exit();world._process(0)
	check(not manager.is_active() and not cancelled_player.playing and not world.flag(&"test.phone.cancelled") and not game.player.controls_blocked,"Leaving the fixed view cancels its timer, ringing and pending actions")
	await settle();begin(phone);manager.select_part(first);call=cycle();var deleted_player: AudioStreamPlayer3D=call.player
	first.free();check(not manager.is_active() and not deleted_player.playing and not world.flag(&"test.phone.cancelled"),"Deleting a button cancels its live call without stale callbacks")
	await settle();begin(phone);manager.select_part(second);call=cycle();var reset_player: AudioStreamPlayer3D=call.player;world.reset_run()
	check(not manager.is_active() and not reset_player.playing and not game.player.controls_blocked,"World reset stops the whole call and restores controls")
	check(FileAccess.get_sha256(path)==scene_hash,"Runtime never rewrites the artist's interphone scene")
	phone.queue_free();await settle()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	var result := {"ok":failures.is_empty(),"checks":checks,"errors":failures};FileAccess.open("res://docs/interphone-calls-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("INTERPHONE_CALLS_OK " if failures.is_empty() else "INTERPHONE_CALLS_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
