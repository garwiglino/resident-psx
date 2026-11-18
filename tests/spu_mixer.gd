extends SceneTree
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
var failures: Array[String]=[]
var measures := {}
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func sample(nibble: int) -> AudioStream:
	var stream: AudioStream=ClassDB.instantiate("AudioStreamPSX")
	var bytes := PackedByteArray();bytes.resize(5000*16)
	for block in 5000:
		for byte in range(2,16):bytes[block*16+byte]=(nibble&15)*17
	bytes[bytes.size()-15]=1
	stream.set("adpcm_left",bytes);stream.set("frame_count",140000);stream.set("mix_rate",44100)
	return stream
func scalar(stream: AudioStream,lreg := 16383,rreg := 16383) -> int:
	stream.set_spu_controls(lreg,rreg,false)
	var playback := stream.instantiate_playback();playback.start()
	var values: PackedVector2Array=playback.mix_spu(1024);var result := roundi(values[1023].x*32768)
	playback.stop();return result
func stable(capture: AudioEffectCapture) -> Dictionary:
	var samples := capture.get_buffer(capture.get_frames_available())
	var histogram := {};var off_grid := 0;var peak := 0.0
	for value in samples:
		var l := value.x*32768;var r := value.y*32768
		if absf(l-roundf(l))>.0001 or absf(r-roundf(r))>.0001:off_grid+=1
		var key := roundi(l);histogram[key]=histogram.get(key,0)+1;peak=maxf(peak,absf(value.x))
	var mode := 0;var count := 0
	for value in histogram:
		if histogram[value]>count:mode=value;count=histogram[value]
	return {"frames":samples.size(),"mode":mode,"mode_frames":count,"off_grid":off_grid,"peak":peak}
