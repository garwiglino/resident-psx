extends SceneTree
const Voice=preload("res://scripts/dialogue/dialogue_voice.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var audio := Voice.new();root.add_child(audio)
	var style: Resource=load("res://assets/dialogue/default_style.tres")
	var shared: AudioStream=style.intercom_loop_sound
	var original_loop: bool=shared.get("loop")
	var line := Line.new();line.audio=load("res://assets/audio/dialogs/1/1_Chapter_1.wav");line.is_intercom=true
	audio.play_line(line,style)
	check(audio.voice.playing and audio.radio_loop.playing and audio.opening.playing,"Voix, ouverture et fond radio demarrent dans le meme tick")
	check(audio.radio_loop.stream.get("loop") and shared.get("loop")==original_loop,"La boucle utilise une copie privee du fichier importe")
	check(audio.radio_loop.bus==&"Radio FX Dry" and not audio.radio_loop.get_meta("psx_reverb"),"Le fond radio suit Intercom Effets et reste sans reverb")
	check(audio.radio_loop.volume_db==style.intercom_loop_volume_db,"Le volume du fond est reglable separement dans le style")
	await create_timer(shared.get_length()+.2).timeout
	check(audio.voice.playing and audio.radio_loop.playing and audio.radio_loop.get_stream_playback().get_loop_count()>0,"Le fond boucle pendant une longue replique")
	var cursor := audio.radio_loop.get_playback_position();audio.set_suspended(true)
	await create_timer(.12).timeout
	check(audio.radio_loop.stream_paused and absf(cursor-audio.radio_loop.get_playback_position())<.03,"La pause conserve la position du fond radio")
	audio.set_suspended(false);await create_timer(.12).timeout
	check(not audio.radio_loop.stream_paused and audio.radio_loop.playing,"Le fond reprend avec la voix")
	audio.stop_line()
	check(not audio.voice.playing and not audio.radio_loop.playing and audio.closing.playing,"Passer la replique arrete la voix et le fond, puis ferme le talkie")
	audio.play_line(line,style);audio._voice_finished()
	check(not audio.radio_loop.playing and audio.phase==Voice.Phase.CLOSING,"La fin naturelle arrete egalement le fond")
	line.is_intercom=false;audio.play_line(line,style)
	check(audio.voice.playing and not audio.radio_loop.playing,"Une replique normale ne joue aucun fond radio")
	line.is_intercom=true;line.audio=null;audio.play_line(line,style)
	check(not audio.radio_loop.playing,"Une replique sans WAV ne lance pas de boucle isolee")
	line.audio=load("res://assets/audio/dialogs/1/1_Chapter_1.wav");audio.play_line(line,style);audio.stop_line(false)
	check(not audio.radio_loop.playing and not audio.closing.playing,"Une annulation complete ne laisse aucun fond actif")
	audio.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/intercom-loop-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures,"loop_volume_db":style.intercom_loop_volume_db},"\t"))
	print("INTERCOM_LOOP_OK " if failures.is_empty() else "INTERCOM_LOOP_FAILED ",JSON.stringify(failures));quit(0 if failures.is_empty() else 1)
