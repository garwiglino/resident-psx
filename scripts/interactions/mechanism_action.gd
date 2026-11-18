@tool
class_name MechanismAction3D
extends "res://scripts/interactions/interactive_part.gd"
const Pose=preload("res://scripts/inventory/placement_pose.gd")
const TrackMask=preload("res://scripts/inventory/pose_track_mask.gd")
enum Behaviour { ACTION, SWITCH }
enum AfterInteraction { KEEP_VIEW, EXIT_VIEW }
@export_group("Comportement au clic")
@export_enum("Bouton / actions","Interrupteur actif / inactif") var behaviour: int=Behaviour.ACTION:
	set(value):behaviour=value;notify_property_list_changed()
## Les cinematiques rendent toujours la camera au gestionnaire avant leurs actions.
@export_enum("Rester sur l'objet","Quitter la vue puis lancer les actions") var after_interaction: int=AfterInteraction.KEEP_VIEW
## Raccourci pour un bouton : jouer ce dialogue, puis la liste Actions. Pour un autre ordre, utiliser une action Jouer un dialogue dans la liste.
@export var dialogue: DialogueSequence
## Vide : derive automatiquement de l'Interaction Id de cette partie, suffixe .active.
@export var state_flag: StringName
@export var initially_active := false
@export var off_selection_label := "DESACTIVER"
@export var off_actions: Array[WorldAction]=[]
@export_group("Animation de la partie - facultatif")
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export var activation_animation: StringName
## Interrupteur : vide = activation a l'envers pour revenir a l'etat inactif.
@export var deactivation_animation: StringName
@export_range(.05,5,.05) var animation_speed := 1.0
## Noeud ou Skeleton3D. Vide : seulement les pistes qui varient dans les clips.
@export_node_path("Node3D") var animated_root_path: NodePath
@export var bone_names := PackedStringArray()
@export_group("Son de la partie - facultatif")
@export var activation_sound: AudioStream
@export var deactivation_sound: AudioStream
@export_range(-40,0,.5,"suffix:dB") var mechanism_volume_db := -12.0
var _state_pose: RefCounted
var _mask: RefCounted
func _init() -> void:requires_open=false
func _flag() -> StringName:return state_flag if not state_flag.is_empty() else StringName(String(_id())+".active")
func can_interact() -> bool:return false # Only the object root offers world interaction.
func is_on() -> bool:return bool(WorldEvents.fact(StringName("flag.%s" % _flag()),initially_active))
func get_selection_label() -> String:return off_selection_label if behaviour==Behaviour.SWITCH and is_on() and not off_selection_label.is_empty() else selection_label
func animation_source() -> AnimationPlayer:return get_node_or_null(animation_player_path) as AnimationPlayer if not animation_player_path.is_empty() else null
func _ready() -> void:
	process_priority=85;set_process(false)
	if Engine.is_editor_hint():return
	selection_area();WorldEvents.state_changed.connect(_world_changed);WorldEvents.run_reset.connect(_reset);_sync()
func _enter_tree() -> void:
	super._enter_tree();add_to_group("psx_dynamic_geometry")
	if is_node_ready() and not Engine.is_editor_hint():call_deferred("_sync")
func _exit_tree() -> void:_dispose_pose()
func _world_changed(key: StringName,_value: Variant) -> void:
	if key==&"world.restored" or key==StringName("interaction.%s.used" % _id()) or (behaviour==Behaviour.SWITCH and key==StringName("flag.%s" % _flag())):_sync()
func _reset() -> void:_dispose_pose();call_deferred("_sync")
func set_inspection_active(value: bool) -> void:set_process(value and not Engine.is_editor_hint())
func _process(_delta: float) -> void:
	if not _busy:reapply_pose()
func reapply_pose() -> void:
	if _state_pose:_state_pose.advance(0)
func _dispose_pose() -> void:
	if _state_pose:_state_pose.finish(true);_state_pose=null
func _sync() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or _busy:return
	_dispose_pose()
	if behaviour==Behaviour.SWITCH:WorldEvents.set_flag(_flag(),is_on())
	if not configuration_error().is_empty():return
	if behaviour==Behaviour.ACTION and not WorldEvents.interaction_used(_id()):return
	_state_pose=Pose.new();sample_animation(_state_pose,self,is_on() if behaviour==Behaviour.SWITCH else true)
	if _state_pose.player:_state_pose.player.add_to_group("mechanism_pose_sampler")
	_state_pose.advance(_state_pose.length)
