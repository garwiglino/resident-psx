@tool
class_name Interphone3D
extends "res://scripts/interactions/interactive_object.gd"
## Reglages sonores communs. Chaque InterphoneButton3D regle sa duree d'appel.
@export_group("Interphone - sonnerie")
@export var ringing_sound: AudioStream=preload("res://assets/audio/interactables/interphone_ring_loop.wav")
@export_range(-40,0,.5,"suffix:dB") var ringing_volume_db := -10.0
@export_group("Interphone - sans reponse")
@export var hangup_sound: AudioStream=preload("res://assets/audio/ui/intercom_end.wav")
@export_range(-40,0,.5,"suffix:dB") var hangup_volume_db := -6.0

func interphone_audio() -> Dictionary:
	return {"ringing":ringing_sound,"ringing_db":ringing_volume_db,"hangup":hangup_sound,"hangup_db":hangup_volume_db}
