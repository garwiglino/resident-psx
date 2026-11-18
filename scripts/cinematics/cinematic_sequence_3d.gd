@tool
class_name CinematicSequence3D
extends Node3D
const Dialogue=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
const Montage=preload("res://scripts/cinematics/timeline_montage.gd")

signal event_reached(id: StringName)
signal montage_changed
@export var id: StringName=&"cinematic"
@export_node_path("AnimationPlayer") var timeline_path := NodePath("Timeline")
@export var animation: StringName=&"cinematic"
@export_node_path("Camera3D") var entry_camera := NodePath("CameraA")
@export var skippable := true
## Bibliotheque de textes disponibles dans le panneau Cinematiques.
## Les anciens reperes show_dialogue sont importes sans modifier les cles.
@export var dialogues: Array[Dialogue]=[]
## Le panneau Cinematiques permet de monter ces plans dans la carte.
## Vide : les plans sont lus depuis les anciens reperes sans modifier les cles.
@export var plans: Array[Shot]=[]:
	set(value):plans=value;montage_changed.emit()
@export_storage var classic_timeline := false
var _director: Node

func get_plans() -> Array[Shot]:return plans if not plans.is_empty() else Montage.from_sequence(self)

func set_montage_library(name: StringName,library: AnimationLibrary) -> void:
	var player := get_node_or_null(timeline_path) as AnimationPlayer
	if not player:return
	if player.has_animation_library(name):player.remove_animation_library(name)
	if library:player.add_animation_library(name,library)
	montage_changed.emit()

func validation_error() -> String:
	var timeline := get_node_or_null(timeline_path) as AnimationPlayer
	if not timeline:return "Assigner un AnimationPlayer dans Timeline Path."
	if not timeline.autoplay.is_empty():return "Laisser Autoplay vide : le gestionnaire declenche Timeline."
	if classic_timeline or plans.is_empty():
		if not timeline.has_animation(animation):return "L'animation choisie n'existe pas dans Timeline."
		if timeline.get_animation(animation).loop_mode!=Animation.LOOP_NONE:return "La timeline de cinematique doit etre sans boucle."
		if not get_node_or_null(entry_camera) is Camera3D:return "Assigner une Camera3D dans Entry Camera."
	if timeline.speed_scale<=0:return "La vitesse de Timeline doit etre positive."
	if not classic_timeline:
		var montage := get_plans()
		if montage.is_empty():return "Ajouter un plan dans le panneau Cinematiques."
		for index in montage.size():
			if not montage[index]:return "Plan vide : "+str(index+1)
			var error := montage[index].validation_error(self,timeline)
			if not error.is_empty():return "Plan %d : %s" % [index+1,error]
		var actors: Array[Node]=[]
		for plan in montage:
			for cue in plan.actors:
				var actor: Node=cue.actor(self)
				for other in actors:
					if other!=actor and (actor.is_ancestor_of(other) or other.is_ancestor_of(actor)):return "Choisir la racine de chaque personnage : deux pistes ciblent des personnages imbriques."
				if actor not in actors:actors.append(actor)
	for camera in find_children("*","Camera3D",true,false):
		if camera.projection==Camera3D.PROJECTION_FRUSTUM:return "Utiliser une camera perspective ou orthogonale pour le rendu PSX."
	return ""

func _get_configuration_warnings() -> PackedStringArray:
	var error := validation_error()
	return PackedStringArray([error]) if not error.is_empty() else PackedStringArray()

## These methods are authored in native AnimationPlayer Call Method tracks.
func cut_to(camera_path: NodePath) -> void:
	if not classic_timeline:return
	if is_instance_valid(_director):_director.change_camera(get_node_or_null(camera_path),0)

func blend_to(camera_path: NodePath,seconds := .5) -> void:
	if not classic_timeline:return
	if is_instance_valid(_director):_director.change_camera(get_node_or_null(camera_path),seconds)

func show_dialogue(index: int,wait_for_finish := true) -> void:
	if not classic_timeline:return
	if not is_instance_valid(_director):return
	if index<0 or index>=dialogues.size():_director.cancel(&"invalid_dialogue");return
	_director.show_dialogue(dialogues[index],wait_for_finish)

func next_plan() -> void:
	if is_instance_valid(_director):_director.next_plan()

func emit_event(event: StringName) -> void:
	if not is_instance_valid(_director):return
	event_reached.emit(event)
	if is_instance_valid(_director):_director.event_reached.emit(self,event)
