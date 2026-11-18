@tool
class_name PSXLevelSettings
extends "res://scripts/audio/level_audio_manager.gd"
## One level module: PSX atmosphere and the existing SPU ambience/music manager.
## Rendering, player and game systems belong to the shared game session.
signal render_changed
const AnimeStyle=preload("res://scripts/psx_anime_style.gd")
## Profil commun a tous les niveaux. Rendre unique pour un style propre a cette carte.
@export_group("Style anime PSX")
@export var anime_style: AnimeStyle=preload("res://assets/rendering/anime_psx.tres"):
	set(value):anime_style=value;render_changed.emit()
@export_group("Fog PSX")
@export var fog_enabled := true:
	set(value): fog_enabled=value; render_changed.emit()
@export_range(0,100,.1,"suffix:m") var fog_start := 9.0:
	set(value): fog_start=value; render_changed.emit(); _warnings()
@export_range(.1,100,.1,"suffix:m") var fog_end := 33.0:
	set(value): fog_end=value; render_changed.emit(); _warnings()
@export var fog_color := Color(.027,.044,.046):
	set(value): fog_color=value; render_changed.emit()
@export_range(10,100,1,"suffix:m") var draw_distance := 42.0:
	set(value): draw_distance=value; render_changed.emit()
@export_group("Couleurs et eclairage PSX")
## Palette tint, before the PSX RGB555 conversion. No screen filter.
@export var color_tint := Color.WHITE:
	set(value): color_tint=value; render_changed.emit()
## 0 = grey palettes and lighting, 1 = original colours.
@export_range(0,2,.01) var saturation := 1.0:
	set(value): saturation=value; render_changed.emit()
@export_range(0,2,.01) var brightness := 1.0:
	set(value): brightness=value; render_changed.emit()
## Black keeps unlit parts dark. Place PSXLight3D nodes in this level.
@export var ambient_light_color := Color.BLACK:
	set(value): ambient_light_color=value; render_changed.emit()

func _enter_tree() -> void:
	super._enter_tree(); add_to_group("psx_level_settings")

func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		var session := get_node_or_null("/root/LevelRuntime")
		if session: session.request_current_scene()

func render_overrides() -> Dictionary:
	return {"fog_enabled":fog_enabled,"fog_start":fog_start,"fog_end":fog_end,"fog_color":fog_color,
		"draw_distance":draw_distance,"ambient_light_color":ambient_light_color,
		"color_tint":color_tint,"saturation":saturation,"brightness":brightness,"anime_style":anime_style}

func _warnings() -> void:
	if is_inside_tree(): update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var result := PackedStringArray()
	if fog_enabled and fog_end<=fog_start: result.append("Fog End doit etre plus grand que Fog Start.")
	return result

static func find_in(root: Node) -> Node:
	if not is_instance_valid(root): return null
	if root is PSXLevelSettings: return root
	if root.is_inside_tree():
		for candidate in root.get_tree().get_nodes_in_group("psx_level_settings"):
			if root.is_ancestor_of(candidate): return candidate
	else:
		for child in root.get_children():
			if child.name==&"Construction": continue
			var found := find_in(child)
			if found: return found
	return null
