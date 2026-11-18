@tool
class_name InterphoneButton3D
extends "res://scripts/interactions/mechanism_action.gd"
const Call=preload("res://scripts/interactions/interphone_call.gd")
const Text=preload("res://scripts/dialogue/dialogue_text.gd")
enum Response { ASSIGNED_DIALOGUE, NO_ANSWER }
@export_group("Appel interphone")
## Temps total de sonnerie, silences de la boucle compris, apres l'appui du bouton.
@export_range(0,120,.1,"suffix:s") var ringing_seconds := 4.0
## Un dialogue assigne se lit automatiquement. Sans dialogue, l'appel raccroche.
@export_enum("Dialogue automatique si assigne","Personne ne repond") var response: int=Response.ASSIGNED_DIALOGUE:
	set(value):response=value;notify_property_list_changed()
## Vide : sonnerie commune de la racine Interphone3D.
@export var ringing_sound_override: AudioStream

func has_click_effect() -> bool:return true
func action_dialogue() -> DialogueSequence:return dialogue if response==Response.ASSIGNED_DIALOGUE else null

func intent() -> Dictionary:
	var data := super.intent();var call_actions: Array[WorldAction]=[];var answered := false
	for action: WorldAction in data.actions:
		if action.kind!=WorldAction.Kind.DIALOGUE:call_actions.append(action);continue
		if response==Response.NO_ANSWER:continue
		if not action.dialogue.lines.any(func(line: Resource):return line and not Text.plain(line.text).strip_edges().is_empty()):continue
		var copy: WorldAction=action.duplicate(false)
		copy.dialogue=action.dialogue.duplicate(false);copy.dialogue.mode=DialogueSequence.Mode.EXPLORATION_CALL;copy.wait_for_completion=true
		call_actions.append(copy);answered=true
	data.actions=call_actions;data["interphone_answered"]=answered;return data

func create_action_cycle(data: Dictionary) -> Node:
	var cycle := Call.new();cycle.configure(placement_owner(),self,bool(data.get("interphone_answered",false)));return cycle

func must_exit(data: Dictionary) -> bool:
	# A phone keeps its view through the reply. Cinematic actions still hand off.
	return data.actions.any(func(action: Resource):return action.kind==WorldAction.Kind.CINEMATIC)

func configuration_error() -> String:
	var error := super.configuration_error()
	if not error.is_empty():return error
	var phone := placement_owner()
	if not phone or not phone.has_method("interphone_audio"):return "Placer ce bouton sous une racine Interphone3D."
	if behaviour!=Behaviour.ACTION:return "Un bouton d'interphone utilise le comportement Bouton / actions."
	if not is_finite(ringing_seconds) or ringing_seconds<0:return "Duree de sonnerie invalide."
	if ringing_seconds>0 and not ringing_sound_override and not phone.ringing_sound:return "Assigner la sonnerie sur la racine Interphone ou sur ce bouton."
	return ""

func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property.name in ["behaviour","after_interaction"]:property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="dialogue" and response==Response.NO_ANSWER:property.usage&=~PROPERTY_USAGE_EDITOR
