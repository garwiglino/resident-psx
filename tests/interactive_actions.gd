extends SceneTree
const Action=preload("res://scripts/world_events/world_action.gd")
const Sequence=preload("res://scripts/dialogue/dialogue_sequence.gd")
const Line=preload("res://scripts/dialogue/dialogue_line.gd")
var game: Node3D
var manager: Node
var world: Node
var inventory: Node
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func settle(frames := 4) -> void:
	for frame in frames:await process_frame
func fixture(id: String) -> Node3D:
	var scene: Node3D=load("res://scenes/interactions/interphone_example.tscn").instantiate();scene.interaction_id=StringName(id);scene.position=Vector3(1000,0,1000);return scene
func add(scene: Node3D) -> void:game.level.add_child(scene)
func begin(scene: Node3D) -> void:
	check(scene.configuration_error().is_empty(),"Interactive object validates without requiring any inventory item")
	check(scene.interact(game.player),"World interaction opens the object's inspection camera")
	manager.set_process(false);manager.set_physics_process(false)
func flag(id: StringName,value := true) -> Resource:
	var action := Action.new();action.kind=Action.Kind.SET_FLAG;action.id=id;action.value=value;return action
func step_actions() -> void:
	world._process(0);manager._process(0);manager.set_process(false)
func text(automatic := false) -> Resource:
	var value := Sequence.new();value.mode=Sequence.Mode.EXPLORATION_CALL if automatic else Sequence.Mode.CONVERSATION
	var line := Line.new();line.text="Test du bouton d'appel.";value.lines.append(line);return value
func finish_manual() -> void:
	for step in 40:
		if not game.dialogue.is_active():return
		game.dialogue._process(1);game.dialogue.advance()
