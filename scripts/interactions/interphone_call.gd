extends Node
## Transient pre-action cycle. Pauses with gameplay and never writes scene assets.
const Audio=preload("res://scripts/audio/psx_audio_routing.gd")
enum Phase { IDLE, RINGING, HANGUP, FINISHED }
signal finished
var phase := Phase.IDLE
var player: AudioStreamPlayer3D
var elapsed := 0.0
var duration := 0.0
var _hangup_length := 0.0
var _answered := false
var _suspended := false
var _position := Vector3.ZERO
var _sounds: Dictionary={}

func configure(phone: Node3D,button: Node3D,answered: bool) -> void:
	_sounds=phone.interphone_audio();duration=maxf(button.ringing_seconds,0);_answered=answered;_position=button.get_interaction_position()
	if button.ringing_sound_override:_sounds.ringing=button.ringing_sound_override

func start() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	player=AudioStreamPlayer3D.new();player.name="SonnerieInterphone";player.max_distance=9;add_child(player);player.global_position=_position
	Audio.set_category(player,&"Interactions");phase=Phase.RINGING;elapsed=0
	if duration<=0:_end_ringing()
	else:_play(_sounds.ringing,float(_sounds.ringing_db),true)

func _play(source: AudioStream,db: float,loop: bool) -> void:
	Audio.stop(player)
	if not source:player.stream=null;return
	# Never change a WAV import's loop flag, or the shared prepared sample.
	var prepared: AudioStream=get_node("/root/PSXAudio").prepare(source).duplicate()
	if prepared.is_class("AudioStreamPSX"):prepared.set("loop",loop)
	elif prepared is AudioStreamWAV:prepared.loop_mode=AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	player.stream=prepared;player.volume_db=db;Audio.play(player)

func _end_ringing() -> void:
	Audio.stop(player);elapsed=0
	if _answered:_complete();return
	phase=Phase.HANGUP;_play(_sounds.hangup,float(_sounds.hangup_db),false)
	_hangup_length=maxf(player.stream.get_length(),0) if player.stream else 0
	if _hangup_length<=0:_complete()

func _process(delta: float) -> void:
	if _suspended or phase in [Phase.IDLE,Phase.FINISHED]:return
	elapsed+=delta
	if phase==Phase.RINGING and elapsed>=duration:_end_ringing()
	elif phase==Phase.HANGUP and elapsed>=_hangup_length:_complete()

func _complete() -> void:
	if phase==Phase.FINISHED:return
	phase=Phase.FINISHED;Audio.stop(player);set_process(false);finished.emit()

func set_suspended(value: bool) -> void:
	_suspended=value
	if is_instance_valid(player):
		# AudioStreamPlayer3D may still have a pending key-on in this frame.
		# Disable processing as well so native SPU controls pause that pending voice.
		player.process_mode=Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
		player.stream_paused=value;Audio.sync_player(player)

func cancel() -> void:
	phase=Phase.FINISHED;set_process(false)
	if is_instance_valid(player):Audio.stop(player)

func _exit_tree() -> void:cancel()
