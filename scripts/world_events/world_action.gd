@tool
class_name WorldAction
extends Resource
enum Kind { EMIT_EVENT, SET_FLAG, COMPLETE_OBJECTIVE, ADD_COUNTER, DIALOGUE, CINEMATIC, TRIGGER_NODE, AUDIO_CUE, GIVE_ITEM, REMOVE_ITEM, COLLECT_CARD, MECHANISM_STATE }
@export_enum("Emettre un evenement","Modifier un drapeau","Accomplir un objectif","Ajouter au compteur","Jouer un dialogue","Jouer une cinematique","Declencher un noeud","Jouer un effet audio","Donner un objet","Retirer un objet","Trouver une carte de collection","Etat d'un mecanisme") var kind: int=Kind.EMIT_EVENT:
	set(value):kind=value;notify_property_list_changed();emit_changed()
@export var id: StringName
@export var value := true
@export var amount := 1
@export var inventory_item: Resource
@export var dialogue: DialogueSequence
## Chemin relatif au noeud qui porte cette action (Reaction, Objectif, Ennemi...).
@export_node_path("CinematicSequence3D") var cinematic_path: NodePath
## Le noeud cible doit posseder une methode trigger().
@export var trigger_path: NodePath
## Racine du mecanisme, ou composant MechanismAccess3D. Chemin relatif au porteur de l'action.
@export var mechanism_path: NodePath
@export_enum("Ouvrir","Fermer","Inverser") var mechanism_operation := 0
## Une action suivante attend la fin du dialogue ou de la cinematique.
@export var wait_for_completion := true

func validation_error(context: Node) -> String:
	if kind<0 or kind>Kind.MECHANISM_STATE:return "Type d'action inconnu."
	if kind in [Kind.EMIT_EVENT,Kind.SET_FLAG,Kind.COMPLETE_OBJECTIVE,Kind.ADD_COUNTER,Kind.AUDIO_CUE] and id.is_empty():return "Identifiant d'action manquant."
	if kind==Kind.DIALOGUE and (not dialogue or dialogue.lines.is_empty()):return "Dialogue manquant ou sans replique."
	if kind==Kind.CINEMATIC and (cinematic_path.is_empty() or not context.get_node_or_null(cinematic_path) is CinematicSequence3D):return "Chemin de cinematique invalide."
	if kind==Kind.TRIGGER_NODE:
		var target := context.get_node_or_null(trigger_path) if not trigger_path.is_empty() else null
		if not target or not target.has_method("trigger"):return "Le noeud cible doit proposer trigger()."
	if kind==Kind.MECHANISM_STATE:
		var target := context.get_node_or_null(mechanism_path) if not mechanism_path.is_empty() else null
		if not target or not target.has_method("get_mechanism_access") or not target.has_method("access_configuration_error"):return "Mechanism Path doit viser la racine d'un mecanisme."
		if mechanism_operation<0 or mechanism_operation>2:return "Commande de mecanisme inconnue."
		var error: String=target.access_configuration_error()
		if not error.is_empty():return error
		var settings: Resource=target.get("access_settings") if "access_settings" in target else target.get("settings")
		if not settings or not settings.enabled:return "Activer Enabled dans les reglages d'ouverture du mecanisme."
	if kind in [Kind.REMOVE_ITEM,Kind.COLLECT_CARD] and id.is_empty(): return "Identifiant d'objet/carte manquant."
	if kind==Kind.GIVE_ITEM and (not inventory_item or not inventory_item.has_method("maximum_stack")): return "Choisir une InventoryItemDefinition."
	if kind in [Kind.GIVE_ITEM,Kind.REMOVE_ITEM] and amount<=0: return "Quantite d'objet invalide."
	return ""
func _validate_property(property: Dictionary) -> void:
	var visible: Dictionary={"id":kind in [0,1,2,3,7,9,10],"value":kind==1,"amount":kind in [3,8,9],"inventory_item":kind==8,"dialogue":kind==4,"cinematic_path":kind==5,"trigger_path":kind==6,"mechanism_path":kind==11,"mechanism_operation":kind==11,"wait_for_completion":kind in [4,5,8,11]}
	if property.name=="inventory_item": property.hint=PROPERTY_HINT_RESOURCE_TYPE; property.hint_string="InventoryItemDefinition"
	if visible.has(property.name) and not visible[property.name]:property.usage&=~PROPERTY_USAGE_EDITOR
