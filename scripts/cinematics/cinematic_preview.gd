extends Node
func _ready() -> void:
	var game := get_node("Level")
	var example := game.get_node("Example")
	example.position=game.player.position-Vector3(0,.05,6.2)
	game.get_node("Trigger").position=game.player.position