func run() -> void:
	measures["host_rate"]=AudioServer.get_mix_rate()
	check(ClassDB.class_has_method("AudioStreamPSX","make_voice"),"v14 native mixer is loaded")
	if not ClassDB.class_has_method("AudioStreamPSX","make_voice"):quit(1);return
	var manager := root.get_node("PSXAudio");manager.set_process(false)
	AudioServer.set_bus_volume_db(0,0)
	Routing.sync_master()
	var master: AudioEffect
	for slot in AudioServer.get_bus_effect_count(0):
		var effect := AudioServer.get_bus_effect(0,slot)
		if effect.is_class("AudioEffectPSXReverb"):master=effect
	check(master!=null and master.get("native_mixer"),"Master uses the native integer sum rather than Godot voice mixing")
	master.set("master_left",16383);master.set("master_right",16383)
	var capture := AudioEffectCapture.new();capture.buffer_length=2
	var capture_slot := AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,capture)
	var positive := sample(7);var negative := sample(-7)
	var p := scalar(positive);var n := scalar(negative)
	var players: Array[AudioStreamPlayer]=[]
	for source in [positive,positive,negative]:
		var player := AudioStreamPlayer.new();player.set_meta("psx_reverb",false);player.stream=source;root.add_child(player)
		Routing.play(player);players.append(player)
	await create_timer(.15).timeout;capture.clear_buffer();await create_timer(.12).timeout
	var result := stable(capture);measures["wide_cancellation"]=result
	var expected := (clampi(p+p+n,-32768,32767)*32766)>>15
	check(result.frames>1000 and result.mode_frames>result.frames*.95,"Actual AudioServer capture contains a stable native mixed signal")
	check(result.mode==expected,"Actual output matches wide signed sum, clamp, then MVOL multiplication (expected %d, got %d)" % [expected,result.mode])
	if AudioServer.get_mix_rate()==44100:check(result.off_grid==0,"Native-rate output stays exactly on the signed 16-bit grid")
	for player in players:player.stop();player.queue_free()
	await create_timer(.08).timeout;players.clear()
	# Three positive voices must clip before master attenuation, unlike a
	# floating-point gain followed by a final integer conversion.
	master.set("master_left",8192);master.set("master_right",8192)
	for index in 3:
		var player := AudioStreamPlayer.new();player.set_meta("psx_reverb",false);player.stream=positive;root.add_child(player)
		Routing.play(player);players.append(player)
	await create_timer(.12).timeout;capture.clear_buffer();await create_timer(.12).timeout
	result=stable(capture);measures["pre_master_clipping"]=result
	expected=(32767*16384)>>15
	check(result.mode==expected,"Master gain is a SPU register applied after saturation")
	for player in players:player.stop();player.queue_free()
	await create_timer(.08).timeout;players.clear();master.set("master_left",16383);master.set("master_right",16383)
	# Each player owns its register state even when the source resource is shared.
	var a := AudioStreamPlayer.new();a.set_meta("psx_reverb",false);a.volume_db=-12;a.stream=positive;root.add_child(a);Routing.play(a)
	var b := AudioStreamPlayer.new();b.set_meta("psx_reverb",false);b.volume_db=-24;b.stream=positive;root.add_child(b);Routing.play(b)
	await create_timer(.06).timeout
	var a_state: Dictionary=a.get_stream_playback().get_spu_state();var b_state: Dictionary=b.get_stream_playback().get_spu_state()
	check(a.stream!=b.stream and Routing.source_of(a.stream)==positive and Routing.source_of(b.stream)==positive,"Shared samples have independent per-player voice registers")
	check(a_state.left==roundi(db_to_linear(-12)*16384)*2 and b_state.left==roundi(db_to_linear(-24)*16384)*2,"Player dB controls map to signed 15-bit voice registers")
	var before := a.get_playback_position();a.stream_paused=true;Routing.sync_player(a)
	await create_timer(.08).timeout
	check(absf(a.get_playback_position()-before)<.02,"Pause freezes sample position and ADSR")
	a.stream_paused=false;Routing.sync_player(a);await create_timer(.05).timeout
	check(a.get_playback_position()>before+.02,"Resume continues from the same voice position")
	a.stop();b.stop();a.queue_free();b.queue_free();await create_timer(.08).timeout
	var release_sample := sample(3);release_sample.set("adsr2",0x1fcb)
	var released := AudioStreamPlayer.new();released.set_meta("psx_reverb",false);released.stream=release_sample;root.add_child(released);Routing.play(released)
	await create_timer(.08).timeout;capture.clear_buffer();Routing.stop(released)
	await create_timer(.15).timeout
	var released_samples := capture.get_buffer(capture.get_frames_available())
	var mid_peak := 0.0;var tail_peak := 0.0
	for index in released_samples.size():
		if index>int(.025*AudioServer.get_mix_rate()) and index<int(.06*AudioServer.get_mix_rate()):mid_peak=maxf(mid_peak,absf(released_samples[index].x))
		if index>int(.12*AudioServer.get_mix_rate()):tail_peak=maxf(tail_peak,absf(released_samples[index].x))
	check(mid_peak>.02 and tail_peak<.0001,"Stopping a player renders its hardware release instead of Godot's short fade")
	measures["key_off_release"]={"middle_peak":mid_peak,"tail_peak":tail_peak,"frames":released_samples.size()}
	released.queue_free();await process_frame
	# Check the hardware budget on the real managed path as well as standalone.
	for index in 25:
		var player := AudioStreamPlayer.new();player.set_meta("psx_reverb",false);player.volume_db=-48;player.stream=positive;root.add_child(player)
		Routing.play(player);players.append(player)
	await create_timer(.1).timeout
	check(positive.get_mixer_diagnostics().active_voices==24,"The real mixer accepts 24 mono voices and refuses the twenty-fifth")
	for player in players:Routing.stop(player);player.queue_free()
	players.clear();await create_timer(.08).timeout
	# A long attack must follow sample-clock ENVX, not render/physics FPS.
	var slow := sample(3);slow.set("adsr1",(11<<10)|15);slow.set("adsr2",0x1fc0)
	var playback := slow.instantiate_playback();playback.start();playback.mix_spu(1000)
	check(playback.get_spu_state().envelope==7000,"Attack envelope advances by seven per SPU tick")
	playback.mix_spu(1000,2)
	check(playback.get_spu_state().envelope==14000 and playback.get_spu_state().pitch==8192,"Pitch changes source stepping without changing the ADSR clock")
	playback.key_off();playback.mix_spu(1)
	check(not playback.is_playing() and playback.get_spu_state().envelope==0,"Key-off enters the register release phase")
	playback.stop()
	var diagnostics: Dictionary=positive.get_mixer_diagnostics();measures["diagnostics"]=diagnostics
	check(diagnostics.spu_rate==44100 and diagnostics.spu_ticks>10000,"Internal SPU clock stays at 44,100 Hz independently of the device rate")
	check(absi(diagnostics.spu_ticks-int(diagnostics.host_frames*44100.0/diagnostics.host_rate))<=1,"Captured SPU ticks match physical time on the actual output device")
	check(diagnostics.blocks>10 and diagnostics.voice_frames>1000 and diagnostics.overflow==0,"All real callbacks pass through the native mix buffer without mismatch or overflow")
	check(diagnostics.active_voices==0,"Finished, stopped and freed players release every SPU voice")
	AudioServer.remove_bus_effect(0,capture_slot)
	FileAccess.open("res://docs/spu-mixer-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"measurements":measures},"\t"))
	print("SPU_MIXER_OK: captured integer sum, clipping order, volume registers, independent shared samples, fixed-clock ADSR, pause/resume and voice cleanup" if failures.is_empty() else "SPU_MIXER_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
