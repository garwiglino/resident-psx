extends Node
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
@export var mix_profile: Resource=preload("res://assets/audio/mixage.tres")
## Applies the SPU source path to existing and dynamically added audio players.
## Newly imported files already contain their ADPCM data and need no conversion.
var _players: Array[WeakRef]=[]
var _cache: Dictionary={}
var _mix_signature: Dictionary={}

func _exit_tree() -> void:
	_players.clear(); _cache.clear(); Routing.release_cached_effects()
	for path: String in ["res://scripts/dialogue/intercom_filter.gd","res://scripts/face_texture_pages.gd"]:
		if ResourceLoader.has_cached(path): load(path).clear_cache()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_priority=1000000
	if not ClassDB.class_exists("AudioStreamPSX"):
		push_error("Audio PS1 indisponible : redemarrer Godot pour charger la bibliotheque native du projet.")
		set_process(false)
		return
	if not Routing.setup():
		# An already open v11 editor keeps its previous audio until restart.
		var effect=ClassDB.instantiate("AudioEffectPSXReverb")
		AudioServer.add_bus_effect(0,effect)
	_apply_mix()
	get_tree().node_added.connect(_track_player)
	_scan(get_tree().root)

func _scan(node: Node) -> void:
	_track_player(node)
	for child in node.get_children():_scan(child)

func _track_player(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		_players.append(weakref(node))
		_prepare_player(node)

func _apply_mix() -> void:
	if mix_profile and _mix_signature!=mix_profile.volumes():
		_mix_signature=mix_profile.volumes();mix_profile.apply()

func prepare(source: AudioStream) -> AudioStream:
	if not source or source.is_class("AudioStreamPSX"):return source
	var key := source.get_instance_id()
	if _cache.has(key):return _cache[key]
	var converted=ClassDB.instantiate("AudioStreamPSX")
	if not converted.configure_source(source,22050):
		# Procedural/infinite streams cannot be baked. Their output still passes
		# through the common SPU reverb and signed 16-bit output stage.
		return source
	converted.resource_name=source.resource_name if not source.resource_name.is_empty() else source.resource_path.get_file()
	converted.set_meta("psx_source_path",source.resource_path)
	converted.set_meta("psx_category",Routing.Categories.for_path(source.resource_path))
	_cache[key]=converted
	return converted

func _prepare_player(player: Node) -> void:
	# Scene swaps briefly detach valid players from their viewport.
	if not player.is_inside_tree() or player.is_queued_for_deletion(): return
	Routing.route(player)
	var source: AudioStream=player.stream
	if not source:return
	if source.is_class("AudioStreamPSX"):Routing.sync_player(player);return
	var converted := prepare(source)
	if converted==source:return
	var resume: bool=player.playing
	var position: float=player.get_playback_position() if resume else 0.0
	player.stream=converted
	Routing.sync_player(player)
	if resume:player.play(position)

func _process(_delta: float) -> void:
	_apply_mix()
	for index in range(_players.size()-1,-1,-1):
		var player=_players[index].get_ref()
		if not player:_players.remove_at(index)
		else:_prepare_player(player)
