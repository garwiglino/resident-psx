extends SceneTree
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
var Door: Script
const Item=preload("res://scripts/inventory/item_definition.gd")
const SOURCE="res://assets/audio/dialogs/locked_doors_key/locked_doors_key.tres"
const PERMANENT_SOURCE="res://assets/audio/dialogs/locked_doors/locked_doors.tres"
var failures: Array[String]=[]
var game: Node
var inventory: Node
var channel: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(frames := 5) -> void:
	for frame in frames:await process_frame
func make_door(id: StringName,required: StringName,source: Resource) -> Node:
	var door: Node=Door.new();var silent: Array[AudioStream]=[];door.door_id=id;door.initially_locked=true;door.required_item_id=required;door.locked_dialogue_pool=source;door.locked_sounds=silent;door.duration=0;game.level.add_child(door);return door
func reset_reply() -> void:
	channel.cancel();channel.set_meta(&"locked_door_next_reply",0)
func run() -> void:
	Door=load("res://scripts/world_events/world_door_3d.gd")
	var source_hash := FileAccess.get_sha256(SOURCE)
	var permanent_hash := FileAccess.get_sha256(PERMANENT_SOURCE)
	inventory=root.get_node("InventoryState");inventory.persist_collection=false
	var map: Node=load("res://scenes/examples/inventory_demo.tscn").instantiate();root.add_child(map);current_scene=map;await settle(20);game=current_scene
	game.pickup_feedback.enabled=false;game.player.set_physics_process(false);game.psx_renderer.set_process(false);channel=game.exploration_dialogue
	check(game.level.locked_door_dialogues.resource_path==SOURCE,"New maps and the inventory example use the artist's existing locked_doors_key sequence")
	var source := Sequence.new();source.id=&"test_locked_doors_key";source.reply_gap=0;source.minimum_page_seconds=.5;source.reading_characters_per_second=80
	for text in ["Test un.","Test deux.","Test trois."]:
		var line := Line.new();line.speaker="HITOMI";line.text=text;source.lines.append(line)
	var door := make_door(&"test.locked.key",&"key_archives",source)
	check(not door.interact(game.player) and door.locked and not door.is_open,"Missing matching key refuses to unlock the door")
	check(channel.is_active() and channel.current_sequence.lines.size()==1 and channel.current_line.text in ["Test un.","Test deux.","Test trois."],"A failed attempt plays exactly one random line from the authored sequence")
	check(channel.is_automatic() and not paused and not game.player.controls_blocked and game.state=="playing","Door reply advances automatically and leaves gameplay controls free")
	check(source.mode==Sequence.Mode.CONVERSATION and source.lines.size()==3,"Random playback preserves every source line and its authored mode")
	var first_text: String=channel.current_line.text
	for attempt in 5:door.interact(game.player)
	check(channel.current_line.text==first_text and channel._queue.is_empty(),"Repeated interaction cannot interrupt or queue overlapping dialogue")
	channel.cancel();door.interact(game.player)
	check(not channel.is_active(),"Shared cooldown also protects the interval after a short reply")
	var previous := first_text;var seen := {}
	for attempt in 24:
		reset_reply();door.interact(game.player)
		var text: String=channel.current_line.text
		check(text!=previous,"Two consecutive attempts do not repeat the same line")
		previous=text;seen[text]=true
	check(seen.size()>=2,"Random selection produces different alternatives")
	reset_reply()
	var other := make_door(&"test.locked.key2",&"key_archives",source);door.interact(game.player);first_text=channel.current_line.text;channel.cancel();other.interact(game.player)
	check(not channel.is_active(),"Cooldown is shared across doors, rather than bypassed by trying the next door")
	reset_reply();other.interact(game.player)
	check(channel.current_line.text!=first_text,"Shared replies do not immediately repeat when changing doors")
	reset_reply()
	var sealed := make_door(&"test.locked.sealed",&"",source)
	var permanent: Resource=load(PERMANENT_SOURCE)
	check(game.level.permanent_door_dialogues.resource_path==PERMANENT_SOURCE and sealed.permanent_dialogue_pool.resource_path==PERMANENT_SOURCE,"Permanent doors use the distinct locked_doors.tres authored bank")
	var permanent_texts: Array=[]
	for entry in permanent.lines:permanent_texts.append(entry.text)
	check(not sealed.interact(game.player) and channel.is_active() and channel.current_line.text in permanent_texts,"Locked doors without a key choose one line from locked_doors.tres")
	reset_reply()
	var condemned: Node=Door.new();condemned.door_id=&"test.locked.permanent";condemned.permanently_locked=true;condemned.required_item_id=&"key_archives";condemned.locked_sounds.clear();game.level.add_child(condemned)
	check(condemned.locked and not condemned.open(),"Explicit permanent lock starts closed and refuses open")
	condemned.set_locked(false);check(condemned.locked,"Permanent locks refuse to be unlocked")
	var badge := make_door(&"test.locked.badge",&"access_maintenance",source)
	check(not badge.interact(game.player) and not channel.is_active(),"Access-card doors are excluded for now")
	var mechanism := make_door(&"test.locked.mechanism",&"valve_wheel",source)
	check(not mechanism.interact(game.player) and not channel.is_active(),"Other required-item types do not trigger key-door replies")
	door.locked_dialogue_enabled=false;door.interact(game.player)
	check(not channel.is_active(),"The per-door checkbox can disable its replies")
	door.locked_dialogue_enabled=true
	var manual := Sequence.new();var line := Line.new();line.text="Conversation prioritaire.";manual.lines.append(line);game.play_dialogue(manual)
	door.interact(game.player);check(not channel.is_active() and channel._queue.is_empty(),"A manual conversation cannot enqueue a stale door reply")
	game.dialogue.cancel();reset_reply()
	var sound_door := make_door(&"test.locked.sound",&"key_archives",source)
	sound_door.locked_sounds.assign([load("res://assets/audio/interactables/locked_door_1.wav"),load("res://assets/audio/interactables/locked_door_2.wav")])
	var sounds: Array[String]=[];var times: Array[int]=[]
	for attempt in 2:
		reset_reply();sound_door.interact(game.player)
		var feedback: Node=sound_door._locked_feedback;var sfx: AudioStream=load("res://scripts/audio/psx_audio_routing.gd").source_of(feedback._audio.stream)
		sounds.append(str(channel.get_meta(&"locked_door_last_sound")));var started := Time.get_ticks_msec()
		check(feedback._pending and feedback._audio.playing and not channel.is_active(),"Random lock effect plays before the dialogue starts")
		check(feedback._audio.stream.is_class("AudioStreamPSX") and feedback._audio.bus==&"PSX Reverb","Mechanical effect uses native PSX spatial audio with level reverb")
		var reply_listener := func(_line: Resource,_index: int):times.append(Time.get_ticks_msec())
		channel.line_started.connect(reply_listener)
		for spam in 4:sound_door.interact(game.player);other.interact(game.player)
		check(not channel.is_active() and channel._queue.is_empty() and not other._locked_feedback._pending,"Attempts during a lock effect cannot queue another sound or dialogue")
		var sound_deadline := Time.get_ticks_msec()+4000
		while not channel.is_active() and Time.get_ticks_msec()<sound_deadline:await process_frame
		check(feedback._pending and feedback._audio.playing and channel.is_active() and channel.current_sequence.lines.size()==1,"The reply opens while the lock effect continues, without waiting for its end")
		var sound_timing := {"listeners":times.duplicate(),"elapsed":Time.get_ticks_msec()-started,"source_ms":roundi(sfx.get_length()*1000)}
		check(times.size()==1 and times[0]-started<180,"Locked-door reply follows interaction almost immediately: "+JSON.stringify(sound_timing))
		while feedback._pending and Time.get_ticks_msec()<sound_deadline:await process_frame
		check(times.size()==1,"Finishing the lock sound never launches a second reply")
		channel.line_started.disconnect(reply_listener);times.clear()
	check(sounds[0]!=sounds[1],"Two successive lock attempts choose different mechanical sound variants")
	reset_reply()
	sound_door.interact(game.player);check(sound_door._locked_feedback._pending,"A delayed reply is pending during its mechanical effect")
	sound_door.set_locked(false);await create_timer(1.8).timeout
	check(not channel.is_active(),"Unlocking during the effect cancels its stale locked-door reply")
	reset_reply()
	var voiced := source.duplicate(true);voiced.lines.resize(1);voiced.lines[0].audio=load("res://assets/audio/dialogs/locked_doors_key/1_locked_doors.wav")
	door.locked_dialogue_pool=voiced;door.interact(game.player);await settle(12)
	check(channel.voice_audio.voice.stream!=null and channel.voice_audio.voice.stream.is_class("AudioStreamPSX") and not channel.current_line.is_intercom,"The selected line keeps its own WAV and uses native PSX voice audio")
	reset_reply();door.locked_dialogue_pool=source
	# A one-line bank still works and closes without manual validation.
	var single := Sequence.new();single.minimum_page_seconds=.5;single.reading_characters_per_second=80;single.reply_gap=0;single.lines.append(source.lines[0]);door.locked_dialogue_pool=single;door.interact(game.player)
	var deadline := Time.get_ticks_msec()+7000
	while channel.is_active() and Time.get_ticks_msec()<deadline:await process_frame
	check(not channel.is_active() and not game.player.controls_blocked,"Single-line text replies close naturally without playing another bank entry")
	reset_reply();door.locked_dialogue_pool=source
	inventory.give(inventory.resolve_item(&"key_archives"));door.interact(game.player)
	check(door.is_open and not door.locked and not channel.is_active() and inventory.has_item(&"key_archives"),"Owning the exact key unlocks and opens without a locked-door reply or unwanted consumption")
	reset_reply();condemned.interact(game.player)
	check(channel.is_active() and channel.current_line.text in permanent_texts and condemned.locked and not condemned.is_open,"Even an owned key cannot open a permanently locked door or suppress its generic reply")
	reset_reply()
	var snapshot: Dictionary=root.get_node("WorldEvents").snapshot();door.close();root.get_node("WorldEvents").restore(snapshot);await settle()
	check(door.is_open and not door.locked,"World restoration preserves the opened and unlocked door state")
	check(FileAccess.get_sha256(SOURCE)==source_hash,"Validation never changes the dialogue currently authored by the user")
	check(FileAccess.get_sha256(PERMANENT_SOURCE)==permanent_hash,"Validation preserves the artist's locked_doors.tres")
	current_scene=null;game.queue_free();await settle(8)
	var result := {"ok":failures.is_empty(),"errors":failures}
	FileAccess.open("res://docs/locked-door-dialogue-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("LOCKED_DOOR_DIALOGUE_OK " if failures.is_empty() else "LOCKED_DOOR_DIALOGUE_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
