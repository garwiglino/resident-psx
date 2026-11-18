extends Node
## Run-scoped world facts. No objective UI; notifications and actions are queued.
signal state_changed(key: StringName,value: Variant)
signal event_raised(id: StringName,payload: Dictionary)
signal objective_completed(id: StringName)
signal run_reset
const Action=preload("res://scripts/world_events/world_action.gd")
const Dialogue=preload("res://scripts/dialogue/dialogue_controller.gd")
const AudioManager=preload("res://scripts/audio/level_audio_manager.gd")
const EventAudio=preload("res://scripts/audio/world_event_audio.gd")
var _facts: Dictionary={}
var _notifications: Array[Dictionary]=[]
var _jobs: Array[Dictionary]=[]
var _scheduled := false
var _flushing := false
var _generation := 0
var _next_job_id := 1

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE;set_process(false)
	var audio := EventAudio.new();audio.name="EventSounds";add_child(audio)
	event_raised.connect(audio.play_event)
	run_reset.connect(audio.stop)
func fact(key: StringName,fallback: Variant=false) -> Variant:return _facts.get(key,fallback)
func set_fact(key: StringName,value: Variant) -> bool:
	if key.is_empty() or typeof(value) not in [TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_STRING_NAME]:return false
	if _facts.has(key) and _facts[key]==value:return false
	_facts[key]=value;_notify({"key":key,"value":value});return true
func set_flag(id: StringName,value := true) -> bool:return set_fact(StringName("flag.%s" % id),value) if not id.is_empty() else false
func flag(id: StringName) -> bool:return bool(fact(StringName("flag.%s" % id)))
func count(id: StringName) -> int:return int(fact(StringName("counter.%s" % id),0))
func add_counter(id: StringName,amount := 1) -> void:
	if not id.is_empty():set_fact(StringName("counter.%s" % id),count(id)+amount)
func raise_event(id: StringName,payload: Dictionary={}) -> void:
	if id.is_empty():return
	var key := StringName("event.%s.count" % id)
	set_fact(key,int(fact(key,0))+1);_notify({"event":id,"payload":payload.duplicate(true)})
func door_open(id: StringName) -> bool:return bool(fact(StringName("door.%s.open" % id)))
func enemy_dead(id: StringName) -> bool:return bool(fact(StringName("enemy.%s.dead" % id)))
func objective_done(id: StringName) -> bool:return bool(fact(StringName("objective.%s.complete" % id)))
func interaction_used(id: StringName) -> bool:return bool(fact(StringName("interaction.%s.used" % id)))
func zone_visited(id: StringName) -> bool:return bool(fact(StringName("zone.%s.visited" % id)))
func set_door_open(id: StringName,opened: bool) -> bool:
	if id.is_empty() or not set_fact(StringName("door.%s.open" % id),opened):return false
	raise_event(StringName("door.%s.%s" % [id,"opened" if opened else "closed"]));return true
func mark_enemy_dead(id: StringName) -> bool:
	if id.is_empty() or enemy_dead(id):return false
	set_fact(StringName("enemy.%s.dead" % id),true);raise_event(StringName("enemy.%s.killed" % id));return true
func mark_interaction(id: StringName) -> void:
	if id.is_empty():return
	set_fact(StringName("interaction.%s.used" % id),true);raise_event(StringName("interaction.%s.used" % id))
func mark_zone(id: StringName) -> void:
	if id.is_empty():return
	set_fact(StringName("zone.%s.visited" % id),true);raise_event(StringName("zone.%s.entered" % id))
func complete_objective(id: StringName) -> bool:
	if id.is_empty() or objective_done(id):return false
	set_fact(StringName("objective.%s.complete" % id),true)
	_notify({"objective":id});raise_event(StringName("objective.%s.completed" % id));return true
func claim_once(id: StringName) -> bool:
	var key := StringName("once.%s" % id)
	if bool(fact(key)):return false
	set_fact(key,true);return true
func was_used(id: StringName) -> bool:return bool(fact(StringName("once.%s" % id)))
func reset_run() -> void:
	_generation+=1;_facts.clear();_notifications.clear();_jobs.clear();set_process(false);run_reset.emit()
