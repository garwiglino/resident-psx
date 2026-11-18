extends SceneTree
var Condition: Script
var Action: Script
var Response: Script
var Objective: Script
var failures: Array[String]=[]
var observations: Dictionary={}
var world: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func condition(kind: int,id: StringName,expected := true) -> Resource:
	var value: Resource=Condition.new();value.kind=kind;value.id=id;value.expected=expected;return value
func action(kind: int,id: StringName=&"") -> Resource:
	var value: Resource=Action.new();value.kind=kind;value.id=id;return value
func settle(frames := 5) -> void:
	for step in frames:await process_frame
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	world=root.get_node("WorldEvents")
	Condition=load("res://scripts/world_events/world_condition.gd");Action=load("res://scripts/world_events/world_action.gd")
	Response=load("res://scripts/world_events/world_response.gd");Objective=load("res://scripts/world_events/world_objective.gd")
	world.reset_run()
	var raised: Array[StringName]=[];var finished: Array[StringName]=[]
	world.event_raised.connect(func(id: StringName,_data: Dictionary):raised.append(id))
	world.objective_completed.connect(func(id: StringName):finished.append(id))
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.set_process(false);game.psx_renderer.set_process(false)
	game.pickup_feedback.enabled=false
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false);enemy.death_actions.clear();enemy.death_event=&""
	check(game.enemies.size()==4,"Exactly four authored enemies replace the old runtime spawner")
	var ids: Dictionary={}
	for enemy in game.enemies:
		check(game.level.is_ancestor_of(enemy) and enemy.scene_file_path=="res://scenes/enemies/enemy.tscn","Enemy is an editable map instance")
		check(not enemy.enemy_id.is_empty() and not ids.has(enemy.enemy_id),"Map enemy IDs are stable and unique")
		ids[enemy.enemy_id]=true;check(enemy.target==p,"Authored enemies find the actual player")
	var moving := 0
	for entry in game.psx_renderer.entries:
		for enemy in game.enemies:
			if enemy.is_ancestor_of(entry.node):check(not entry.fixed,"Map enemy meshes retain live transforms in the PSX renderer");moving+=1
	check(moving>20,"Authored enemy meshes enter the native renderer")
	var moving_enemy=game.enemies[0];var original_enemy_transform: Transform3D=moving_enemy.global_transform
	moving_enemy.global_position=p.global_position+Vector3(0,0,-3)
	var raster=game.psx_renderer;var view: Transform3D=p.get_render_camera_transform()
	var before_frame: Array=raster.native_geometry.frame(view,p.camera.fov,false,false,true)
	moving_enemy.position.x+=.5
	var after_frame: Array=raster.native_geometry.frame(view,p.camera.fov,false,false,true)
	check(not before_frame.is_empty() and not after_frame.is_empty() and before_frame[0].points!=after_frame[0].points,"Moving an editor-placed enemy updates actual native geometry rather than freezing the cached map mesh")
	check(raster.native_geometry.get_statistics().batches==1,"Editable enemies retain a single native PSX batch")
	moving_enemy.global_transform=original_enemy_transform
	# Room entry and interaction combine into a hidden, single-completion objective.
	var objective: Node=Objective.new();objective.objective_id=&"test.room_and_panel"
	objective.conditions.assign([condition(Condition.Kind.ZONE_VISITED,&"test.room"),condition(Condition.Kind.INTERACTION_USED,&"test.panel")]);game.level.add_child(objective)
	var reaction: Node=Response.new();reaction.response_id=&"test.objective_reaction"
	reaction.conditions.append(condition(Condition.Kind.OBJECTIVE_COMPLETE,objective.objective_id))
	reaction.actions.append(action(Action.Kind.ADD_COUNTER,&"test.reaction"));game.level.add_child(reaction)
	await settle();check(not objective.is_completed(),"Objective waits for every requirement")
	var zone=load("res://scenes/world_events/event_zone.tscn").instantiate();zone.zone_id=&"test.room";game.level.add_child(zone)
	zone.global_position=p.global_position+Vector3(30,0,0)
	for step in 3:await physics_frame
	zone.global_position=p.global_position
	for step in 4:await physics_frame
	check(world.zone_visited(&"test.room") and not objective.is_completed(),"Physical box entry records the room without completing its remaining interaction")
	var interaction=load("res://scenes/world_events/interaction.tscn").instantiate();interaction.interaction_id=&"test.panel";interaction.once=true;game.level.add_child(interaction)
	check(interaction.interact(p),"Inspectable world interaction succeeds")
	await settle();check(objective.is_completed() and world.count(&"test.reaction")==1,"Hidden objective completion starts its configured reaction exactly once")
	check(not interaction.interact(p) and not zone.trigger(),"One-shot interactions and zones do not replay")
	check(finished.count(objective.objective_id)==1,"Objective completion notification is emitted once")
	# Deferred completion, existing facts, reverse conditions and repeated events.
	var existing: Node=Objective.new();existing.objective_id=&"test.existing";existing.conditions.append(condition(Condition.Kind.ZONE_VISITED,&"test.room"));game.level.add_child(existing)
	var repeated: Node=Response.new();repeated.listen_event=&"test.pulse";repeated.once=false
	repeated.conditions.append(condition(Condition.Kind.FLAG,&"test.block",false));repeated.actions.append(action(Action.Kind.ADD_COUNTER,&"test.pulses"));game.level.add_child(repeated)
	world.raise_event(&"test.pulse");world.raise_event(&"test.pulse");await settle()
	check(world.count(&"test.pulses")==2 and existing.is_completed(),"Repeated events are not coalesced, and objectives inspect already-known facts")
	world.set_flag(&"test.block");world.raise_event(&"test.pulse");await settle();check(world.count(&"test.pulses")==2,"Conditions can require a flag to be false")
	# Door state and collision geometry follow real opening/closing, including restore.
	var door=load("res://scenes/world_events/door.tscn").instantiate();door.door_id=&"test.door";door.duration=0
	# Random locked-door chatter has its own integration test and must not
	# occupy the channel used by the action-ordering assertions below.
	door.locked_dialogue_enabled=false;game.level.add_child(door)
	var closed_basis: Basis=door.get_node("Pivot").basis
	check(not world.door_open(door.door_id) and door.interact(p),"Door interaction opens the tracked door")
	await settle();check(world.door_open(door.door_id) and not door.get_node("Pivot").basis.is_equal_approx(closed_basis),"Door visuals and physical pivot match the stored open state")
	check(not door.open(),"Opening an already open door does not emit duplicate events")
	check(door.close(),"Door can be closed again");await settle();check(not world.door_open(door.door_id) and door.get_node("Pivot").basis.is_equal_approx(closed_basis),"Closing restores geometry and world state")
	door.set_locked(true);check(not door.interact(p),"Locked doors reject interactions")
	# Enemy death records its ID, custom event and inspector actions once.
	var victim=game.enemies[0];victim.death_event=&"test.death";victim.death_actions.append(action(Action.Kind.ADD_COUNTER,&"test.kills"))
	check(victim.take_hit(victim.global_position,999),"Real damage kills an authored map enemy")
	check(not victim.take_hit(victim.global_position,999),"A corpse cannot emit a second death")
	await settle();check(world.enemy_dead(victim.enemy_id) and world.count(&"test.kills")==1 and raised.count(&"test.death")==1,"Enemy state, custom event and death actions are delivered exactly once")
	var corpse=load("res://scenes/enemies/enemy.tscn").instantiate();corpse.enemy_id=victim.enemy_id;game.level.add_child(corpse)
	check(corpse.dead and corpse.collision_layer==0,"Reloading a known dead enemy restores a nonblocking corpse without another death event")
	corpse.queue_free();await settle()
	# Persistence is an explicit snapshot, survives scene state restoration, and resets for a new run.
	var saved: Dictionary=world.snapshot();world.set_flag(&"test.transient");door.set_locked(false);door.open();await settle()
	check(world.restore(saved),"World state snapshots restore atomically")
	await settle();check(not world.flag(&"test.transient") and not door.is_open and door.locked,"Door state and flags reflect the restored snapshot")
	check(not reaction.trigger(),"Consumed reactions remain consumed after restoring state")
	check(not world.restore({"version":1,"facts":{"bad":game}}),"Snapshots reject live object references")
	# Presentation actions queue behind existing conversations, then respect authored order.
	var line=load("res://scripts/dialogue/dialogue_line.gd").new();line.text="Appel du monde."
	var sequence=load("res://scripts/dialogue/dialogue_sequence.gd").new();sequence.id=&"test.call";sequence.mode=1;sequence.lines.append(line)
	var call_action=action(Action.Kind.DIALOGUE);call_action.dialogue=sequence
	var chain: Node=Response.new();chain.response_id=&"test.presentation_chain";chain.actions.assign([call_action,action(Action.Kind.SET_FLAG,&"test.after_call")]);game.level.add_child(chain)
	check(chain.trigger(),"A response queues the authored dialogue action")
	await settle();var channel=game.exploration_dialogue
	check(channel.is_active() and not p.controls_blocked and not world.flag(&"test.after_call"),"Exploration event dialogue starts without blocking controls; next action waits")
	channel.cancel();await settle();check(world.flag(&"test.after_call"),"Action chain resumes when the dialogue ends")
	check(raised.count(&"dialogue.test.call.cancelled")==1 and raised.count(&"dialogue.test.call.completed")==0,"Cancelled dialogues do not masquerade as completed story events")
	var conversation=sequence.duplicate(true);conversation.id=&"test.manual";conversation.mode=0
	check(game.play_dialogue(conversation,false),"Priority conversation starts")
	var later: Node=Response.new();later.response_id=&"test.deferred_call";later.actions.append(call_action);game.level.add_child(later);later.trigger()
	await settle();check(game.dialogue.is_active() and not channel.is_active(),"Event calls wait while a manual conversation owns presentation")
	game.dialogue.cancel();await settle();check(channel.is_active() and not p.controls_blocked,"The pending exploration call starts once the conversation releases controls")
	channel.cancel();await settle()
	# Real cinematic action: cuts cameras, waits at the current scene's queue, then restores.
	var cine=load("res://scenes/cinematics/cinematic_sequence.tscn").instantiate();cine.name="EventCamera";cine.id=&"test.world_cine";game.add_child(cine)
	var shot=load("res://scripts/cinematics/cinematic_shot.gd").new();shot.progression=1;shot.end_time=.15;shot.finished_event=&"test.camera_cue";cine.plans.assign([shot])
	check(cine.validation_error().is_empty(),"Authored event cinematic is valid")
	var camera_action=action(Action.Kind.CINEMATIC)
	var camera_response: Node=Response.new();camera_response.response_id=&"test.camera_response";game.level.add_child(camera_response)
	camera_action.cinematic_path=camera_response.get_path_to(cine);camera_response.actions.assign([camera_action,action(Action.Kind.SET_FLAG,&"test.after_cine")])
	check(camera_response.trigger(),"Cinematic response is accepted")
	await settle(2);game.cinematics.set_process(false)
	check(game.cinematics.is_active() and game.psx_renderer.camera==game.cinematics.camera and p.controls_blocked,"World action takes cinematic camera ownership through the existing manager")
	check(not world.flag(&"test.after_cine"),"Later actions wait for cinematic completion")
	game.cinematics._process(.2);await settle()
	check(not game.cinematics.is_active() and game.psx_renderer.camera==p.camera and not p.controls_blocked and world.flag(&"test.after_cine"),"Completion restores camera/controls and continues ordered world actions")
	check(raised.count(&"test.camera_cue")==1 and raised.count(&"cinematic.test.world_cine.completed")==1,"Timeline cues and completed cinematics enter the world event stream once")
	# Job cancellation on scene removal does not leave an orphan action behind.
	var missing: Node=Response.new();game.level.add_child(missing);missing.actions.append(call_action);missing.trigger();missing.queue_free();await settle()
	check(not channel.is_active(),"Removing an event source cancels its not-yet-started presentation job")
	var paused_response: Node=Response.new();game.level.add_child(paused_response);paused_response.actions.append(action(Action.Kind.SET_FLAG,&"test.after_pause"));paused_response.trigger()
	game.pause_game();await create_timer(.05).timeout
	check(not world.flag(&"test.after_pause"),"Real game pause suspends queued world actions")
	game.start_game();await settle();check(world.flag(&"test.after_pause"),"World action resumes normally after pause")
	# Built-in prototype interactions publish facts and complete silent map objectives.
	game.nearest=game.interactables.filter(func(item: Dictionary):return item.kind=="fuse")[0];game.interact();await settle()
	check(world.objective_done(&"couloir.fuse_found"),"Existing fuse pickup participates in hidden objectives")
	game.nearest=game.interactables.filter(func(item: Dictionary):return item.kind=="power")[0];game.interact();await settle()
	check(world.flag(&"couloir.power") and world.objective_done(&"couloir.power_restored"),"Existing power interaction publishes its state and silent objective")
	check(not game.hud.canvas.has_node("Objectives"),"No objective panel or completion UI is introduced")
	game.nearest=game.interactables.filter(func(item: Dictionary):return item.kind=="exit")[0];game.interact();await settle()
	check(world.door_open(&"couloir.exit") and world.objective_done(&"couloir.exit_opened") and game.state=="won","Exit state and its silent objective complete even as the level ends")
	paused=false
	observations={"enemy_ids":ids.keys(),"dynamic_enemy_meshes":moving,"completed_objectives":finished,"events":raised.size(),"facts":world.snapshot().facts.size(),"failures":failures}
	FileAccess.open("res://docs/world-events-validation.json",FileAccess.WRITE).store_string(JSON.stringify(observations,"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free();await settle();world.reset_run();await settle()
	var remaining: Dictionary=world.snapshot().facts
	check(remaining.keys().all(func(key: Variant):return String(key).begins_with("collection.") and bool(remaining[key])),"New-run reset clears gameplay state and preserves only persistent collection ownership")
	print("WORLD_EVENTS_OK: editable enemies, death hooks, physical zones, interactions, doors, silent objectives, conditions, ordered dialogue actions, deduplication and state snapshots" if failures.is_empty() else "WORLD_EVENTS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
