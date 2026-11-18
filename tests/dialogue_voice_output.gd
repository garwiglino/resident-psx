extends SceneTree
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Voice=preload("res://scripts/dialogue/dialogue_voice.gd")
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	Routing.setup()
	var capture := AudioEffectCapture.new();capture.buffer_length=8;var capture_slot := AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,capture)
	var voice := Voice.new();root.add_child(voice)
	var line := Line.new();var path := "res://assets/audio/dialogs/1/1_Chapter_1.wav"
	if not ResourceLoader.exists(path):path="res://assets/audio/dialogs/1/-01.wav"
	line.audio=load(path) if ResourceLoader.exists(path) else null;line.text="Voix 01."
	if not line.audio:push_error("Voice audit source no longer exists.");quit(1);return
	var style=load("res://assets/dialogue/default_style.tres")
	var reports: Array=[]
	for radio in [false,true]:
		line.is_intercom=radio;voice.stop_line(false);capture.clear_buffer()
		voice.play_line(line,style)
		await create_timer(line.audio.get_length()+(style.intercom_close_sound.get_length() if radio else 0)+.3).timeout
		var samples := capture.get_buffer(capture.get_frames_available());var peak := 0.0;var sum := 0.0;var nonzero := 0
		for sample in samples:
			peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)));sum+=sample.length_squared()*.5
			if sample.length_squared()>.000001:nonzero+=1
		reports.append({"radio":radio,"captured_frames":samples.size(),"peak":peak,"rms":sqrt(sum/maxi(samples.size(),1)),"nonzero_frames":nonzero,"phase":voice.phase})
		check(peak>.05 and nonzero>10000,"Actual AudioServer output contains the speech, radio="+str(radio)+": "+str(reports.back()))
		check(voice.phase==Voice.Phase.SILENT,"Natural playback ends without watchdog truncation")
	print("VOICE_OUTPUT ",JSON.stringify(reports))
	voice.stop_line(false);voice.queue_free();await process_frame;await create_timer(.15).timeout
	AudioServer.remove_bus_effect(0,capture_slot)
	FileAccess.open("res://docs/dialogue-voice-output.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"reports":reports},"\t"))
	print("DIALOGUE_VOICE_OUTPUT_OK" if failures.is_empty() else "DIALOGUE_VOICE_OUTPUT_FAILED");quit(0 if failures.is_empty() else 1)