func snapshot() -> Dictionary:
	var data := {"version":1,"facts":_facts.duplicate(true)}
	var inventory := get_node_or_null("/root/InventoryState")
	if inventory: data.inventory=inventory.snapshot()
	return data
func restore(data: Dictionary) -> bool:
	if int(data.get("version",0))!=1 or not data.get("facts") is Dictionary:return false
	var inventory := get_node_or_null("/root/InventoryState")
	if data.has("inventory") and (not data.inventory is Dictionary or (inventory and not inventory.validate_snapshot(data.inventory))): return false
	var restored: Dictionary={}
	for key in data.facts:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or typeof(data.facts[key]) not in [TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_STRING_NAME]:return false
		restored[StringName(key)]=data.facts[key]
	_generation+=1;_facts=restored;_notifications.clear();_jobs.clear();set_process(false);run_reset.emit()
	if inventory and data.get("inventory") is Dictionary: inventory.restore(data.inventory)
	_notify({"key":&"world.restored","value":true});return true
func _notify(item: Dictionary) -> void:
	if _notifications.size()>=4096:push_error("Boucle d'evenements du monde : file pleine.");return
	_notifications.append(item)
	if not _scheduled and not _flushing:_scheduled=true;call_deferred("_flush")
func _flush() -> void:
	_scheduled=false;_flushing=true;var generation := _generation
	for step in 256:
		if _notifications.is_empty() or generation!=_generation:break
		var item: Dictionary=_notifications.pop_front()
		if item.has("event"):event_raised.emit(item.event,item.payload)
		elif item.has("objective"):objective_completed.emit(item.objective)
		else:state_changed.emit(item.key,item.value)
	_flushing=false
	if not _notifications.is_empty() and not _scheduled:_scheduled=true;call_deferred("_flush_next_frame")
func _flush_next_frame() -> void:
	await get_tree().process_frame
	_flush()
static func stable_id(node: Node) -> StringName:
	var scene := node;var parent := node.get_parent()
	while parent:
		if not parent.scene_file_path.is_empty():scene=parent
		parent=parent.get_parent()
	return StringName("%s::%s" % [scene.scene_file_path,scene.get_path_to(node)])
static func game_for(node: Node) -> Node:
	var parent := node
	while parent:
		if parent.has_method("play_dialogue") and parent.has_method("play_cinematic"):return parent
		parent=parent.get_parent()
	return null
func execute(actions: Array,context: Node) -> bool:return start_job(actions,context)>=0
func start_job(actions: Array,context: Node,dialogue_owner: Node=null) -> int:
	if not is_instance_valid(context) or not context.is_inside_tree() or context.is_queued_for_deletion():return -1
	for action in actions:
		if not action:push_error("Action du monde vide sur "+str(context.get_path()));return -1
		var error: String=action.validation_error(context)
		if not error.is_empty():push_error(error+" "+str(context.get_path()));return -1
	if actions.is_empty():return 0
	if _jobs.size()>=256:push_error("Trop d'actions du monde en attente.");return -1
	var token := _next_job_id;_next_job_id+=1
	_jobs.append({"token":token,"context":weakref(context),"actions":actions.duplicate(),"index":0,"waiting":null,"owner":weakref(dialogue_owner) if dialogue_owner else null})
	set_process(true);return token
func job_active(token: int) -> bool:return token>0 and _jobs.any(func(job: Dictionary):return job.token==token)
func cancel_job(token: int) -> void:
	_jobs=_jobs.filter(func(job: Dictionary):return job.token!=token)
	set_process(not _jobs.is_empty())
func release_job_owner(token: int) -> void:
	for job in _jobs:
		if job.token==token:job.owner=null
