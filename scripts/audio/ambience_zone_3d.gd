@tool
class_name AmbienceZone3D
extends Area3D
const Manager=preload("res://scripts/audio/level_audio_manager.gd")
const Layer=preload("res://scripts/audio/ambience_layer.gd")
@export var enabled := true
## Remplace entierement l'ambiance par defaut. Vide = zone silencieuse.
@export var ambience_layers: Array[Layer]=[]
## La priorite la plus haute gagne. A egalite, la derniere zone entree gagne.
@export var audio_priority := 0
@export_range(0.0,10.0,.1,"suffix:s") var transition_seconds := 1.5
## Facultatif : laisser vide pour trouver AudioNiveau dans la carte.
@export_node_path("LevelAudioManager") var manager_path: NodePath
var _manager: Node
var _listeners: Array[Node3D]=[]

func _init() -> void:
	collision_layer=0;collision_mask=2

func _ready() -> void:
	if Engine.is_editor_hint():return
	process_mode=Node.PROCESS_MODE_PAUSABLE
	body_entered.connect(_entered);body_exited.connect(_exited)
	call_deferred("_prepare_audio")

func _prepare_audio() -> void:
	_manager=Manager.find_for(self,manager_path)
	if _manager:_manager.prepare_ambience(ambience_layers)

func _entered(body: Node3D) -> void:
	if not body.is_in_group("audio_listener_player"):return
	if body not in _listeners:_listeners.append(body)
	_manager=Manager.find_for(self,manager_path)
	if _manager:_manager.enter_zone(self)

func _exited(body: Node3D) -> void:
	_listeners.erase(body)
	if _listeners.is_empty() and is_instance_valid(_manager):_manager.leave_zone(self)

func _exit_tree() -> void:
	if not Engine.is_editor_hint() and is_instance_valid(_manager):_manager.leave_zone(self)
