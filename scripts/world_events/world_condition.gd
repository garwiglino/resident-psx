@tool
class_name WorldCondition
extends Resource
enum Kind { FLAG, DOOR_OPEN, ENEMY_DEAD, OBJECTIVE_COMPLETE, INTERACTION_USED, ZONE_VISITED, EVENT_COUNT, COUNTER, HAS_ITEM, CARD_COLLECTED, DOCUMENT_READ, MECHANISM_OPEN }
@export_enum("Drapeau","Porte ouverte","Ennemi mort","Objectif accompli","Interaction effectuee","Zone atteinte","Evenement recu","Compteur","Objet dans l'inventaire","Carte de collection trouvee","Document lu","Mecanisme ouvert") var kind: int=Kind.FLAG:
	set(value):kind=value;notify_property_list_changed();emit_changed()
@export var id: StringName
@export var expected := true
@export_range(1,100000,1) var minimum_count := 1

func key() -> StringName:
	var formats := ["flag.%s","door.%s.open","enemy.%s.dead","objective.%s.complete","interaction.%s.used","zone.%s.visited","event.%s.count","counter.%s","inventory.%s.count","collection.%s.owned","document.%s.read","mechanism.%s.open"]
	return StringName(formats[clampi(kind,0,11)] % id)
func matches() -> bool:
	if id.is_empty():return false
	var numeric: bool=kind in [Kind.EVENT_COUNT,Kind.COUNTER,Kind.HAS_ITEM]
	var value: Variant=WorldEvents.fact(key(),0 if numeric else false)
	return int(value)>=minimum_count if numeric else bool(value)==expected
func _validate_property(property: Dictionary) -> void:
	if property.name=="expected" and kind in [Kind.EVENT_COUNT,Kind.COUNTER,Kind.HAS_ITEM]:property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="minimum_count" and kind not in [Kind.EVENT_COUNT,Kind.COUNTER,Kind.HAS_ITEM]:property.usage&=~PROPERTY_USAGE_EDITOR

static func all_match(conditions: Array,require_all := true) -> bool:
	for condition in conditions:
		var matched: bool=condition!=null and condition.matches()
		if require_all and not matched:return false
		if not require_all and matched:return true
	return require_all
