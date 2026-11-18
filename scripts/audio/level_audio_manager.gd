@tool
class_name LevelAudioManager
extends Node
const AudioRouting=preload("res://scripts/audio/psx_audio_routing.gd")
const Profile=preload("res://scripts/audio/level_audio_profile.gd")
const Layer=preload("res://scripts/audio/ambience_layer.gd")
const Cue=preload("res://scripts/audio/audio_cue.gd")
const MAX_LAYERS := 3
const AMBIENCE_VOICES := 8
const EFFECT_VOICES := 4
enum CombatMode { AUTOMATIC, CALM, COMBAT }
signal combat_changed(active: bool)
signal ambience_changed(zone: Node)
signal cue_played(id: StringName,position: Vector3)
@export var profile: Profile
@export var autoplay := true
@export_group("Volumes")
@export_range(-60.0,0.0,.5,"suffix:dB") var ambience_volume_db := 0.0
@export_range(-60.0,0.0,.5,"suffix:dB") var music_volume_db := 0.0
@export_range(-60.0,0.0,.5,"suffix:dB") var effects_volume_db := 0.0
@export_group("Combat")
@export_enum("Automatique","Calme force","Combat force") var combat_mode: int=CombatMode.AUTOMATIC
@export_range(1.0,50.0,.5,"suffix:m") var combat_enter_distance := 10.0
@export_range(1.0,80.0,.5,"suffix:m") var combat_exit_distance := 14.0
var in_combat := false
var active_zone: Node
var _running := false
var _threat := false
var _combat_left := 0.0
var _zones: Array[Node]=[]
var _ambience: Array[Dictionary]=[]
var _ambience_time := 0.0
var _ambience_duration := 1.5
var _music: Array[AudioStreamPlayer]=[]
var _music_gain: Array[float]=[0.0,0.0]
var _music_from: Array[float]=[0.0,0.0]
var _music_target: Array[float]=[0.0,0.0]
var _music_time := 0.0
var _global_effects: Array[AudioStreamPlayer]=[]
var _spatial_effects: Array[AudioStreamPlayer3D]=[]
var _prepared: Dictionary={}
var _cooldowns: Dictionary={}
var _last_variants: Dictionary={}
var _duck_requests: Array[Dictionary]=[]
var _duck_db := 0.0

func _enter_tree() -> void:add_to_group("level_audio_managers")

func _ready() -> void:
	if Engine.is_editor_hint():set_process(false);return
	process_mode=Node.PROCESS_MODE_PAUSABLE
	for index in AMBIENCE_VOICES:
		var player := AudioStreamPlayer.new();player.name="Ambience%d" % index;add_child(player)
		AudioRouting.set_category(player,&"Ambience")
		_ambience.append({"player":player,"source":null,"gain":0.0,"from":0.0,"target":0.0})
	for index in 2:
		var player := AudioStreamPlayer.new();player.name="Exploration" if index==0 else "Combat"
		AudioRouting.set_category(player,&"Music")
		add_child(player);_music.append(player)
	for index in EFFECT_VOICES:
		var global := AudioStreamPlayer.new();global.name="Effect%d" % index
		AudioRouting.set_category(global,&"Stingers")
		add_child(global);_global_effects.append(global)
		var spatial := AudioStreamPlayer3D.new();spatial.name="SpatialEffect%d" % index
		AudioRouting.set_category(spatial,&"Stingers")
		add_child(spatial);_spatial_effects.append(spatial)
	if autoplay:start_level()

## Les zones trouvent le gestionnaire du niveau le plus proche, pas celui d'une autre carte.
static func find_for(node: Node,path: NodePath=NodePath()) -> Node:
	if not path.is_empty():return node.get_node_or_null(path)
	var managers := node.get_tree().get_nodes_in_group("level_audio_managers")
	var ancestor: Node=node
	while ancestor:
		for manager in managers:
			if ancestor==manager or ancestor.is_ancestor_of(manager):return manager
		ancestor=ancestor.get_parent()
	return null

