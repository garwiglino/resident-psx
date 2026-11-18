extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	root.get_node("PSXAudio").set_process(false)
	await create_timer(.25).timeout
	var effect: AudioEffect
	var instance: AudioEffectInstance
	for slot in AudioServer.get_bus_effect_count(0):
		var candidate := AudioServer.get_bus_effect(0,slot)
		if candidate.has_method("set_output_rate"):effect=candidate;instance=AudioServer.get_bus_effect_instance(0,slot)
	check(effect!=null and instance!=null,"The actual output uses the new native sampling stage")
	if not effect or not instance:quit(1);return
	var directory := "res://exports/audio_mix_test/output"
	DirAccess.make_dir_recursive_absolute(directory);FileAccess.open(directory+"/.gdignore",FileAccess.WRITE).store_string("")
	var host := int(AudioServer.get_mix_rate());var captures := []
	for rate in [22050,44100]:
		effect.set("output_rate",rate)
		for frequency in [1000,14000]:
			var input := PackedVector2Array();input.resize(host)
			for frame in host:input[frame]=Vector2.ONE*(sin(TAU*frequency*frame/host)*.25)
			var output: PackedVector2Array=instance.process_samples(input)
			var path := directory+"/%d_%d.f32" % [rate,frequency]
			FileAccess.open(path,FileAccess.WRITE).store_buffer(output.to_byte_array())
			captures.append({"rate":rate,"frequency":frequency,"path":path,"host_rate":host})
	effect.set("output_rate",22050)
	FileAccess.open("res://docs/audio-output-rate-captures.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures,"captures":captures},"\t"))
	print("AUDIO_OUTPUT_RATE_CAPTURE_OK ",host," Hz device, 22050 Hz mix");quit(0 if failures.is_empty() else 1)