func run() -> void:
	create_timer(50).timeout.connect(func():push_error("Interactive actions timeout");quit(2));root.size=Vector2i(320,240)
	inventory=root.get_node("InventoryState");inventory.persist_collection=false;world=root.get_node("WorldEvents");world.reset_run()
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.pickup_feedback.enabled=false;game.set_process(false);game.player.set_process(false);game.player.set_physics_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	manager=game.item_placement
	# An unfinished part only disables its own click, never the object's inspection or siblings.
	var unfinished := fixture("test.unfinished");var empty_part: Node3D=load("res://scenes/interactions/action_part.tscn").instantiate();empty_part.name="SansDialogue";empty_part.visual_path=NodePath("../../Modele");unfinished.get_node("Parties").add_child(empty_part);add(unfinished);await settle()
	var original_bag: Dictionary=inventory.snapshot();begin(unfinished)
	check(not empty_part.configuration_error().is_empty() and Array(unfinished._get_configuration_warnings()).any(func(warning: String):return warning.begins_with("SansDialogue :")),"Incomplete button remains identified in authoring warnings without blocking entry")
	check(not manager.select_part(empty_part) and manager.phase==manager.Phase.INSPECTING and not world.interaction_used(empty_part._id()) and inventory.snapshot()==original_bag,"An incomplete button cannot consume an item or commit an empty action")
	var working: Node3D=unfinished.get_node("Parties/Appeler");check(manager.select_part(working),"An incomplete sibling does not prevent a configured button from being clicked");manager._process(.2)
	check(world.fact(&"event.interphone.call.count",0)==1 and manager.phase==manager.Phase.INSPECTING,"Configured sibling still publishes its action and returns to selection")
	empty_part.actions.assign([flag(&"test.invalid.part")]);empty_part.highlight_paths.assign([NodePath("missing_mesh")])
	check(unfinished.configuration_error().is_empty() and not manager.select_part(empty_part) and not world.flag(&"test.invalid.part"),"Broken part paths remain local failures and cannot publish actions")
	manager.cancel();unfinished.camera_path=NodePath("missing_camera")
	check(not unfinished.configuration_error().is_empty() and not unfinished.interact(game.player) and not manager.is_active() and not game.player.controls_blocked,"A missing root camera still rejects entry without taking control")
	unfinished.queue_free();await settle();world.reset_run();await settle()
	# Reproduce the artist's actual interphone entry without saving or changing its model/camera.
	var authored: Node3D=load("res://scenes/interactions/interphone_interact.tscn").instantiate();authored.interaction_id=&"test.authored.interphone";authored.position=Vector3(1000,0,1000)
	var authored_camera: Camera3D=authored.get_node("CameraFixe");var authored_pose := authored_camera.transform;var authored_button: Node3D=authored.get_node("Parties/button_01");var button_pose := authored_button.transform
	add(authored);await settle();begin(authored)
	check(manager.phase==manager.Phase.INSPECTING and manager.station==authored and game.psx_renderer.camera==manager.camera,"The authored interphone now opens its fixed view")
	check(authored_camera.transform.is_equal_approx(authored_pose) and authored_button.transform.is_equal_approx(button_pose),"Entering inspection preserves the artist's camera and button transforms")
	manager.request_exit();check(not manager.is_active() and not game.player.controls_blocked,"An unfinished authored object can exit normally and restore player controls");authored.queue_free();await settle()
	var scene := fixture("test.phone");add(scene);await settle()
	var part: Node3D=scene.get_node("Parties/Appeler");var model: Node3D=scene.get_node("Modele/BoutonAppel")
	var bag: Dictionary=inventory.snapshot();begin(scene)
	check(not scene.all_installed() and not scene.accepts_inventory_item(&"valve_wheel"),"An action-only object is neither an assembly nor an inventory target")
	await physics_frame;check(manager.pick_part(manager.camera.unproject_position(part.selection_area().global_position))==part,"An ordinary action uses the same 3D hit shape as item sockets")
	check(manager.select_part(part) and manager.phase==manager.Phase.ACTION_ANIMATING and not manager.menu.canvas.visible,"Clicking an action starts its animation without opening the inventory")
	manager._process(.08);check(model.position.z<.075 and not manager.select_part(part),"Button animation progresses and blocks double activation")
	manager.cancel();check(is_equal_approx(model.position.z,.075) and not world.interaction_used(part._id()),"Cancelling an unfinished click restores its pose without firing actions")
	begin(scene);manager.select_part(part);manager._process(.2)
	check(manager.phase==manager.Phase.INSPECTING and world.fact(&"event.interphone.call.count",0)==1,"Completed button emits its event and returns to part selection")
	check(part.can_select_part() and inventory.snapshot()==bag,"Repeatable buttons stay selectable and never modify the inventory")
	manager.select_part(part);manager._process(.2);check(world.fact(&"event.interphone.call.count",0)==2,"A repeatable button can be used several times")
	manager.cancel()
	# A manual conversation stays on the object's camera and releases selection after completion.
	part.activation_animation=&"";part.dialogue=text();part.actions.assign([flag(&"test.after.voice")]);begin(scene);manager.select_part(part);step_actions();game.dialogue.set_process(false)
	check(game.dialogue.is_active() and game.dialogue.reservation_owner()==manager and manager.phase==manager.Phase.ACTIONS,"Dialogues can use the inspection-owned channel without deadlocking its reservation")
	check(game.psx_renderer.camera==manager.camera and not manager.menu.canvas.visible and not manager.select_part(part),"Fixed view remains active while the conversation owns input")
	check(not world.flag(&"test.after.voice"),"World actions retain their authored order after a waiting dialogue")
	finish_manual();step_actions();check(world.flag(&"test.after.voice") and manager.phase==manager.Phase.INSPECTING,"Finishing the dialogue runs subsequent actions and restores selection")
	manager.cancel()
	# Automatic dialogue must not wait on the exploration channel suspended by inspection.
	part.dialogue=text(true);part.actions.clear();begin(scene);manager.select_part(part);step_actions()
	check(game.dialogue.is_active() and game.dialogue.is_automatic() and not game.exploration_dialogue.is_active(),"An automatic reply stays on the usable reserved inspection channel")
	manager.cancel();check(not game.dialogue.is_active() and not world.job_active(manager._action_job),"Hard cancellation stops the owned reply and its pending world job")
	# Exit-before-actions restores gameplay before dispatching an exploration call.
	part.after_interaction=part.AfterInteraction.EXIT_VIEW;begin(scene);manager.select_part(part)
	check(not manager.is_active() and not game.player.controls_blocked and game.psx_renderer.camera==game.player.camera,"Exit choice releases the camera and controls before actions start")
	world._process(0);game.exploration_dialogue.set_process(false)
	check(game.exploration_dialogue.is_active() and not game.player.controls_blocked,"Exit choice launches automatic intercom dialogue on the free exploration channel")
	game.exploration_dialogue.cancel();world._process(0);scene.queue_free();await settle()
	# Persistent ON/OFF state and reverse animation, independent of installed items.
	scene=fixture("test.switch");part=scene.get_node("Parties/Appeler");model=scene.get_node("Modele/BoutonAppel");part.behaviour=part.Behaviour.SWITCH;part.state_flag=&"test.switch.state";part.selection_label="ACTIVER";part.actions.assign([flag(&"test.indicator")]);part.off_actions.assign([flag(&"test.indicator",false)])
	var player: AnimationPlayer=scene.get_node("AnimationBouton");var library := AnimationLibrary.new();var clip := Animation.new();clip.length=.4
	var track := clip.add_track(Animation.TYPE_VALUE);clip.track_set_path(track,NodePath("Modele/BoutonAppel:position:z"));clip.track_insert_key(track,0,.075);clip.track_insert_key(track,.4,.13);library.add_animation(&"toggle",clip);player.remove_animation_library(&"");player.add_animation_library(&"",library);part.activation_animation=&"toggle"
	add(scene);await settle();begin(scene);manager.select_part(part);manager._process(.2);manager.cancel()
	check(not part.is_on() and not world.flag(&"test.indicator") and is_equal_approx(model.position.z,.075),"Interrupted switch movement does not commit its state")
	begin(scene);manager.select_part(part);manager._process(.4);step_actions()
	check(part.is_on() and world.flag(&"test.indicator") and part.get_selection_label()=="DESACTIVER" and is_equal_approx(model.position.z,.13),"Switch ON commits its flag, actions, label and final pose")
	var save: Dictionary=world.snapshot();manager.select_part(part);manager._process(.2)
	check(model.position.z>.075 and model.position.z<.13,"Switch OFF reads the activation clip backward when no OFF clip is assigned")
	manager._process(.2);step_actions();check(not part.is_on() and not world.flag(&"test.indicator") and part.get_selection_label()=="ACTIVER","Switch OFF runs its own action list")
	world.restore(save);await settle();check(part.is_on() and world.flag(&"test.indicator") and is_equal_approx(model.position.z,.13),"World restore silently restores switch state and matching pose")
	# Once and conditions are per part, rather than disabling an entire model.
	part.once=true;check(not part.can_select_part(),"Once disables only the already-used part")
	part.once=false;var condition: Resource=load("res://scripts/world_events/world_condition.gd").new();condition.id=&"test.enabled";part.requirements.assign([condition]);check(not part.can_select_part(),"World conditions gate selection")
	world.set_flag(&"test.enabled");check(part.can_select_part(),"Changing a condition makes the part available again")
	part.requirements.clear();scene.queue_free();await settle()
	# Inventory sockets and independent actions coexist under an existing assembly root.
	scene=load("res://scenes/inventory/placement_assembly.tscn").instantiate();scene.interaction_id=&"test.mixed";scene.once=false;scene.position=Vector3(1000,0,1000)
	part=load("res://scenes/interactions/action_part.tscn").instantiate();part.name="Button";part.visual_path=NodePath("../../Modele");part.actions.assign([flag(&"test.mixed.button")]);scene.get_node("Emplacements").add_child(part);add(scene);await settle();begin(scene);manager.select_part(part);step_actions()
	check(world.flag(&"test.mixed.button") and not scene.all_installed() and manager.phase==manager.Phase.INSPECTING,"Action click never completes or consumes a missing inventory piece")
	for socket in scene.placement_targets():
		if socket.is_item_socket():world.mark_interaction(socket._id())
	check(scene.all_installed() and part.can_select_part(),"Assembly completion counts sockets only; a repeatable control remains independent")
	manager.cancel();scene.queue_free();await settle()
	# Exterior controls work on a closed cover, while protected parts remain inaccessible.
	scene=fixture("test.cover");scene.access_settings.enabled=true;scene.access_settings.open_on_interaction=false;part=scene.get_node("Parties/Appeler");part.activation_animation=&"";part.actions.assign([flag(&"test.cover.button")]);add(scene);await settle();begin(scene)
	check(manager.can_pick_parts() and manager.select_part(part),"An exterior button can work with the cover still closed");step_actions()
	part.requires_open=true;check(not manager.select_part(part),"Requires Open protects internal controls");part.requires_open=false
	var open := Action.new();open.kind=Action.Kind.MECHANISM_STATE;open.mechanism_path=NodePath("../..");open.mechanism_operation=0;part.actions.assign([open,flag(&"test.cover.after")]);manager.select_part(part);step_actions();step_actions()
	check(world.flag(&"test.cover.after") and scene.get_mechanism_access().is_open() and manager.phase==manager.Phase.INSPECTING,"An action can open its own cover, await it and continue its action list")
	manager.cancel();scene.queue_free();await settle()
	# A cinematic action leaves inspection before the cinematic takes camera ownership.
	var cine: Node3D=load("res://scripts/cinematics/cinematic_sequence_3d.gd").new();cine.name="ActionCinematic";game.add_child(cine)
	var cine_camera := Camera3D.new();cine_camera.name="CameraA";cine.add_child(cine_camera)
	var timeline := AnimationPlayer.new();timeline.name="Timeline";cine.add_child(timeline);var movie := Animation.new();movie.length=.3;var clips := AnimationLibrary.new();clips.add_animation(&"cinematic",movie);timeline.add_animation_library(&"",clips)
	var shot: Resource=load("res://scripts/cinematics/cinematic_shot.gd").new();shot.progression=2;cine.plans.append(shot)
	scene=fixture("test.cine.button");part=scene.get_node("Parties/Appeler");part.activation_animation=&"";add(scene);await settle()
	var play := Action.new();play.kind=Action.Kind.CINEMATIC;play.cinematic_path=part.get_path_to(cine);part.actions.assign([play]);begin(scene);manager.select_part(part)
	check(not manager.is_active() and game.dialogue.reservation_owner()==null,"A cinematic action automatically exits the close-up even with Keep View selected")
	world._process(0);game.cinematics.set_process(false)
	check(game.cinematics.is_active() and game.psx_renderer.camera!=manager.camera,"Cinematic manager owns the camera after the button hands it over")
	game.cinematics.cancel();world._process(0);scene.queue_free();cine.queue_free();await settle()
	# Source deletion cancels owned audio and prevents later actions from escaping.
	scene=fixture("test.remove");part=scene.get_node("Parties/Appeler");part.activation_animation=&"";part.dialogue=text();part.actions.assign([flag(&"test.must.not.run")]);add(scene);await settle();begin(scene);manager.select_part(part);step_actions();scene.queue_free();await settle();world._process(0)
	check(not manager.is_active() and not game.dialogue.is_active() and not game.player.controls_blocked and not world.flag(&"test.must.not.run"),"Deleting the active object safely cancels its owned dialogue and remaining actions")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/interactive-actions-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("INTERACTIVE_ACTIONS_OK " if failures.is_empty() else "INTERACTIVE_ACTIONS_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
