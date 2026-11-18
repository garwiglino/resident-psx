extends SceneTree
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
const Voice=preload("res://scripts/dialogue/dialogue_voice.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func tail_energy(samples: PackedVector2Array) -> float:
	var energy := 0.0;var first := 8820
	for index in range(first,samples.size()):energy+=samples[index].length_squared()*.5
	return energy/maxi(samples.size()-first,1)
func run() -> void:
	check(Routing.setup(),"Native v12 supports per-voice reverb sends")
	var wet_index := AudioServer.get_bus_index(Routing.WET_BUS);var dry_index := AudioServer.get_bus_index(Routing.DRY_BUS)
	check(wet_index>0 and dry_index>0 and AudioServer.get_bus_send(dry_index)==&"Master","Radio dry bus goes straight to the master")
	var output_only := false;var wet_effect := false
	for slot in AudioServer.get_bus_effect_count(0):
		var effect := AudioServer.get_bus_effect(0,slot)
		if effect.is_class("AudioEffectPSXReverb"):output_only=is_zero_approx(effect.get("wet"))
	for slot in AudioServer.get_bus_effect_count(wet_index):
		var effect := AudioServer.get_bus_effect(wet_index,slot)
		if effect.is_class("AudioEffectPSXReverb"):wet_effect=effect.get("wet")>.2
	check(output_only and wet_effect,"Master keeps 16-bit output while only the send bus runs SPU reverb")
	var wave := AudioStreamWAV.new();wave.mix_rate=44100;wave.format=AudioStreamWAV.FORMAT_16_BITS
	var pcm := PackedByteArray();pcm.resize(882*2);pcm.encode_s16(220*2,24000);wave.data=pcm
	var line := Line.new();line.audio=wave;line.audio_volume_db=0;line.text="Reverb routing fixture."
	var style=load("res://assets/dialogue/default_style.tres").duplicate(false);style.intercom_open_sound=null;style.intercom_close_sound=null
	var voice := Voice.new();root.add_child(voice)
	var capture := AudioEffectCapture.new();capture.buffer_length=2;var slot := AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,capture)
	var tails: Dictionary={};var peaks: Dictionary={}
	for radio in [true,false]:
		line.is_intercom=radio;capture.clear_buffer();voice.play_line(line,style)
		check(voice.voice.bus==(Routing.DRY_BUS if radio else Routing.WET_BUS),"Voice chooses its send from Is Intercom")
		check(voice.opening.bus==Routing.DRY_BUS and voice.closing.bus==Routing.DRY_BUS,"Talkie opening and closing always bypass reverb")
		await create_timer(.8).timeout
		var samples := capture.get_buffer(capture.get_frames_available());var peak := 0.0
		for sample in samples:peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		peaks["radio" if radio else "normal"]=peak
		check(peak>.001,"Real master capture contains the routed impulse (radio=%s, peak=%f)" % [radio,peak])
		tails["radio" if radio else "normal"]=tail_energy(samples)
	check(tails.radio<.000000000001,"Intercom has no reverb tail at the actual audio output")
	check(tails.normal>.00000000001,"Normal speech retains an actual SPU reverb tail")
	var player := AudioStreamPlayer3D.new();root.add_child(player)
	check(player.bus==Routing.WET_BUS,"Ordinary 3D game sounds retain SPU reverb")
	AudioServer.add_bus();var custom_index := AudioServer.bus_count-1;AudioServer.set_bus_name(custom_index,&"ReverbCustomFixture");player.bus=&"ReverbCustomFixture"
	root.get_node("PSXAudio")._process(0)
	check(player.bus==&"ReverbCustomFixture" and AudioServer.get_bus_send(custom_index)==Routing.WET_BUS,"Custom bus assignment is preserved and its volume controls feed the SPU voice registers")
	Routing.set_reverb_enabled(player,false);check(player.bus==Routing.DRY_BUS,"Dry per-voice selection bypasses the custom send")
	Routing.set_reverb_enabled(player,true);check(player.bus==&"ReverbCustomFixture","Re-enabling reverb restores the original custom bus")
	voice.stop_line(false);voice.queue_free();player.queue_free();await process_frame;await create_timer(.15).timeout
	AudioServer.remove_bus_effect(0,slot);AudioServer.remove_bus(AudioServer.get_bus_index(&"ReverbCustomFixture"))
	FileAccess.open("res://docs/reverb-routing-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"tail_energy":tails,"peaks":peaks},"\t"))
	print("REVERB_ROUTING_OK: dry intercom and squelch, wet normal voice, measured output tails, common 16-bit output and custom buses" if failures.is_empty() else "REVERB_ROUTING_FAILED "+str(failures));quit(0 if failures.is_empty() else 1)
