extends Node
func _ready() -> void:call_deferred("_show_example")
func _show_example() -> void:
	var game := get_node("Level")
	game.play_dialogue(load("res://assets/dialogue/couloir_example.tres"))
