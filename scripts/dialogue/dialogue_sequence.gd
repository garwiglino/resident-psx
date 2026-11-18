@tool
class_name DialogueSequence
extends Resource
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
enum Mode { CONVERSATION, EXPLORATION_CALL }
@export var id: StringName=&"dialogue"
## Conversation bloque les commandes ; Appel laisse jouer et avance avec les voix.
@export_enum("Conversation - validation manuelle","Appel en exploration - automatique") var mode: int=Mode.CONVERSATION
@export var lines: Array[Line]=[]
@export_group("Lecture automatique")
## Temps minimum de presence de chaque page, meme si le WAV est tres court.
@export_range(.5,5,.1,"suffix:s") var minimum_page_seconds := 1.2
@export_range(10,80,1,"suffix:caracteres/s") var reading_characters_per_second := 32.0
@export_range(0,2,.05,"suffix:s") var reply_gap := .2

func is_exploration_call() -> bool:return mode==Mode.EXPLORATION_CALL