func _prepare(source: AudioStream,looping: bool) -> AudioStream:
	if not source:return null
	var key := str(source.get_instance_id())+":"+str(looping)
	if _prepared.has(key):return _prepared[key]
	var stream: AudioStream=get_node("/root/PSXAudio").prepare(source).duplicate()
	# La boucle est propre au lecteur ; le fichier importe et les autres effets restent intacts.
	if stream.is_class("AudioStreamPSX"):stream.set("loop",looping)
	elif stream is AudioStreamWAV:
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
		if looping and stream.loop_end<=stream.loop_begin:stream.loop_end=int(stream.get_length()*stream.mix_rate)
	_prepared[key]=stream
	return stream

func prepare_ambience(layers: Array) -> void:
	var count := 0
	for layer in layers:
		if layer and layer.stream:
			_prepare(layer.stream,true);count+=1
			if count>=MAX_LAYERS:break

func prepare_effect(cue: Cue) -> void:
	if cue:
		for source in cue.variants:_prepare(source,false)

func start_level() -> void:
	if Engine.is_editor_hint() or _running or not profile:return
	_running=true;_threat=false;_combat_left=0;in_combat=false
	_music[0].stream=_prepare(profile.exploration_music,true)
	_music[1].stream=_prepare(profile.combat_music,true)
	for cue in profile.cues:prepare_effect(cue)
	_set_ambience(profile.ambience_layers,profile.crossfade_seconds)
	_refresh_zone(true);_select_music()

func stop_level() -> void:
	_running=false;_threat=false;_combat_left=0
	for slot in _ambience:
		AudioRouting.stop(slot.player);slot.source=null;slot.gain=0.0;slot.from=0.0;slot.target=0.0
	for player in _music:AudioRouting.stop(player)
	for player in _global_effects:AudioRouting.stop(player)
	for player in _spatial_effects:AudioRouting.stop(player)
	_music_gain=[0.0,0.0];_music_from=[0.0,0.0];_music_target=[0.0,0.0]
	_duck_requests.clear();_duck_db=0;_cooldowns.clear();_last_variants.clear()
	if in_combat:in_combat=false;combat_changed.emit(false)

func report_combat(threat: bool) -> void:_threat=threat

func enter_zone(zone: Node) -> void:
	if zone not in _zones:_zones.append(zone)
	_refresh_zone()

func leave_zone(zone: Node) -> void:
	_zones.erase(zone);_refresh_zone()

func _refresh_zone(force := false) -> void:
	var chosen: Node
	for index in range(_zones.size()-1,-1,-1):
		var zone := _zones[index]
		if not is_instance_valid(zone):_zones.remove_at(index);continue
		if zone.enabled and (not chosen or zone.audio_priority>chosen.audio_priority):chosen=zone
	if chosen==active_zone and not force:return
	var fade: float=chosen.transition_seconds if chosen else (active_zone.transition_seconds if is_instance_valid(active_zone) else profile.crossfade_seconds if profile else 1.5)
	active_zone=chosen
	if _running:
		_set_ambience(chosen.ambience_layers if chosen else profile.ambience_layers,fade)
		ambience_changed.emit(chosen)

func _set_ambience(layers: Array,duration: float) -> void:
	var desired: Dictionary={}
	for layer in layers:
		if layer and layer.stream and not desired.has(layer.stream):
			if desired.size()==MAX_LAYERS:break
			desired[layer.stream]=db_to_linear(layer.volume_db)
	for slot in _ambience:slot.target=desired.get(slot.source,0.0)
	for source in desired:
		var found := false
		for slot in _ambience:
			if slot.source==source:found=true;break
		if found:continue
		var available: Dictionary={}
		for slot in _ambience:
			if slot.source==null or slot.gain<=.00001:available=slot;break
		# Une rafale de zones garde une limite de voix ; seule la sortie la plus faible est remplacee.
		if available.is_empty():
			for slot in _ambience:
				if slot.target==0 and (available.is_empty() or slot.gain<available.gain):available=slot
		if available.is_empty():continue
		AudioRouting.stop(available.player);available.source=source;available.gain=0.0
		available.target=desired[source];available.player.volume_db=-80
		available.player.stream=_prepare(source,true);AudioRouting.play(available.player)
	for slot in _ambience:slot.from=slot.gain
	_ambience_time=0;_ambience_duration=maxf(duration,0)

