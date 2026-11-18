extends SceneTree
var game: Node3D
var manager: Node
var inventory: Node
var world: Node
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func settle(frames := 3) -> void:
	for frame in frames:await process_frame
func tick(access: Node,delta: float) -> void:access._process(delta);access.set_process(false)
func uid(id: StringName) -> String:
	for entry: Dictionary in inventory.model.sections[&"items"]:
		if not entry.is_empty() and entry.item.id==id:return entry.uid
	return ""
func give(id: StringName) -> void:inventory.give(inventory.resolve_item(id),1,{},false)
func fixture(id: String,policy: int) -> Node3D:
	var scene: Node3D=load("res://scenes/inventory/placement_access_example.tscn").instantiate();scene.interaction_id=StringName(id);scene.access_settings=scene.access_settings.duplicate(true);scene.access_settings.close_policy=policy
	game.level.add_child(scene);scene.position=Vector3(1000,0,1000);return scene
func begin(scene: Node3D) -> Node:
	check(scene.configuration_error().is_empty(),"Authored access example has valid camera, slots and clips")
	check(scene.interact(game.player),"Configured mechanism accepts interaction")
	manager.set_process(false);manager.set_physics_process(false)
	var access: Node=scene.get_mechanism_access();access.set_process(false);return access
func install(part: Node3D) -> void:
	give(part.required_id());check(manager.select_part(part),"Open mechanism accepts socket selection")
	check(manager.choose(uid(part.required_id())),"Matching inventory item begins insertion")
	manager._process(1)
	if manager.phase==manager.Phase.ANIMATING:manager._process(1)
	manager.set_process(false)
