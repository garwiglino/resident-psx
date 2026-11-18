extends Node
## Project-wide entry point. F6 on a level starts the one shared game session.
const Settings = preload("res://scripts/levels/psx_level_settings.gd")
const SESSION := "res://scenes/systemes_jeu.tscn"
var _pending := false
var _launching := false

func request_current_scene() -> void:
	if Engine.is_editor_hint() or _pending or _launching: return
	_pending=true; call_deferred("_launch_current")

func _launch_current() -> void:
	_pending=false
	var level := get_tree().current_scene
	if not is_instance_valid(level) or not level is Node3D: return
	# A game session such as main already owns the common systems.
	if level.has_method("play_cinematic"): return
	if not Settings.find_in(level) and not level.has_method("apply_plan"): return
	_launching=true
	var source_path := level.scene_file_path
	var transform: Transform3D=level.global_transform
	for manager in get_tree().get_nodes_in_group("level_audio_managers"):
		if level.is_ancestor_of(manager): manager.stop_level()
	var game: Node3D=load(SESSION).instantiate()
	game.name="SessionJeu"; game.scene_file_path=source_path
	game.set_meta("standalone_level",true)
	get_tree().current_scene=null
	get_tree().root.remove_child(level)
	level.name="Map"; game.add_child(level); level.transform=transform
	_ensure_spawn(level)
	get_tree().root.add_child(game)
	get_tree().current_scene=game
	_launching=false

func _ensure_spawn(level: Node3D) -> void:
	if level.has_node("Gameplay/PlayerSpawn"): return
	var gameplay := level.get_node_or_null("Gameplay")
	if not gameplay:
		gameplay=Node3D.new(); gameplay.name="Gameplay"; level.add_child(gameplay)
	var marker := Marker3D.new(); marker.name="PlayerSpawn"; marker.position=Vector3(1,.05,1)
	if level.has_method("apply_plan") and level.layout:
		var first: Dictionary=level.layout.first_floor()
		if not first.is_empty():
			var cell: Vector2i=first.cell
			marker.position=Vector3(cell.x*2+1,int(first.level)*3+.05,cell.y*2+1)
	gameplay.add_child(marker)

func configure_game(game: Node3D) -> void:
	var settings := Settings.find_in(game.level)
	if not settings: return
	var renderer := game.get_node("PSXRenderer")
	_apply_settings(renderer,settings)
	settings.render_changed.connect(_apply_settings.bind(renderer,settings))

func _apply_settings(renderer: Node, settings: Node) -> void:
	if not is_instance_valid(renderer) or not is_instance_valid(settings): return
	for property: String in settings.render_overrides(): renderer.set(property,settings.get(property))
