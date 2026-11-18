@tool
class_name InventoryItemDefinition
extends Resource
const Weapon=preload("res://scripts/weapon_definition.gd")
enum Kind { CONSUMABLE, QUEST, MECHANISM, DOCUMENT, KEY, ACCESS_CARD, WEAPON, AMMO, TOOL, MATERIAL, OTHER }
enum Section { ITEMS, EQUIPMENT }
@export var id: StringName
@export var display_name := "Objet"
@export_multiline var description := ""
@export var kind: Kind=Kind.OTHER:
	set(value): kind=value; notify_property_list_changed()
@export var icon: Texture2D
@export var icon_tint := Color.WHITE
@export_range(1,999,1) var stack_limit := 1
@export var essential := false
@export var allow_discard := true
@export_group("Utilisation")
@export_range(0,1000,1) var healing := 0
@export var consumed_on_use := true
@export var custom_action_label := ""
@export var use_actions: Array[WorldAction]=[]
@export_group("Document")
@export_multiline var document_text := ""
@export_group("Arme et munitions")
@export var weapon: Weapon
@export var ammo_type: StringName
@export_group("Objet dans le niveau")
@export var world_model: PackedScene
## Optional dedicated model for the rotating discovery preview.
@export var inspection_model: PackedScene
@export_group("Placement sur un mecanisme")
## Les mecanismes sont placables automatiquement. Cocher pour les outils,
## objets de quete ou autres pieces a proposer dans le choix d'installation.
@export var placeable := false

func can_place() -> bool:return kind==Kind.MECHANISM or placeable

func is_essential() -> bool: return essential or kind in [Kind.QUEST,Kind.KEY,Kind.ACCESS_CARD,Kind.MECHANISM]
func section() -> StringName: return &"equipment" if kind in [Kind.WEAPON,Kind.AMMO] else &"items"
func maximum_stack() -> int:
	return 1 if kind in [Kind.KEY,Kind.ACCESS_CARD,Kind.WEAPON,Kind.DOCUMENT,Kind.QUEST] else maxi(stack_limit,1)
func can_discard() -> bool:
	return allow_discard and not is_essential()
func action_label() -> String:
	if not custom_action_label.is_empty(): return custom_action_label
	match kind:
		Kind.CONSUMABLE: return "CONSOMMER"
		Kind.WEAPON: return "EQUIPER"
		Kind.DOCUMENT: return "LIRE"
		Kind.AMMO,Kind.MATERIAL: return ""
	return "UTILISER"
func _validate_property(property: Dictionary) -> void:
	if property.name=="stack_limit" and maximum_stack()==1 and kind in [Kind.KEY,Kind.ACCESS_CARD,Kind.WEAPON,Kind.DOCUMENT,Kind.QUEST]: property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="document_text" and kind!=Kind.DOCUMENT: property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="weapon" and kind!=Kind.WEAPON: property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="ammo_type" and kind!=Kind.AMMO: property.usage&=~PROPERTY_USAGE_EDITOR
	if property.name=="healing" and kind!=Kind.CONSUMABLE: property.usage&=~PROPERTY_USAGE_EDITOR