func run() -> void:
	create_timer(50).timeout.connect(func():push_error("Mechanism placement timeout");quit(2))
	root.size=Vector2i(320,240);inventory=root.get_node("InventoryState");inventory.persist_collection=false;world=root.get_node("WorldEvents");world.reset_run()
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.pickup_feedback.enabled=false;game.set_process(false);game.player.set_process(false);game.player.set_physics_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	manager=game.item_placement;await settle()
	for policy in 4:
		var scene := fixture("test.policy.%s" % policy,policy);await settle()
		var wheel: Node3D=scene.get_node("Emplacements/Roue");var lever: Node3D=scene.get_node("Emplacements/Levier")
		var access := begin(scene)
		check(manager.phase==manager.Phase.OPENING and not manager.select_part(wheel) and not manager.menu.canvas.visible,"Selection waits for opening to finish")
		tick(access,.65);check(manager.phase==manager.Phase.INSPECTING and access.is_open(),"Opening reveals the selection cursor")
		install(wheel);check(manager.phase==manager.Phase.INSPECTING and not world.interaction_used(lever._id()),"Partial installation keeps the other slot available")
		manager.request_exit();access.set_process(false)
		if policy==1:
			check(manager.phase==manager.Phase.CLOSING and game.player.controls_blocked,"Close-on-exit retains fixed camera until closure")
			tick(access,.65)
		check(not manager.is_active() and not game.player.controls_blocked,"Partial exit restores player controls")
		check(access.is_open()==(policy!=1),"Partial exit obeys each physical closing policy")
		var starts: int=world.fact(StringName("event.mechanism.%s.opening.count" % scene._id()),0)
		access=begin(scene)
		if policy==1:tick(access,.65)
		check(manager.phase==manager.Phase.INSPECTING,"Second interaction returns to inspection")
		check(world.fact(StringName("event.mechanism.%s.opening.count" % scene._id()),0)==starts+(1 if policy==1 else 0),"A lid left open does not replay opening")
		install(lever);access.set_process(false)
		if policy in [1,2]:
			check(manager.phase==manager.Phase.CLOSING,"Last part closes the lid before returning the camera")
			tick(access,.65)
		check(not manager.is_active() and access.is_open()==(policy in [0,3]),"Complete exit obeys leave-open, on-exit, when-complete and event-only rules")
		check(world.interaction_used(wheel._id()) and world.interaction_used(lever._id()) and world.interaction_used(scene._id()),"Lid state never replaces independent installed-piece state")
		scene.queue_free();await settle()
	# close_when_complete controls only the camera, independently of the physical closing rule.
	var scene := fixture("test.stay",2);scene.close_when_complete=false;scene.inspect_when_complete=true;await settle()
	var access := begin(scene);tick(access,.65)
	install(scene.get_node("Emplacements/Roue"));install(scene.get_node("Emplacements/Levier"));access.set_process(false);tick(access,.65)
	check(manager.phase==manager.Phase.INSPECTING and not access.is_open() and not manager.can_pick_parts(),"Physical close can finish while the inspection camera stays active")
	check(manager.inspection_caption()=="FERME","Closed inspection clearly blocks socket selection")
	manager.request_exit();check(not manager.is_active() and scene.can_interact(),"Completed mechanism can be inspected again when explicitly allowed")
	scene.queue_free();await settle()
	# Event received while an item animates is deferred until the commit, not rolled back.
	scene=fixture("test.queued",3);scene.access_settings.close_event=&"test.queued.close";await settle()
	var wheel: Node3D=scene.get_node("Emplacements/Roue");var lever: Node3D=scene.get_node("Emplacements/Levier")
	var player: AnimationPlayer=scene.get_node("AnimationCouvercle");var clip := Animation.new();clip.length=.5
	var track := clip.add_track(Animation.TYPE_VALUE);clip.track_set_path(track,NodePath("Modele/Charniere:rotation:y"));clip.track_insert_key(track,0,0.0);clip.track_insert_key(track,.5,0.0)
	track=clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(track,NodePath("Modele/FixationRoue"));clip.position_track_insert_key(track,0,Vector3(-.35,.8,.1));clip.position_track_insert_key(track,.5,Vector3(-.35,.92,.1))
	player.get_animation_library(&"").add_animation(&"insert",clip);wheel.animation_player_path=wheel.get_path_to(player);wheel.installation_animation=&"insert"
	access=begin(scene);tick(access,.65);give(wheel.required_id());manager.select_part(wheel);manager.choose(uid(wheel.required_id()));world.raise_event(&"test.queued.close");await settle();access.set_process(false)
	check(manager.phase==manager.Phase.PLACING and access.is_active() and inventory.count(wheel.required_id())==1,"Close event waits for the moving item and its animation")
	manager._process(1);manager._process(.2);access.reapply_pose()
	check(is_equal_approx(scene.get_node("Modele/Charniere").rotation.y,-1.9),"Full-rig installation's static tracks cannot reset the lid")
	manager._process(.4);manager.set_process(false);tick(access,0)
	check(manager.phase==manager.Phase.CLOSING and world.interaction_used(wheel._id()) and not world.interaction_used(lever._id()),"Queued close starts after the successful commit")
	tick(access,.65)
	check(not manager.is_active() and is_equal_approx(scene.get_node("Modele/FixationRoue").position.y,.92),"Closing keeps installed mechanism channels intact")
	var save: Dictionary=world.snapshot();world.restore(save);await settle(5);access.set_process(false)
	check(not access.is_open() and wheel.prepare_piece().visible and not lever.prepare_piece().visible and is_equal_approx(scene.get_node("Modele/FixationRoue").position.y,.92),"Restore combines closed lid, installed animation and independently missing piece")
	# A wrong-item dialogue can be interrupted cleanly by a close event.
	access=begin(scene);tick(access,.65);give(&"fuse_16a");manager.select_part(lever);manager.choose(uid(&"fuse_16a"))
	check(manager._wrong_pending,"Wrong item starts its normal random reply")
	world.raise_event(&"test.queued.close");await settle();access.set_process(false)
	check(manager.phase==manager.Phase.CLOSING and not game.dialogue.is_active(),"Close event releases the wrong-item dialogue reservation")
	tick(access,.65);check(not manager.is_active() and inventory.count(&"fuse_16a")==1,"Wrong item is retained after event closure")
	scene.queue_free();await settle()
	# Save/restore, pause and early exit while the lid itself moves.
	scene=fixture("test.interrupt",1);await settle();access=begin(scene);tick(access,.2)
	var angle: float=scene.get_node("Modele/Charniere").rotation.y;paused=true;access.set_process(true);await settle();access.set_process(false)
	check(is_equal_approx(scene.get_node("Modele/Charniere").rotation.y,angle),"Pause freezes the access animation");paused=false
	save=world.snapshot();world.restore(save);await settle(5);access.set_process(false)
	check(not manager.is_active() and access.is_open() and not game.player.controls_blocked,"Restore during opening releases inspection and restores the saved open endpoint")
	access.request_close();access.set_process(false);tick(access,.65);access=begin(scene);tick(access,.2);manager.request_exit();access.set_process(false);tick(access,.45)
	check(manager.is_active() and manager.phase==manager.Phase.CLOSING,"Early exit finishes opening then closes without jumping poses")
	tick(access,.65);check(not manager.is_active() and not access.is_open(),"Early exit finally returns controls with closed state")
	access=begin(scene);tick(access,.2);scene.queue_free();await settle()
	check(not manager.is_active() and not game.player.controls_blocked,"Removing the active mechanism safely restores controls")
	# Single-slot legacy scene, no clips, immediate transitions: no signal reentrancy failures.
	scene=load("res://scenes/inventory/item_target.tscn").instantiate();scene.interaction_id=&"test.single";scene.access_settings.enabled=true;scene.access_settings.close_policy=1;game.level.add_child(scene);scene.position=Vector3(1000,0,1000);await settle()
	access=begin(scene);check(manager.phase==manager.Phase.INSPECTING and access.is_open(),"Existing single-slot scenes support instant opening without a clip")
	install(scene);check(not manager.is_active() and not access.is_open(),"Instant close and completion restore the camera exactly once")
	scene.queue_free();await settle()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/mechanism-placement-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("MECHANISM_PLACEMENT_OK " if failures.is_empty() else "MECHANISM_PLACEMENT_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
