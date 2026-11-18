class_name LevelAmbienceLayer
extends Resource
## Une boucle d'ambiance avec son propre volume.
@export var stream: AudioStream
@export_range(-60.0,0.0,.5,"suffix:dB") var volume_db := -12.0
