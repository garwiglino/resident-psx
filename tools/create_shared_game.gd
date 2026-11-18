extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	# Instantiation outside the tree preserves Player overrides without starting
	# old gameplay, sounds, enemies or the level renderer.
	var game: Node3D=load("res://scenes/main.tscn").instantiate()
	var map: Node=game.get_node("Map"); game.remove_child(map); map.free()
	game.name="SessionJeu"; game.scene_file_path=""; game.legacy_couloir_content=false
	var packed := PackedScene.new(); assert(packed.pack(game)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/systemes_jeu.tscn")==OK)
	game.free(); print("SHARED_GAME_CREATED"); quit()
