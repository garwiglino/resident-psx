extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func make_tone(stereo: bool=false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=22050;stream.stereo=stereo
	var pcm := PackedByteArray();pcm.resize(2205*2*(2 if stereo else 1))
	for frame in 2205:
		var sample := roundi(sin(frame*TAU*440/22050)*12000)
		pcm.encode_s16(frame*2*(2 if stereo else 1),sample)
		if stereo:pcm.encode_s16(frame*4+2,roundi(sin(frame*TAU*660/22050)*8000))
	stream.data=pcm;return stream
func energy(frames: PackedVector2Array,begin: int=0,end: int=-1) -> float:
	var result := 0.0
	if end<0:end=frames.size()
	for i in range(begin,end):result+=frames[i].length_squared()
	return result/maxi(end-begin,1)
func run() -> void:
	check(ProjectSettings.get_setting("audio/driver/mix_rate")==22050,"Project requests the chosen 22050 Hz output")
	var audio=root.get_node("PSXAudio")
	var mono := make_tone()
	var converted: AudioStream=audio.prepare(mono)
	check(converted.is_class("AudioStreamPSX"),"Ordinary imported audio automatically gets the native SPU stream")
	check(audio.prepare(mono)==converted,"Conversion is cached per source")
	check(converted.get("adpcm_left").size()==ceil(2205.0/28)*16,"SPU data has 16-byte blocks for 28 samples")
	check(converted.get("adpcm_right").is_empty(),"Mono uses one hardware voice")
	check(absf(converted.get_length()-.1)<.0001,"Conversion preserves duration")
	var playback=converted.instantiate_playback();playback.start()
	var frames: PackedVector2Array=playback.mix_audio(1.0,ceili(AudioServer.get_mix_rate()*.1))
	check(energy(frames)>.03 and energy(frames)<.2,"Converted samples retain useful signal level")
	var crossings := 0
	for i in range(1,frames.size()):
		if frames[i-1].x<0 and frames[i].x>=0:crossings+=1
	check(crossings>=42 and crossings<=45,"ADPCM + Gaussian playback preserves 440 Hz pitch")
	playback.mix_audio(1,128)
	check(not playback.is_playing(),"One-shot reaches end and releases voice")
	var stereo: AudioStream=audio.prepare(make_tone(true))
	check(not stereo.get("adpcm_right").is_empty(),"Stereo retains independent SPU channels")
	var stereo_play=stereo.instantiate_playback();stereo_play.start()
	var stereo_frames: PackedVector2Array=stereo_play.mix_audio(1,512);stereo_play.stop()
	check(not stereo_frames[100].is_equal_approx(Vector2.ONE*stereo_frames[100].x),"Stereo image is not collapsed")
	mono.loop_mode=AudioStreamWAV.LOOP_FORWARD;mono.loop_begin=280;mono.loop_end=1960
	var looped=ClassDB.instantiate("AudioStreamPSX");looped.configure_source(mono)
	var loop_play=looped.instantiate_playback();loop_play.start();loop_play.mix_audio(1,12000)
	check(loop_play.is_playing() and loop_play.get_loop_count()>0,"Loop points survive conversion")
	loop_play.stop()
	var voices: Array=[]
	for i in 25:
		var voice=converted.instantiate_playback();voice.start();voices.append(voice)
	var count := 0
	for voice in voices:
		if voice.is_playing():count+=1
	check(count==24,"SPU path enforces the 24 mono-voice budget")
	for voice in voices:voice.stop()
	check(ResourceSaver.save(converted,"user://psx-audio-test.tres")==OK,"Converted stream can be serialized at import")
	var restored: AudioStream=ResourceLoader.load("user://psx-audio-test.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.is_class("AudioStreamPSX") and restored.get("adpcm_left")==converted.get("adpcm_left"),"Stored ADPCM survives save/load")
	var player := AudioStreamPlayer3D.new();player.stream=make_tone();root.add_child(player)
	check(player.stream.is_class("AudioStreamPSX"),"Dynamically added 3D audio is converted before playback")
	player.stream=make_tone(true)
	await process_frame
	await process_frame
	check(player.stream.is_class("AudioStreamPSX"),"Replacing a player's stream is handled automatically")
	player.queue_free()
	var reverb=ClassDB.instantiate("AudioEffectInstancePSX")
	var host_rate := int(AudioServer.get_mix_rate())
	# Supply a finite host-rate pulse spanning one SPU tick, including when the
	# device's first 48 kHz frame precedes that tick.
	var impulse := PackedVector2Array();impulse.resize(host_rate*2)
	for sample in ceili(host_rate/44100.0):impulse[sample]=Vector2(.7,0)
	var started := Time.get_ticks_usec()
	var result: PackedVector2Array=reverb.process_samples(impulse)
	report.reverb_seconds_for_2s_audio=(Time.get_ticks_usec()-started)/1000000.0
	check(energy(result,roundi(host_rate*.025),host_rate/2)>.00000001,"SPU reverb produces a tail after the impulse")
	var right_energy := 0.0
	for frame in result:right_energy+=frame.y*frame.y
	check(right_energy>.00001,"Different-side reflections reach opposite channel")
	check(energy(result,roundi(host_rate*1.5),host_rate*2)<energy(result,roundi(host_rate*.025),host_rate/2),"Reverb decays rather than accumulating")
	for frame in result:check(absf(frame.x)<=1 and absf(frame.y)<=1,"DSP saturates safely to signed 16-bit output")
	var has_effect := false
	for slot in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0,slot).is_class("AudioEffectPSXReverb"):has_effect=true
	check(has_effect,"All game buses retain the common signed 16-bit output stage")
	check(AudioServer.get_bus_index(&"PSX Reverb")>0 and AudioServer.get_bus_index(&"PSX Dry")>0,"SPU reverb sends and dry voices use separate paths")
	report.pitch_crossings=crossings;report.mono_rms=sqrt(energy(frames));report.reverb_right_energy=right_energy
	FileAccess.open("res://docs/psx-audio-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"measurements":report,"failures":failures},"\t"))
	print("PSX_AUDIO_OK: automatic wrapping, source cache, SPU ADPCM, Gaussian pitch, mono/stereo, loops, 24 voices, serialization, reverb tail/decay and master routing" if failures.is_empty() else "PSX_AUDIO_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
