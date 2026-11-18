@tool
extends Resource
const Item=preload("res://scripts/inventory/item_definition.gd")
const Card=preload("res://scripts/inventory/card_definition.gd")
@export var items: Array[Item]=[]
@export var cards: Array[Card]=[]
@export var card_back: Texture2D
@export var card_mystery: Texture2D
@export_range(4,64,1) var item_capacity := 16
@export_range(4,64,1) var equipment_capacity := 16
func item(id: StringName) -> Resource:
	for value in items:
		if value and value.id==id: return value
	return null
func card(id: StringName) -> Resource:
	for value in cards:
		if value and value.id==id: return value
	return null