func _process(_delta: float) -> void:
	# Each job retains authored order; unrelated state changes are never held by a conversation.
	for job in _jobs.duplicate():
		if not _jobs.has(job):continue
		var source: Node=job.context.get_ref()
		if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():_jobs.erase(job);continue
		if job.get("owner"):
			var owner: Node=job.owner.get_ref()
			if not is_instance_valid(owner) or not owner.is_inside_tree():_jobs.erase(job);continue
		var game := game_for(source)
		if game and game.state in ["dead","won"]:_jobs.erase(job);continue
		if job.waiting:
			var receiver: Node=job.waiting.get_ref()
			if is_instance_valid(receiver) and receiver.is_active():continue
			job.waiting=null
		for step in 32:
			if job.index>=job.actions.size():_jobs.erase(job);break
			var action: Resource=job.actions[job.index]
			var result := _step(action,source,game,job)
			if not _jobs.has(job):break
			if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():_jobs.erase(job);break
			if result==0:break
			if result<0:_jobs.erase(job);break
			job.index+=1
			if job.waiting:break
	set_process(not _jobs.is_empty())
func _step(action: Resource,source: Node,game: Node,job: Dictionary) -> int:
	match action.kind:
		Action.Kind.EMIT_EVENT:raise_event(action.id)
		Action.Kind.SET_FLAG:set_flag(action.id,action.value)
		Action.Kind.COMPLETE_OBJECTIVE:complete_objective(action.id)
		Action.Kind.ADD_COUNTER:add_counter(action.id,action.amount)
		Action.Kind.DIALOGUE:
			var owner: Node=job.owner.get_ref() if job.get("owner") else null
			var receiver: Node=owner.world_dialogue_controller(action.dialogue) if owner and owner.has_method("world_dialogue_controller") else Dialogue.find_for(source,action.dialogue)
			if not receiver:return 0
			if receiver.is_active() or receiver.suspended or (receiver.reservation_owner()!=null and receiver.reservation_owner()!=owner):return 0
			if not receiver.play(action.dialogue,false,owner):push_error("Dialogue d'evenement invalide.");return -1
			if owner and owner.has_method("world_dialogue_started"):owner.world_dialogue_started(receiver)
			if action.wait_for_completion:job.waiting=weakref(receiver)
		Action.Kind.CINEMATIC:
			if not game or not is_instance_valid(game.cinematics):return 0
			if game.cinematics.is_active() or game.dialogue.is_active() or game.dialogue.reservation_owner()!=null:return 0
			var target := source.get_node_or_null(action.cinematic_path)
			if not target or not game.play_cinematic(target):push_error("Cinematique d'evenement invalide.");return -1
			if action.wait_for_completion:job.waiting=weakref(game.cinematics)
		Action.Kind.TRIGGER_NODE:
			var target := source.get_node_or_null(action.trigger_path)
			if not target or not target.has_method("trigger"):return -1
			if target.trigger()==false:return 0
		Action.Kind.MECHANISM_STATE:
			var target := source.get_node_or_null(action.mechanism_path)
			var access: Node=target.get_mechanism_access() if target and target.has_method("get_mechanism_access") else null
			if not access:return -1
			var accepted: bool=access.request_open() if action.mechanism_operation==0 else (access.request_close() if action.mechanism_operation==1 else access.request_toggle())
			if not accepted:return -1
			if action.wait_for_completion and access.is_active():job.waiting=weakref(access)
		Action.Kind.AUDIO_CUE:
			var manager := AudioManager.find_for(source)
			if not manager:return 0
			if not manager.play_cue(action.id,source.global_position if source is Node3D else Vector3.ZERO):return -1
		Action.Kind.GIVE_ITEM:
			var inventory := get_node_or_null("/root/InventoryState")
			if not inventory or not inventory.give(action.inventory_item,action.amount): return 0
			if action.wait_for_completion and game and is_instance_valid(game.pickup_feedback) and game.pickup_feedback.is_active(): job.waiting=weakref(game.pickup_feedback)
		Action.Kind.REMOVE_ITEM:
			var inventory := get_node_or_null("/root/InventoryState")
			if not inventory or not inventory.remove_item(action.id,action.amount): return 0
		Action.Kind.COLLECT_CARD:
			var inventory := get_node_or_null("/root/InventoryState")
			if not inventory: return 0
			inventory.collect_card(action.id)
	return 1
