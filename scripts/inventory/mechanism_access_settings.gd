@tool
class_name MechanismAccessSettings
extends Resource
enum ClosePolicy { LEAVE_OPEN, ON_EXIT, WHEN_COMPLETE, WORLD_EVENT }
@export var enabled := false
@export var initially_open := false
## Ouvrir a l'interaction si le mecanisme est ferme. Une ouverture deja faite n'est pas rejouee.
@export var open_on_interaction := true
@export_enum("Laisser ouvert","Fermer a chaque sortie","Fermer quand tout est installe","Uniquement par evenement ou action") var close_policy: int=ClosePolicy.WHEN_COMPLETE
@export_group("Animations du mecanisme")
## Chemin relatif a la racine du mecanisme, pas a cette ressource.
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export var opening_animation: StringName
## Vide : lire l'ouverture a l'envers. Sans aucun clip, seul l'etat logique change.
@export var closing_animation: StringName
@export_range(.05,5,.05) var playback_speed := 1.0
@export_group("Limite de l'animation - facultatif")
## Noeud anime ou Skeleton3D. Vide : garder les pistes qui varient entre les poses, pour proteger les autres parties du rig.
@export_node_path("Node3D") var animated_root_path: NodePath
## Si le noeud choisi est un Skeleton3D : noms des os a animer, avec leurs descendants.
@export var bone_names := PackedStringArray()
@export_group("Commandes du monde")
## Ces evenements demandent l'ouverture ou la fermeture. Les actions Etat d'un mecanisme proposent la meme commande.
@export var open_event: StringName
@export var close_event: StringName
func _init() -> void:resource_local_to_scene=true
func validation_error(context: Node) -> String:
	if not enabled:return ""
	if close_policy<0 or close_policy>ClosePolicy.WORLD_EVENT:return "Regle de fermeture inconnue."
	if not is_finite(playback_speed) or playback_speed<=0:return "Vitesse d'ouverture/fermeture invalide."
	var player := context.get_node_or_null(animation_player_path) as AnimationPlayer if not animation_player_path.is_empty() else null
	if (not opening_animation.is_empty() or not closing_animation.is_empty()) and not player:return "Choisir l'Animation Player du mecanisme pour l'ouverture/fermeture."
	for clip in [opening_animation,closing_animation]:
		if not clip.is_empty() and not player.has_animation(clip):return "Animation du mecanisme introuvable : "+String(clip)
	var animated := context.get_node_or_null(animated_root_path) as Node3D if not animated_root_path.is_empty() else null
	if not animated_root_path.is_empty() and not animated:return "Noeud anime du mecanisme introuvable."
	if not bone_names.is_empty():
		if not animated is Skeleton3D:return "Choisir un Skeleton3D avant de renseigner les os du couvercle."
		for bone in bone_names:
			if animated.find_bone(bone)<0:return "Os d'ouverture/fermeture introuvable : "+bone
	if not open_event.is_empty() and open_event==close_event:return "Les evenements d'ouverture et de fermeture doivent etre differents."
	return ""
