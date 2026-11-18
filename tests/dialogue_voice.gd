extends SceneTree
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Controller=preload("res://scripts/dialogue/dialogue_controller.gd")
const Radio=preload("res://scripts/dialogue/intercom_filter.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func tone(frequency: float) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new();wave.format=AudioStreamWAV.FORMAT_16_BITS;wave.mix_rate=22050
	var data := PackedByteArray();data.resize(22050)
	for frame in 11025:data.encode_s16(frame*2,roundi(sin(TAU*frequency*frame/22050)*9000))
	wave.data=data;return wave
func energy(stream: AudioStream) -> float:
	var playback := stream.instantiate_playback();playback.start()
	var samples := playback.mix_audio(AudioServer.get_mix_rate()/22050.0,11025);var sum := 0.0
	for index in range(2205,samples.size()):sum+=samples[index].length_squared()*.5
	playback.stop();return sqrt(sum/maxi(samples.size()-2205,1))
func run() -> void:
	var controller := Controller.new();root.add_child(controller);controller.set_process(false)
	var line := Line.new();line.text="Une voix dans le couloir.";line.audio=tone(1000);line.is_intercom=true
	var sequence := Sequence.new();sequence.lines.append(line)
	var audio: Node=controller.voice_audio;var events: Array[String]=[]
	audio.phase_changed.connect(func(value: int):if value==audio.Phase.VOICE:events.append("voice"))
	controller.letter_revealed.connect(func(_character: String):if "text" not in events:events.append("text"))
	check(controller.play(sequence),"An audio reply starts without changing the dialogue design")
	controller.set_process(false);controller._process(.06)
	check(events.is_empty() and not audio.voice.playing,"Window/name lead-in is shared by text and voice")
	controller._process(.14)
	check(audio.phase==audio.Phase.VOICE and audio.opening.playing and audio.voice.playing,"Radio opening and speech start together with the text")
	check(events==["voice","text"] and controller.view.body.visible_characters>0,"First voice start and first visible glyph occur in the same controller tick")
	audio.opening.finished.emit()
	check(events.count("voice")==1 and audio.voice.playing,"Ending the radio opening cannot restart or delay speech")
	check(audio.voice.stream.is_class("AudioStreamPSX") and audio.voice.stream.mix_rate==22050 and audio.voice.stream.get("adpcm_right").is_empty(),"Filtered speech is real mono SPU ADPCM at 22050 Hz")
	check(not audio.voice.stream.loop,"Speech cannot loop accidentally")
	controller.advance()
	check(audio.voice.playing and controller.state==Controller.State.WAITING,"Revealing the typewriter does not skip the voice")
	controller.set_suspended(true);check(audio.voice.stream_paused and controller.suspended,"Pause freezes the active voice and prevents radio transitions")
	controller.set_suspended(false)
	controller.advance()
	check(not controller.is_active() and not audio.voice.playing and audio.closing.playing,"Passing the reply cuts its voice and plays the radio close")
	var normal := Line.new();normal.text="Un dialogue normal.";normal.audio=tone(1000)
	var next := Sequence.new();next.lines.append(normal)
	controller.play(next);controller.set_process(false);controller._process(.2)
	check(audio.phase==audio.Phase.VOICE and not audio.opening.playing,"A normal voice uses no radio opening or filter")
	controller.cancel();check(not audio.voice.playing,"Cancellation cannot leak a previous voice")
	# One long reply uses several pages but keeps one continuous voice.
	line.text="Une longue replique dans le couloir. ".repeat(12)
	sequence.lines=[line];controller.play(sequence);controller.set_process(false);controller._process(.2)
	controller.advance();controller.advance()
	check(controller.page_index==1 and audio.voice.playing and audio.current_line==controller.current_line,"Changing text pages keeps the same audio and radio transmission")
	audio._voice_finished();check(audio.closing.playing and audio.phase==audio.Phase.CLOSING,"Natural audio completion also closes the transmission")
	controller.cancel();audio.stop_line(false)
	var low := energy(Radio.build(tone(70)));var mid := energy(Radio.build(tone(1000)));var high := energy(Radio.build(tone(7000)))
	check(mid>.1 and low<mid*.1 and high<mid*.15,"Radio band limits reject bass and ultrasonic detail while retaining intelligible speech")
	var sample := tone(1000);check(Radio.build(sample)==Radio.build(sample),"Prepared radio streams are cached")
	line.text="Transmission normale.";sequence.lines=[line]
	controller.play(sequence);controller.set_process(false);controller._process(.2)
	var natural_seconds: float=audio.voice.stream.get_length()+audio.closing.stream.get_length()+.35
	await create_timer(natural_seconds).timeout
	check(audio.phase==audio.Phase.SILENT and controller.is_active(),"Real audio completion closes the radio without automatically closing unread dialogue")
	controller.cancel()
	FileAccess.open("res://docs/dialogue-voice-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rms_70_hz":low,"rms_1000_hz":mid,"rms_7000_hz":high,"spu_adpcm":true},"\t"))
	controller.queue_free();await process_frame;await create_timer(.15).timeout
	print("DIALOGUE_VOICE_OK: per-reply audio, typewriter/page independence, skip cuts, pause, radio opening/closing, mono band-limited SPU samples" if failures.is_empty() else "DIALOGUE_VOICE_FAILED "+str(failures));quit(0 if failures.is_empty() else 1)
