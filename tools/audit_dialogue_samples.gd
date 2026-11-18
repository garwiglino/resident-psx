extends SceneTree
const Radio=preload("res://scripts/dialogue/intercom_filter.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Voice=preload("res://scripts/dialogue/dialogue_voice.gd")
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func measure(stream: AudioStream) -> Dictionary:
	if not stream:return {"missing":true}
	var playback := stream.instantiate_playback();playback.start()
	var rate := 22050;var count := ceili(stream.get_length()*rate);var peak := 0.0;var energy := 0.0;var frames := 0
	for offset in range(0,count,4096):
		var samples := playback.mix_audio(AudioServer.get_mix_rate()/float(rate),mini(4096,count-offset))
		for sample in samples:peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)));energy+=sample.length_squared()*.5;frames+=1
	playback.stop()
	return {"class":stream.get_class(),"length":stream.get_length(),"peak":peak,"rms":sqrt(energy/maxi(frames,1)),"rate":stream.get("mix_rate"),"frames":stream.get("frame_count")}
func run() -> void:
	for file in DirAccess.get_files_at("res://assets/audio/dialogs/1"):
		if not file.ends_with(".wav"):continue
		var path := "res://assets/audio/dialogs/1/"+file
		var source := AudioStreamWAV.load_from_file(path,{"compress/mode":0})
		var imported: AudioStream=load(path)
		var radio := Radio.build(imported)
		var line := Line.new();line.audio=imported;line.is_intercom=true
		report[file]={"raw":measure(source),"import":measure(imported),"duplicate":measure(imported.duplicate()),"radio":measure(radio),"radio_duplicate":measure(radio.duplicate()),"copied_line":measure(line.duplicate(true).voice_stream())}
		print(file," ",JSON.stringify(report[file]))
	FileAccess.open("res://docs/dialogue-sample-audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await create_timer(.15).timeout;quit()