func _select_music() -> void:
	var index := 1 if in_combat and profile.combat_music and profile.combat_music!=profile.exploration_music else 0
	var target: Array[float]=[0.0,0.0]
	if _music[index].stream:target[index]=1.0
	if target==_music_target:return
	_music_from=_music_gain.duplicate();_music_target=target;_music_time=0
	if target[index]>0 and not _music[index].playing:
		_music[index].volume_db=-80;AudioRouting.play(_music[index])

func play_cue(id: StringName,position := Vector3.ZERO) -> bool:
	if not profile:return false
	for cue in profile.cues:
		if cue and cue.id==id:return play_effect(cue,position)
	return false

func play_effect(cue: Cue,position := Vector3.ZERO) -> bool:
	if not _running or get_tree().paused or not cue:return false
	var key := cue.get_instance_id()
	if _cooldowns.get(key,0.0)>0:return false
	var variants: Array[AudioStream]=[]
	for source in cue.variants:
		if source:variants.append(source)
	if variants.is_empty():return false
	var player: Node
	var voices: Array=_spatial_effects if cue.spatial else _global_effects
	for voice in voices:
		if not voice.playing:player=voice;break
	if not player:return false
	var last: int=_last_variants.get(key,-1)
	var choice := randi_range(0,variants.size()-1)
	if variants.size()>1 and last>=0:
		choice=randi_range(0,variants.size()-2)
		if choice>=last:choice+=1
	player.stream=_prepare(variants[choice],false)
	AudioRouting.set_category(player,StringName(cue.audio_category))
	player.volume_db=cue.volume_db+effects_volume_db
	if player is AudioStreamPlayer3D:
		player.global_position=position;player.max_distance=cue.max_distance
	AudioRouting.play(player);_last_variants[key]=choice;_cooldowns[key]=cue.cooldown_seconds
	if cue.music_duck_db<0 and cue.duck_seconds>0:_duck_requests.append({"time":cue.duck_seconds,"db":cue.music_duck_db})
	cue_played.emit(cue.id,position)
	return true

func _process(delta: float) -> void:
	if not _running:return
	_refresh_zone()
	_combat_left=profile.combat_release_delay if _threat else maxf(_combat_left-delta,0)
	var combat := (_threat or _combat_left>0) if combat_mode==CombatMode.AUTOMATIC else combat_mode==CombatMode.COMBAT
	if combat!=in_combat:in_combat=combat;_select_music();combat_changed.emit(combat)
	for key in _cooldowns.keys():
		_cooldowns[key]=maxf(_cooldowns[key]-delta,0)
		if _cooldowns[key]<=0:_cooldowns.erase(key)
	var duck := 0.0
	for index in range(_duck_requests.size()-1,-1,-1):
		_duck_requests[index].time-=delta
		if _duck_requests[index].time<=0:_duck_requests.remove_at(index)
		else:duck=minf(duck,_duck_requests[index].db)
	_duck_db=lerpf(_duck_db,duck,1-exp(-delta/(.06 if duck<_duck_db else .4)))
	_ambience_time+=delta
	var t := smoothstep(0.0,1.0,minf(_ambience_time/_ambience_duration,1.0)) if _ambience_duration>0 else 1.0
	for slot in _ambience:
		# Fondu a puissance constante : evite le creux au milieu de deux ambiances.
		slot.gain=sqrt(lerpf(slot.from*slot.from,slot.target*slot.target,t))
		slot.player.volume_db=linear_to_db(maxf(slot.gain,.0001))+ambience_volume_db
		if slot.target==0 and t>=1 and slot.source!=null:AudioRouting.stop(slot.player);slot.source=null
	_music_time+=delta
	t=smoothstep(0.0,1.0,minf(_music_time/profile.crossfade_seconds,1.0)) if profile.crossfade_seconds>0 else 1.0
	for index in 2:
		_music_gain[index]=sqrt(lerpf(_music_from[index]*_music_from[index],_music_target[index]*_music_target[index],t))
		var db: float=profile.exploration_volume_db if index==0 else profile.combat_volume_db
		_music[index].volume_db=db+music_volume_db+_duck_db+linear_to_db(maxf(_music_gain[index],.0001))
		if _music_target[index]==0 and t>=1:AudioRouting.stop(_music[index])
