@tool
class_name CinematicActorClip
extends Resource
## One full-body animation cue, on the same clock as the current shot.
@export_node_path("Node3D") var actor_path: NodePath
## Optional GLB/scene containing the animation. Empty uses the actor's own player.
@export var source: PackedScene:
	set(value):
		if source and source.changed.is_connected(_invalidate_source):source.changed.disconnect(_invalidate_source)
		source=value;_invalidate_source()
		if source and not source.changed.is_connected(_invalidate_source):source.changed.connect(_invalidate_source)
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export var animation: StringName=&"idle"
@export_range(0,3600,.01,"suffix:s") var start_time := 0.0
@export_range(0,3600,.01,"suffix:s") var source_offset := 0.0
## -1 = play the remaining source once. Set a duration to repeat a looping cue.
@export_range(-1,3600,.01,"suffix:s") var duration := -1.0
@export_range(.05,4,.05) var speed := 1.0
@export var loop := false
@export var apply_root_motion := true
var _source_clips: Dictionary={}

func _invalidate_source() -> void:_source_clips.clear()

func actor(sequence: Node) -> Node3D:return sequence.get_node_or_null(actor_path) as Node3D if not actor_path.is_empty() else null

func player(sequence: Node) -> AnimationPlayer:
	var target := actor(sequence)
	if not target:return null
	if not animation_player_path.is_empty():return target.get_node_or_null(animation_player_path) as AnimationPlayer
	var motion: Variant=target.get("motion")
	if motion and is_instance_valid(motion) and motion.get("mixer") is AnimationPlayer:return motion.mixer
	var players := target.find_children("*","AnimationPlayer",true,false)
	return players[0] if not players.is_empty() else null

func animations(sequence: Node) -> Dictionary:
	var result: Dictionary={}
	if source:
		if not _source_clips.is_empty():return _source_clips
		var state := source.get_state()
		for node in state.get_node_count():
			if state.get_node_type(node)!="AnimationPlayer":continue
			for property in state.get_node_property_count(node):
				var library: Variant=state.get_node_property_value(node,property)
				if library is AnimationLibrary:
					for key in library.get_animation_list():
						if key!=&"RESET":result[key]=library.get_animation(key)
		_source_clips=result
	else:
		var mixer := player(sequence)
		if mixer:
			for key in mixer.get_animation_list():
				if key!=&"RESET":result[key]=mixer.get_animation(key)
	return result

func clip(sequence: Node) -> Animation:return animations(sequence).get(animation)

func animation_root(sequence: Node) -> Node:
	var mixer := player(sequence)
	return mixer.get_node_or_null(mixer.root_node) if mixer else actor(sequence)

func length(sequence: Node) -> float:
	if duration>=0:return duration
	var value := clip(sequence)
	return maxf((value.length-source_offset)/maxf(speed,.001),0) if value else 0.0

func validation_error(sequence: Node) -> String:
	if not actor(sequence):return "Personnage absent : "+String(actor_path)
	var value := clip(sequence)
	if not value:return "Animation du personnage absente : "+String(animation)
	if speed<=0 or start_time<0 or source_offset<0 or source_offset>=value.length:return "Timing du personnage invalide."
	if duration<0 and loop:return "Indiquer une duree pour une animation en boucle."
	var root := animation_root(sequence)
	if not root or (root!=actor(sequence) and not actor(sequence).is_ancestor_of(root)):return "Le lecteur d'animation doit appartenir au personnage."
	for track in value.get_track_count():
		if value.track_get_type(track) not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE,Animation.TYPE_VALUE]:continue
		var path := value.track_get_path(track)
		var target := root.get_node_or_null(NodePath(path.get_concatenated_names()))
		if not target or (target!=actor(sequence) and not actor(sequence).is_ancestor_of(target)):return "Piste hors du personnage ou cible absente : "+String(path)
	return ""
