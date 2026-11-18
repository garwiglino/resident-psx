class_name LevelAudioProfile
extends Resource
const Layer=preload("res://scripts/audio/ambience_layer.gd")
const Cue=preload("res://scripts/audio/audio_cue.gd")
@export_group("Ambiance par defaut")
## Jusqu'a trois couches simultanees. Chaque couche a son propre volume.
@export var ambience_layers: Array[Layer]=[]
@export_group("Musique")
@export var exploration_music: AudioStream
@export var combat_music: AudioStream
@export_range(-60.0,0.0,.5,"suffix:dB") var exploration_volume_db := -14.0
@export_range(-60.0,0.0,.5,"suffix:dB") var combat_volume_db := -12.0
@export_group("Transitions")
@export_range(0.0,10.0,.1,"suffix:s") var crossfade_seconds := 1.5
## Attente apres la derniere menace avant le retour a l'exploration.
@export_range(0.0,30.0,.1,"suffix:s") var combat_release_delay := 4.0
@export_group("Effets ponctuels")
@export var cues: Array[Cue]=[]
