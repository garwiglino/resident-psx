@tool
class_name DialogueLine
extends Resource
const Radio=preload("res://scripts/dialogue/intercom_filter.gd")
@export var speaker := "POLICIERE"
@export_multiline var text := ""
## 0 utilise la cadence du style.
@export_range(0.0,120.0,1.0,"suffix:lettres/s") var characters_per_second := 0.0
@export_group("Evenements")
## Evenement WorldEvents au debut de la replique.
@export var event_id: StringName
## Evenement WorldEvents apres toute la replique (pas apres chaque page).
## end_intercom est aussi reconnu ici pour raccrocher le talkie.
@export var end_event_id: StringName
## Emet end_intercom a la fin : coupe le fond radio et joue le son de raccroche.
@export var end_intercom := false
@export_group("Delai de reponse")
## Appel automatique : remplacer la pause apres cette replique, avant la suivante.
@export var override_reply_gap := false
@export_range(0,30,.05,"suffix:s") var reply_gap := .2
@export_group("Voix")
## Une voix pour toute la replique, meme lorsque le texte utilise plusieurs pages.
@export var audio: AudioStream:
	set(value):
		if audio and audio.changed.is_connected(_audio_changed):audio.changed.disconnect(_audio_changed)
		audio=value
		if audio and not audio.changed.is_connected(_audio_changed):audio.changed.connect(_audio_changed)
		intercom_audio=null;_bake_radio();emit_changed()
@export_range(-40,0,.5,"suffix:dB") var audio_volume_db := -8.0
@export var is_intercom := false:
	set(value):is_intercom=value;_bake_radio();emit_changed()
## External binary SPU sample: no embedded audio bytes in scenes or text resources.
@export_storage var intercom_audio: AudioStream:
	set(value):
		intercom_audio=Radio.store_prepared(audio,value) if Engine.is_editor_hint() and value else value

func prepare_external_audio() -> void:
	if not is_intercom or not audio:return
	if intercom_audio:intercom_audio=Radio.store_prepared(audio,intercom_audio)
	elif Engine.is_editor_hint():_bake_radio()

func _audio_changed() -> void:
	Radio.invalidate(audio);intercom_audio=null;_bake_radio();emit_changed()

func _bake_radio() -> void:
	if Engine.is_editor_hint() and is_intercom and audio:intercom_audio=Radio.build(audio)

func voice_stream() -> AudioStream:
	if not is_intercom:return audio
	if audio and audio.has_meta("psx_intercom_stream"):return audio.get_meta("psx_intercom_stream")
	if not intercom_audio:intercom_audio=Radio.build(audio)
	return intercom_audio

func response_gap(default_gap: float) -> float:
	return maxf(reply_gap if override_reply_gap else default_gap,0)

func hangs_up_intercom() -> bool:
	return end_intercom or end_event_id==&"end_intercom"