func sample_animation(pose: RefCounted,parent: Node,active: bool) -> void:
	var source := animation_source()
	if not source:return
	var clip := activation_animation if active else deactivation_animation;var backwards := clip.is_empty()
	if backwards:clip=deactivation_animation if active else activation_animation
	if clip.is_empty():return
	_mask=TrackMask.new();_mask.configure(self,source,[activation_animation,deactivation_animation],animated_root_path,bone_names)
	pose.begin(source,clip,parent,animation_speed,_mask.allows,backwards)
func intent() -> Dictionary:
	var active: bool=not is_on() if behaviour==Behaviour.SWITCH else true
	var list: Array=(off_actions if behaviour==Behaviour.SWITCH and not active else actions).duplicate()
	var reply := action_dialogue()
	if behaviour==Behaviour.ACTION and reply:
		var talk := WorldAction.new();talk.kind=WorldAction.Kind.DIALOGUE;talk.dialogue=reply;list.push_front(talk)
	return {"active":active,"actions":list,"event":interaction_event}
func action_dialogue() -> DialogueSequence:return dialogue
func has_click_effect() -> bool:return dialogue!=null or not actions.is_empty() or not interaction_event.is_empty() or not activation_animation.is_empty() or activation_sound!=null
## Optional cycle before committing/publishing actions; ordinary buttons have none.
func create_action_cycle(_data: Dictionary) -> Node:return null
func commit_action(data: Dictionary) -> bool:
	if not enabled or not _world_available() or not WorldCondition.all_match(requirements) or not configuration_error().is_empty():return false
	if behaviour==Behaviour.SWITCH:WorldEvents.set_flag(_flag(),bool(data.active))
	WorldEvents.mark_interaction(_id());return true
func publish_action(data: Dictionary,player: Node3D,lease: Node=null) -> int:
	if not StringName(data.event).is_empty():WorldEvents.raise_event(data.event,{"part_id":_id(),"active":bool(data.active)})
	var token: int=WorldEvents.start_job(data.actions,self,lease)
	interacted.emit(player);return token
func must_exit(data: Dictionary) -> bool:
	return after_interaction==AfterInteraction.EXIT_VIEW or data.actions.any(func(action: Resource):return action.kind==WorldAction.Kind.CINEMATIC)
func configuration_error() -> String:
	var error := super.configuration_error()
	if not error.is_empty():return error
	if not placement_owner():return "Placer cette partie sous une racine InteractiveObject3D."
	if behaviour==Behaviour.ACTION and not has_click_effect():return "Ajouter un Dialogue, une Action, un evenement, une animation ou un son a ce bouton."
	var reply := action_dialogue()
	if behaviour==Behaviour.ACTION and reply and reply.lines.is_empty():return "Le dialogue du bouton ne contient aucune replique."
	var source := animation_source()
	if not is_finite(animation_speed) or animation_speed<=0:return "Vitesse d'animation invalide."
	for clip in [activation_animation,deactivation_animation]:
		if not clip.is_empty() and (not source or not source.has_animation(clip)):return "Animation de la partie introuvable : "+String(clip)
	var scope := get_node_or_null(animated_root_path) if not animated_root_path.is_empty() else null
	if not animated_root_path.is_empty() and not scope is Node3D:return "Noeud anime introuvable."
	if not bone_names.is_empty():
		if not scope is Skeleton3D:return "Choisir un Skeleton3D avant de renseigner Bone Names."
		for bone in bone_names:
			if scope.find_bone(bone)<0:return "Os introuvable : "+bone
	for list in [actions,off_actions if behaviour==Behaviour.SWITCH else []]:
		for action in list:
			if not action:return "Action vide sur cette partie."
			error=action.validation_error(self)
			if not error.is_empty():return error
	return ""
func _validate_property(property: Dictionary) -> void:
	if property.name=="dialogue" and behaviour!=Behaviour.ACTION:property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name in ["state_flag","initially_active","off_selection_label","off_actions","deactivation_animation","deactivation_sound"] and behaviour!=Behaviour.SWITCH:property.usage&=~PROPERTY_USAGE_EDITOR
