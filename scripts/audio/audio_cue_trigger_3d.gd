@tool
class_name AudioCueTrigger3D
extends Area3D
const Manager=preload("res://scripts/audio/level_audio_manager.gd")
const Cue=preload("res://scripts/audio/audio_cue.gd")
@export var enabled := true
## Une ressource directe, ou un identifiant dans les Cues du profil de niveau.
@export var cue: Cue
@export var cue_id: StringName=&"scare"
@export var once := true
@export_node_path("LevelAudioManager") var manager_path: NodePath
var used := false

func _init() -> void:
	collision_layer=0;collision_mask=2

func _ready() -> void:
	if Engine.is_editor_hint():return
	process_mode=Node.PROCESS_MODE_PAUSABLE
	body_entered.connect(_entered)
	call_deferred("_prepare_audio")

func _prepare_audio() -> void:
	var manager := Manager.find_for(self,manager_path)
	if manager:manager.prepare_effect(cue)

func _entered(body: Node3D) -> void:
	if body.is_in_group("audio_listener_player"):trigger()

## Peut aussi etre appele par un signal de porte, un evenement, etc.
func trigger() -> bool:
	if Engine.is_editor_hint() or not enabled or (once and used):return false
	var manager := Manager.find_for(self,manager_path)
	if not manager:return false
	var played: bool=manager.play_effect(cue,global_position) if cue else manager.play_cue(cue_id,global_position)
	if played:used=true
	return played

func reset() -> void:used=false
