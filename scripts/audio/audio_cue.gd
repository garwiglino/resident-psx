class_name LevelAudioCue
extends Resource
## Effet ponctuel : peur, impact lointain, evenement, etc.
@export var id: StringName=&"scare"
@export var variants: Array[AudioStream]=[]
@export_enum("Stingers","SFX","Interactions","Ambience","Weapons","UI") var audio_category := "Stingers"
@export_range(-60.0,0.0,.5,"suffix:dB") var volume_db := -6.0
@export_range(0.0,60.0,.1,"suffix:s") var cooldown_seconds := 1.0
@export_group("Position")
## Desactive : son global, adapte a un accent musical de peur.
@export var spatial := false
@export_range(1.0,100.0,.5,"suffix:m") var max_distance := 20.0
@export_group("Priorite sur la musique")
## Baisse temporairement la musique sans l'arreter.
@export_range(-30.0,0.0,.5,"suffix:dB") var music_duck_db := -8.0
@export_range(0.0,10.0,.1,"suffix:s") var duck_seconds := .8
