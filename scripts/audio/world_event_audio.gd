extends Node
## Built-in world-event sounds are shared by both dialogue channels. One listener
## avoids double playback when an exploration call and a conversation coexist.
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
var settings: Resource=preload("res://assets/dialogue/settings.tres")
const INTERCOM_END := "res://assets/audio/ui/intercom_end.wav"
var intercom_end_stream: AudioStream
var player: AudioStreamPlayer
var _missing_reported := false
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	player=AudioStreamPlayer.new();player.name="IntercomHangup"
	Routing.set_category(player,&"Radio FX");Routing.set_reverb_enabled(player,false)
	player.volume_db=settings.volume_raccroche_db;add_child(player)
func play_event(id: StringName,_payload: Dictionary={}) -> void:
	if id!=&"end_intercom":return
	if not intercom_end_stream and ResourceLoader.exists(INTERCOM_END):intercom_end_stream=load(INTERCOM_END)
	if not intercom_end_stream:
		if not _missing_reported:push_warning("Son de raccroche manquant : "+INTERCOM_END);_missing_reported=true
		return
	var prepared: AudioStream=get_node("/root/PSXAudio").prepare(intercom_end_stream).duplicate()
	prepared.set("loop",false);player.stream=prepared;player.volume_db=settings.volume_raccroche_db;Routing.play(player)

func stop() -> void:
	Routing.stop(player)
