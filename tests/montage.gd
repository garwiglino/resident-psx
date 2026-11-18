extends SceneTree
const Shot=preload("res://scripts/cinematics/cinematic_shot.gd")
var failures: Array[String]=[]
var closed_sessions := 0
var opened_sessions := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func fixture(game: Node,fast := true) -> Node:
	var sequence=load("res://scenes/cinematics/cinematic_sequence.tscn").instantiate();game.add_child(sequence)
	sequence.plans=sequence.get_plans()
	for plan in sequence.plans:plan.finish_camera_on_confirm=fast
	return sequence
func start(game: Node,sequence: Node) -> void:
	check(game.play_cinematic(sequence),"Montage starts: "+sequence.validation_error());game.cinematics.set_process(false);game.dialogue.set_process(false)
func confirm_current(dialogue: Node) -> void:
	var current: Resource=dialogue.current_sequence
	var limit := 0
	while dialogue.is_active() and dialogue.current_sequence==current and limit<50:dialogue.advance();limit+=1
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.psx_renderer.set_process(false);game.player.set_physics_process(false)
	var manager=game.cinematics;var dialogue=game.dialogue
	dialogue.session_started.connect(func():opened_sessions+=1)
	dialogue.session_finished.connect(func():closed_sessions+=1)
	var sequence=fixture(game);var timeline: AnimationPlayer=sequence.get_node("Timeline")
	check(sequence.plans.size()==2,"Existing valid camera and dialogue cues become two clear plans")
	sequence.plans[1].finished_event=&"last_plan"
	var events: Array[StringName]=[];manager.event_reached.connect(func(_s: Node3D,id: StringName):events.append(id))
	start(game,sequence);manager._process(.4);dialogue.set_process(false)
	check(dialogue.is_active() and manager.plan_index==0,"Text begins during the first camera movement")
	var position: float=timeline.current_animation_position
	dialogue.advance()
	check(manager.plan_index==0 and timeline.current_animation_position==position,"First confirmation only reveals the typewriter, without finishing the camera")
	manager._process(.7)
	check(manager._camera_done and manager.waiting_for_dialogue and dialogue.is_active(),"The camera finishes naturally and holds its last frame while text waits")
	var last_pose: Transform3D=manager.camera.global_transform;manager._process(2)
	check(manager.camera.global_transform.is_equal_approx(last_pose) and dialogue.is_active() and game.player.controls_blocked,"Waiting never closes the text or releases cinematic controls")
	confirm_current(dialogue);dialogue.set_process(false)
	check(manager.plan_index==1 and manager.camera.global_transform.is_equal_approx(sequence.get_node("CameraB").get_camera_transform()),"Confirmation changes the plan with an immediate camera cut")
	manager._process(.15);dialogue.set_process(false)
	var before_end: float=timeline.current_animation_position
	confirm_current(dialogue)
	check(before_end<3 and not manager.is_active() and not game.player.controls_blocked,"Confirming linked text can finish the current movement and return immediately")
	check(sequence.get_node("CameraB").position.is_equal_approx(Vector3(.1,1.4,4.6)),"Fast confirmation applies the exact final camera pose")
	check(events.count(&"last_plan")==1 and not events.has(&"closing"),"Explicit plan-end events fire once; skipped timeline method cues do not fire")
	# Wait for both: confirming early closes only the confirmed text.
	sequence=fixture(game,false);start(game,sequence);manager._process(.4);dialogue.set_process(false)
	confirm_current(dialogue)
	check(manager.is_active() and manager.plan_index==0 and not manager._camera_done and not dialogue.is_active(),"With fast finish disabled, early text validation waits for the natural movement end")
	manager._process(.7);check(manager.plan_index==1,"The next plan starts when both independent conditions are satisfied")
	manager.cancel()
	# Continuous text across consecutive plans, without closing/reopening its session.
	sequence=fixture(game);sequence.plans[1].dialogue_delay=0
	var opens := opened_sessions;var closes := closed_sessions
	start(game,sequence);manager._process(.4);dialogue.set_process(false);confirm_current(dialogue)
	check(manager.plan_index==1 and dialogue.is_active() and opened_sessions==opens+1 and closed_sessions==closes,"Adjacent linked dialogue keeps one continuous window session")
	manager.cancel()
	# Independent camera plans may carry a pending dialogue into the next shot.
	sequence=fixture(game);sequence.plans[0].progression=Shot.Progression.CAMERA;sequence.plans[1].dialogue_delay=0
	start(game,sequence);manager._process(.4);dialogue.set_process(false);manager._process(.7)
	check(manager.plan_index==1 and dialogue.is_active(),"A camera-only plan advances without cancelling its still-open dialogue")
	var second_time: float=sequence.get_node("Timeline").current_animation_position
	confirm_current(dialogue)
	check(manager.plan_index==1 and sequence.get_node("Timeline").current_animation_position==second_time and dialogue.is_active(),"Confirming carried dialogue cannot finish the wrong camera plan")
	manager.cancel()
	# A delayed text trigger still runs while the camera holds its last frame.
	sequence=fixture(game);sequence.plans.resize(1);sequence.plans[0].end_time=.5;sequence.plans[0].dialogue_delay=1
	start(game,sequence);manager._process(.6)
	check(manager._camera_done and not dialogue.is_active() and manager.is_active(),"The final image can wait before a delayed dialogue begins")
	manager._process(.5);dialogue.set_process(false)
	check(dialogue.is_active(),"Delayed dialogue is not lost when camera time has stopped")
	game.pause_game();var elapsed: float=manager._plan_elapsed;manager._process(5)
	check(manager._plan_elapsed==elapsed and not dialogue.view.visible,"Real pause suspends camera and dialogue independently")
	game.start_game();dialogue.cancel()
	check(not manager.is_active() and not game.player.controls_blocked,"External dialogue cancellation restores gameplay safely")
	sequence=fixture(game);sequence.plans.resize(1);sequence.plans[0].end_time=.5;sequence.plans[0].dialogue_delay=1;sequence.plans[0].progression=Shot.Progression.CAMERA
	start(game,sequence);manager._process(.6)
	check(manager.is_active() and manager._montage_done and not dialogue.is_active(),"Camera-only mode also retains text cues scheduled after the movement")
	manager._process(.5);dialogue.set_process(false);check(dialogue.is_active(),"Independent delayed text still triggers after the last camera plan")
	confirm_current(dialogue);check(not manager.is_active(),"Delayed text requires actual validation before returning to gameplay")
	# Manual last-frame hold, and whole-cinematic skip.
	sequence=fixture(game);sequence.plans[0].dialogue=null;sequence.plans[0].progression=Shot.Progression.MANUAL
	start(game,sequence);manager._process(2)
	check(manager.plan_index==0 and manager._camera_done and manager.is_active(),"Manual plans keep the final image until an explicit continuation")
	check(manager.next_plan() and manager.plan_index==1,"A script or explicit confirm advances a manual plan")
	check(manager.skip() and not manager.is_active() and not dialogue.is_active() and game.psx_renderer.camera==game.player.camera,"Whole cinematic skip cancels pending text and restores the gameplay camera")
	# The artist's actual map is interpreted without touching its animation keys.
	var placed=game.get_node_or_null("Map/CinematicSequence")
	# Artist maps may no longer contain the original demonstration instance.
	# Keep testing cue interpretation and preservation with an isolated fixture.
	if not placed:placed=fixture(game)
	var source_clip: Animation=placed.get_node("Timeline").get_animation(placed.animation)
	var count := source_clip.get_track_count();var imported=placed.get_plans()
	check(not imported.is_empty() and placed.validation_error().is_empty(),"Source scene produces valid plans without rewriting its timeline: "+placed.validation_error())
	start(game,placed);manager._process(5);dialogue.set_process(false)
	check(manager.is_active() and manager.plan_index==0 and dialogue.is_active(),"A long frame cannot jump through unread dialogue in the real map")
	manager.cancel();check(source_clip.get_track_count()==count,"Importing old cues never rewrites artist animation tracks")
	FileAccess.open("res://docs/montage-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"opened_sessions":opened_sessions,"closed_sessions":closed_sessions},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	game.queue_free();await process_frame
	# Let the audio thread release stopped SPU voices before engine shutdown.
	await create_timer(.15).timeout
	print("MONTAGE_OK: camera/text independence, last-frame holds, optional confirm-to-finish, continuous dialogue, carried text ownership, delayed triggers, manual continuation, pause, skip and existing map" if failures.is_empty() else "MONTAGE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
