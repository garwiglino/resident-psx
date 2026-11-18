extends Node3D
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Routing=preload("res://scripts/audio/psx_audio_routing.gd")
signal effect_started(source: AudioStream)
signal effect_finished
var _audio: AudioStreamPlayer3D
var _pending := false
var _elapsed := 0.0
var _watchdog := 0.0
var _reply_delay := .03
var _source: Sequence
var _channel: WeakRef
var _required_id: StringName

func _ready() -> void:
	_audio=AudioStreamPlayer3D.new();_audio.name="Serrure";_audio.max_distance=8;_audio.max_polyphony=1;add_child(_audio)
	Routing.set_category(_audio,&"Interactions")
	_audio.finished.connect(_effect_finished);WorldEvents.run_reset.connect(cancel);set_process(false)

func _available(game: Node) -> bool:
	if not game or game.state!="playing" or get_tree().paused:return false
	var channel: Node=game.exploration_dialogue
	return is_instance_valid(channel) and not channel.suspended and not channel.is_active() and channel._queue.is_empty() and channel.reservation_owner()==null

func play_for(source: Sequence,cooldown: float,sounds: Array[AudioStream],volume_db: float,reply_delay := .03) -> bool:
	var door := get_parent();var game := WorldEvents.game_for(door)
	if _pending or not _available(game):return false
	var channel: Node=game.exploration_dialogue
	var pending: WeakRef=channel.get_meta(&"locked_door_pending") if channel.has_meta(&"locked_door_pending") else null
	if pending and pending.get_ref()!=null:return false
	var now := Time.get_ticks_msec()
	if now<int(channel.get_meta(&"locked_door_next_reply",0)):return false
	_source=source;_channel=weakref(channel);_required_id=door.required_item_id;_reply_delay=maxf(reply_delay,0)
	var variants: Array[AudioStream]=[]
	for sound in sounds:
		if sound:variants.append(sound)
	var last := int(channel.get_meta(&"locked_door_last_sound",0))
	if variants.size()>1:
		var alternatives := variants.filter(func(sound: AudioStream):return sound.get_instance_id()!=last)
		if not alternatives.is_empty():variants=alternatives
	_pending=true;channel.set_meta(&"locked_door_pending",weakref(self));channel.set_meta(&"locked_door_next_reply",now+roundi(cooldown*1000))
	if variants.is_empty():_effect_finished();return true
	var selected: AudioStream=variants[randi_range(0,variants.size()-1)]
	_audio.position=door.interaction_offset;_audio.volume_db=volume_db
	_audio.stream=get_node("/root/PSXAudio").prepare(selected).duplicate();_audio.stream.set("loop",false)
	channel.set_meta(&"locked_door_last_sound",selected.get_instance_id())
	_elapsed=0;_watchdog=_audio.stream.get_length()+.2;set_process(true)
	Routing.play(_audio);effect_started.emit(selected)
	if _reply_delay<=0:_send_reply()
	return true

func _process(delta: float) -> void:
	if not _pending:return
	var game := WorldEvents.game_for(self)
	if not game or game.state not in ["playing","dialogue","cinematic"]:cancel();return
	_elapsed+=delta
	if _source and _elapsed>=_reply_delay:_send_reply()
	# A rejected SPU voice must not leave the door waiting forever.
	if _elapsed>=_watchdog:_effect_finished()

func _effect_finished() -> void:
	if not _pending:return
	_pending=false;set_process(false);Routing.stop(_audio);_release_pending()
	effect_finished.emit();_send_reply()

func _send_reply() -> void:
	_play_reply();_source=null

func _play_reply() -> void:
	var door := get_parent();var game := WorldEvents.game_for(door)
	if not _source or not _available(game) or not door.locked or not door.can_interact() or door.required_item_id!=_required_id:return
	var inventory := get_node_or_null("/root/InventoryState")
	if not inventory or (not door.permanently_locked and not _required_id.is_empty() and inventory.has_item(_required_id)):return
	var channel: Node=game.exploration_dialogue
	var candidates: Array[Line]=[]
	for line in _source.lines:
		if line and not line.text.strip_edges().is_empty():candidates.append(line)
	if candidates.is_empty():return
	var last := int(channel.get_meta(&"locked_door_last_reply",0))
	if candidates.size()>1:
		var alternatives := candidates.filter(func(line: Line):return line.get_instance_id()!=last)
		if not alternatives.is_empty():candidates=alternatives
	var selected: Line=candidates[randi_range(0,candidates.size()-1)]
	# The authored sequence is a bank of alternatives, never a chain to play here.
	var sequence: Sequence=_source.duplicate(false);sequence.mode=Sequence.Mode.EXPLORATION_CALL;sequence.lines=[];sequence.lines.append(selected)
	if not game.play_dialogue(sequence,false):return
	channel.set_meta(&"locked_door_last_reply",selected.get_instance_id())

func _release_pending() -> void:
	var channel: Node=_channel.get_ref() if _channel else null
	if channel:
		var pending: WeakRef=channel.get_meta(&"locked_door_pending") if channel.has_meta(&"locked_door_pending") else null
		if pending and pending.get_ref()==self:channel.remove_meta(&"locked_door_pending")
	_channel=null

func cancel() -> void:
	_pending=false;_source=null;set_process(false);_release_pending()
	if is_instance_valid(_audio):Routing.stop(_audio)
func _exit_tree() -> void:cancel()
