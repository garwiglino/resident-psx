@tool
class_name CinematicShot
extends Resource
const Dialogue=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Actor=preload("res://scripts/cinematics/cinematic_actor_clip.gd")
enum Progression { LINKED, CAMERA, MANUAL }
@export var title := "Plan"
@export var camera_path := NodePath("CameraA")
@export var animation: StringName=&"cinematic"
@export_range(0,3600,.01,"suffix:s") var start_time := 0.0
## -1 = fin de l'animation. Les cles d'origine ne sont pas decoupees.
@export_range(-1,3600,.01,"suffix:s") var end_time := -1.0
@export var dialogue: Dialogue
@export_range(0,3600,.01,"suffix:s") var dialogue_delay := 0.0
@export_enum("Camera et dialogue valides","Fin du mouvement / dialogue independant","Validation manuelle") var progression: int=Progression.LINKED
## La premiere pression revele le texte. La validation finale termine le mouvement.
@export var finish_camera_on_confirm := true
## Emis une fois, meme quand la validation termine le mouvement avant son terme.
@export var finished_event: StringName
## Pistes de personnages sur le meme curseur que la camera et le dialogue.
@export var actors: Array[Actor]=[]

func end_position(timeline: AnimationPlayer) -> float:
	return timeline.get_animation(animation).length if end_time<0 and timeline and timeline.has_animation(animation) else end_time

func camera_duration(timeline: AnimationPlayer) -> float:return maxf(end_position(timeline)-start_time,0)

func duration(timeline: AnimationPlayer) -> float:
	var result := camera_duration(timeline)
	var sequence := timeline.get_node_or_null(timeline.root_node) if timeline else null
	if sequence:
		for cue in actors:
			if cue:result=maxf(result,cue.start_time+cue.length(sequence))
	return result

func validation_error(sequence: Node,timeline: AnimationPlayer) -> String:
	if not sequence.get_node_or_null(camera_path) is Camera3D:return "Camera absente : "+String(camera_path)
	if not timeline or not timeline.has_animation(animation):return "Animation absente : "+String(animation)
	var clip := timeline.get_animation(animation)
	if clip.loop_mode!=Animation.LOOP_NONE:return "Le mouvement du plan ne doit pas boucler."
	if start_time<0 or end_position(timeline)<start_time or end_position(timeline)>clip.length+.00001:return "Bornes du plan hors de l'animation."
	if dialogue:
		var valid := false
		for line in dialogue.lines:
			if line and not line.text.strip_edges().is_empty():valid=true
		if not valid:return "Le dialogue du plan est vide."
	if progression<0 or progression>Progression.MANUAL:return "Condition de passage inconnue."
	for cue in actors:
		if not cue:return "Piste de personnage vide."
		var error: String=cue.validation_error(sequence)
		if not error.is_empty():return error
		for other in actors:
			if cue!=other and cue.actor(sequence)==other.actor(sequence) and cue.start_time<other.start_time+other.length(sequence)-.000001 and other.start_time<cue.start_time+cue.length(sequence)-.000001:return "Deux animations se chevauchent sur le meme personnage."
	return ""
