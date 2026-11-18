@tool
extends Node
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
## The audio belongs to the whole reply, not to a page or a camera shot.
enum Phase { SILENT, OPENING, VOICE, CLOSING }
signal phase_changed(phase: int)
var phase := Phase.SILENT
var voice: AudioStreamPlayer
var opening: AudioStreamPlayer
var closing: AudioStreamPlayer
var radio_loop: AudioStreamPlayer
var current_line: Resource
var _stream: AudioStream
var _radio_open := false
var _watchdog := 0.0
var _suspended := false
var speech_complete := true
var speech_duration := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	voice=_player("DialogueVoice");opening=_player("IntercomOpen");closing=_player("IntercomClose")
	radio_loop=_player("IntercomLoop")
	opening.finished.connect(_opening_finished);voice.finished.connect(_voice_finished);closing.finished.connect(func():if phase==Phase.CLOSING:_phase(Phase.SILENT))

func _player(label: String) -> AudioStreamPlayer:
	var node := AudioStreamPlayer.new();node.name=label;node.max_polyphony=1
	# Squelch sounds are always radio sounds, including when the next reply is
	# already a normal voice while the preceding radio close is still audible.
	node.set_meta("psx_reverb",label=="DialogueVoice");Routing.set_category(node,&"Voices" if label=="DialogueVoice" else &"Radio FX");add_child(node);Routing.route(node);return node

func _phase(value: int) -> void:
	phase=value;_watchdog=0
	var node: AudioStreamPlayer=opening if value==Phase.OPENING else (voice if value==Phase.VOICE else closing)
	if value!=Phase.SILENT and node.stream:_watchdog=node.stream.get_length()+.2
	phase_changed.emit(value)

func _process(delta: float) -> void:
	for player in [voice,opening,closing,radio_loop]:Routing.sync_player(player)
	if _suspended or phase==Phase.SILENT:return
	# If the 24 SPU voices are exhausted, a refused sample must not leave the
	# radio stuck waiting for a finished signal that cannot arrive.
	_watchdog-=delta
	if _watchdog>0:return
	match phase:
		Phase.OPENING:_opening_finished()
		Phase.VOICE:_voice_finished()
		Phase.CLOSING:_phase(Phase.SILENT)

func play_line(line: Resource,style: Resource) -> void:
	stop_line();current_line=line
	Routing.set_reverb_enabled(voice,not line.is_intercom)
	if not line.audio:return
	_stream=_prepare(line.voice_stream())
	if not _stream:return
	# Dialogue audio never loops, even if a mistakenly looping music import is used.
	_stream=_stream.duplicate();_stream.set("loop",false)
	voice.stream=_stream;voice.volume_db=line.audio_volume_db
	speech_duration=_stream.get_length();speech_complete=false
	if line.is_intercom:
		opening.stream=_prepare(style.intercom_open_sound);closing.stream=_prepare(style.intercom_close_sound)
		opening.volume_db=style.intercom_volume_db;closing.volume_db=style.intercom_volume_db;_radio_open=true
		# Own the loop flag; the shared imported asset remains a one-shot.
		radio_loop.stream=null
		var background := _prepare(style.intercom_loop_sound)
		if background:
			background=background.duplicate();background.set("loop",true)
			radio_loop.stream=background
		radio_loop.volume_db=style.intercom_loop_volume_db
		# Opening is an onset effect, not a blocking pre-roll. Speech starts in
		# the same controller tick as the first typewriter glyph.
		if opening.stream:Routing.play(opening)
	_start_voice()

func _prepare(stream: AudioStream) -> AudioStream:
	if not stream or stream.is_class("AudioStreamPSX"):return stream
	var spu := get_node_or_null("/root/PSXAudio")
	if spu:return spu.prepare(stream)
	var converted: AudioStream=ClassDB.instantiate("AudioStreamPSX")
	return converted if converted.configure_source(stream) else stream

func _opening_finished() -> void:
	if phase==Phase.OPENING and current_line:_start_voice()

func _start_voice() -> void:
	Routing.play(voice)
	if _radio_open and radio_loop.stream:Routing.play(radio_loop)
	_phase(Phase.VOICE)

func _voice_finished() -> void:
	if phase==Phase.VOICE:speech_complete=true;Routing.stop(opening);Routing.stop(voice);_close_radio()

func speech_position() -> float:
	if speech_complete:return speech_duration
	# Follow the audible source position instead of a separate per-frame timer.
	return clampf(voice.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency(),0,speech_duration)

func _close_radio() -> void:
	Routing.stop(radio_loop)
	if _radio_open:
		_radio_open=false
		if closing.stream:Routing.play(closing);_phase(Phase.CLOSING);return
	_phase(Phase.SILENT)

func stop_line(play_close := true) -> void:
	if not is_instance_valid(voice):return
	Routing.stop(opening);Routing.stop(voice);Routing.stop(radio_loop);current_line=null;_stream=null
	speech_complete=true;speech_duration=0
	if play_close:_close_radio()
	else:Routing.stop(closing);_radio_open=false;_phase(Phase.SILENT)

func set_suspended(value: bool) -> void:
	_suspended=value
	for node in [voice,opening,closing,radio_loop]:node.stream_paused=value;Routing.sync_player(node)

func _exit_tree() -> void:stop_line(false)
