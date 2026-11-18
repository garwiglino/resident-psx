extends SceneTree
const Controller=preload("res://scripts/dialogue/dialogue_controller.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Preview=preload("res://addons/cinematic_montage/preview.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func count_event(id: StringName) -> int:return int(root.get_node("WorldEvents").fact(StringName("event.%s.count" % id),0))
func make_sequence(automatic := false) -> DialogueSequence:
	var sequence := Sequence.new();sequence.id=&"end_events_test"
	sequence.mode=Sequence.Mode.EXPLORATION_CALL if automatic else Sequence.Mode.CONVERSATION
	for text in ["Premiere replique.","Reponse suivante."]:
		var line := Line.new();line.speaker="HITOMI";line.text=text;sequence.lines.append(line)
	return sequence
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var world := root.get_node("WorldEvents");world.reset_run()
	var event_audio := world.get_node("EventSounds")
	# Exercise lazy loading of the actual artist WAV when present. A fixture
	# supports running the logic independently of optional authoring assets.
	var actual_hangup := ResourceLoader.exists(event_audio.INTERCOM_END)
	if not actual_hangup:event_audio.intercom_end_stream=load("res://assets/audio/dialogs/talkie_end.wav")
	var c := Controller.new();root.add_child(c);c.style=c.style.duplicate()
	c.style.opening_delay=0;c.style.speaker_delay=0;c.style.characters_per_second=120
	c.style.lines_per_page=1
	var sequence := make_sequence();sequence.lines[0].text="Premiere page.\nDeuxieme page."
	sequence.lines[0].event_id=&"test.reply_started";sequence.lines[0].end_event_id=&"test.reply_ended";sequence.lines[0].end_intercom=true
	sequence.lines[0].is_intercom=true;sequence.lines[0].audio=load("res://assets/audio/dialogs/1/1_Chapter_1.wav")
	check(c.play(sequence),"Manual sequence starts");c.set_process(false)
	check(count_event(&"test.reply_started")==1,"Start event is forwarded to WorldEvents")
	c.advance();check(count_event(&"test.reply_ended")==0,"Revealing a page never finishes the line")
	check(c._pages.size()==2,"Fixture has two pages")
	c.advance();c.advance()
	check(count_event(&"test.reply_ended")==0,"Moving to the final page does not emit its end event")
	# Reentrant confirmation from a callback must not skip another reply.
	c.line_finished.connect(func(_line: Resource,_index: int):c.advance(),CONNECT_ONE_SHOT)
	c.advance();await process_frame;c.set_process(false)
	check(c.line_index==1 and c.is_active(),"One confirmation advances exactly one reply")
	check(count_event(&"test.reply_ended")==1 and count_event(&"end_intercom")==1,"End and hangup events fire once for the whole reply")
	check(event_audio.player.playing and event_audio.player.bus==&"Radio FX Dry","Hangup uses Intercom Effets without reverb")
	check(is_equal_approx(event_audio.player.volume_db,-4.0),"Hangup is six dB louder than the preceding -10 dB setting")
	check(not event_audio.player.stream.get("loop"),"Hangup is always a one-shot")
	if actual_hangup:
		check(event_audio.intercom_end_stream.resource_path==event_audio.INTERCOM_END,"The supplied intercom_end WAV is loaded automatically")
		check(event_audio.player.stream.is_class("AudioStreamPSX") and event_audio.player.stream.get("mix_rate")==22050,"Actual hangup uses the prepared 22050 Hz SPU source")
	check(not c.voice_audio.radio_loop.playing and not c.voice_audio.closing.playing,"Hangup stops the old radio bed and old closing squelch")
	c.cancel();event_audio.player.stop()
	check(count_event(&"end_intercom")==1,"Cancelling a different reply does not repeat the preceding end event")
	sequence=make_sequence();sequence.lines[0].end_intercom=true
	c.play(sequence);c.set_process(false);c.cancel()
	check(count_event(&"end_intercom")==1,"An aborted unread line does not fire its completion event")
	# The string event is also a supported hangup preset; checkbox + same ID
	# must not emit it twice.
	sequence=make_sequence();sequence.lines[0].end_event_id=&"end_intercom";sequence.lines[0].end_intercom=true
	c.play(sequence);c.set_process(false);c.advance();c.advance();await process_frame;c.set_process(false)
	check(count_event(&"end_intercom")==2,"Preset ID and checkbox are deduplicated")
	c.cancel();event_audio.player.stop()
	# Automatic completion occurs before the response gap, never once per tick.
	c.exploration_channel=true;sequence=make_sequence(true);sequence.reply_gap=1.8
	sequence.minimum_page_seconds=.5;sequence.reading_characters_per_second=80
	sequence.lines[0].override_reply_gap=true;sequence.lines[0].reply_gap=.6;sequence.lines[0].end_event_id=&"test.auto_ended"
	c.play(sequence);c.set_process(false)
	check(is_equal_approx(c._automatic.reply_gap,.6),"Selected line overrides the sequence gap")
	for tick in 40:
		c._process(.05)
		if c._line_completion_sent:break
	check(count_event(&"test.auto_ended")==1 and c.line_index==0,"End event precedes the response pause")
	for tick in 3:c._process(.05)
	check(c.line_index==0 and count_event(&"test.auto_ended")==1,"Pause holds the completed line without repeating its event")
	var gap: float=c._automatic.gap_elapsed;c.set_suspended(true);c._process(2)
	check(is_equal_approx(c._automatic.gap_elapsed,gap),"Suspension freezes the response gap")
	c.set_suspended(false)
	for tick in 15:c._process(.05)
	check(c.line_index==1 and is_equal_approx(c._automatic.reply_gap,1.8),"Following line restores the general gap")
	check(not sequence.lines[1].override_reply_gap and sequence.reply_gap==1.8,"Authored sequence remains unchanged")
	c.cancel()
	# Zero is an explicit override, and montage duration follows the same policy.
	sequence=make_sequence(true);sequence.reply_gap=1.0
	var normal_duration := Preview.automatic_dialogue_duration(sequence)
	sequence.lines[0].override_reply_gap=true;sequence.lines[0].reply_gap=0
	check(absf(Preview.automatic_dialogue_duration(sequence)-normal_duration+1.0)<.00001,"Montage preview includes the per-line gap")
	c.play(sequence);c.set_process(false)
	check(c._automatic.reply_gap==0,"Zero override never falls back to the default")
	c.cancel();c.queue_free();event_audio.player.stop();await process_frame;await create_timer(.1).timeout
	FileAccess.open("res://docs/dialogue-end-events-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures,"actual_hangup_wav":actual_hangup},"\t"))
	print("DIALOGUE_END_EVENTS_OK " if failures.is_empty() else "DIALOGUE_END_EVENTS_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
