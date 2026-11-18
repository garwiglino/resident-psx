extends SceneTree
var Access: Script
const Settings=preload("res://scripts/inventory/mechanism_access_settings.gd")
const Action=preload("res://scripts/world_events/world_action.gd")
var world: Node
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func settle() -> void:
	for frame in 4:await process_frame
func fixture(id: StringName,initial := false) -> Node3D:
	var model := Node3D.new();model.name="Fixture"
	var lid := Node3D.new();lid.name="Lid";model.add_child(lid)
	var part := Node3D.new();part.name="Part";part.position.x=.75;model.add_child(part)
	var player := AnimationPlayer.new();player.name="Clips";model.add_child(player)
	var clip := Animation.new();clip.length=.5
	var track := clip.add_track(Animation.TYPE_VALUE);clip.track_set_path(track,NodePath("Lid:rotation:y"));clip.track_insert_key(track,0,0.0);clip.track_insert_key(track,.5,1.2)
	track=clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(track,NodePath("Part"));clip.position_track_insert_key(track,0,Vector3.ZERO);clip.position_track_insert_key(track,.5,Vector3.ZERO)
	var library := AnimationLibrary.new();library.add_animation(&"open",clip);player.add_animation_library(&"",library)
	var access: Node=Access.new();access.name="Access";access.state_id=id;access.settings=Settings.new();access.settings.enabled=true;access.settings.initially_open=initial;access.settings.animation_player_path=NodePath("Clips");access.settings.opening_animation=&"open";model.add_child(access)
	root.add_child(model);access.set_process(false);return model
func run() -> void:
	create_timer(25).timeout.connect(func():push_error("Access test timeout");quit(2))
	root.get_node("InventoryState").persist_collection=false;world=root.get_node("WorldEvents");world.reset_run()
	Access=load("res://scripts/inventory/mechanism_access.gd")
	var model := fixture(&"test.access");var access: Node=model.get_node("Access");var lid: Node3D=model.get_node("Lid");var part: Node3D=model.get_node("Part")
	check(access.access_configuration_error().is_empty(),"Valid generic access settings")
	check(not access.is_open() and is_zero_approx(lid.rotation.y),"Initial closed endpoint")
	check(is_equal_approx(part.position.x,.75),"Static tracks from full-model exports do not reset independent parts")
	access.request_open();access.set_process(false);access._process(.2)
	check(access.is_transitioning() and lid.rotation.y>0 and lid.rotation.y<1.2,"Opening animation progresses")
	var save: Dictionary=world.snapshot()
	check(save.facts.get(&"mechanism.test.access.target_state")=="open","Mid-animation snapshot stores the intended endpoint")
	access._process(1)
	check(access.is_open() and is_equal_approx(lid.rotation.y,1.2),"Opening holds final pose")
	await settle();var count: int=world.fact(&"event.mechanism.test.access.opening.count",0)
	access.request_open();check(not access.is_active() and world.fact(&"event.mechanism.test.access.opening.count",0)==count,"Repeated open does not replay animation or events")
	access.request_close();access.set_process(false);access._process(.25)
	check(lid.rotation.y>0 and lid.rotation.y<1.2,"Missing close clip reverses opening with the same timing")
	access._process(.3);check(not access.is_open() and is_zero_approx(lid.rotation.y),"Reverse fallback reaches closed endpoint")
	world.restore(save);await settle();access.set_process(false)
	check(access.is_open() and not access.is_active() and is_equal_approx(lid.rotation.y,1.2),"Loading midway silently restores open endpoint")
	var closing_events: int=world.fact(&"event.mechanism.test.access.closing.count",0)
	access.request_close();access.set_process(false);access._process(.1);save=world.snapshot();world.restore(save);await settle();access.set_process(false)
	check(not access.is_open() and not access.is_active() and is_zero_approx(lid.rotation.y),"Loading midway through closing restores closed endpoint")
	check(world.fact(&"event.mechanism.test.access.closing.count",0)==closing_events+1,"Restore does not replay transition events")
	# Commands received during a transition finish that clip, then run the last requested direction.
	access.request_open();access.set_process(false);access._process(.15);access.request_close();access._process(.35)
	check(access.is_transitioning() and access.is_active(),"Opposite command is queued without a mid-pose jump")
	access._process(.5);check(not access.is_open() and not access.is_active(),"Queued command reaches its own endpoint")
	# An installation can hold the command pending; WorldAction waits for it as well.
	var gate := {"allow":false};access.transition_allowed=func(_open: bool):return gate.allow
	var open := Action.new();open.kind=Action.Kind.MECHANISM_STATE;open.mechanism_path=NodePath("Access");open.mechanism_operation=0
	var next := Action.new();next.kind=Action.Kind.SET_FLAG;next.id=&"access.after"
	check(world.execute([open,next],model),"World action accepts a generic component")
	world._process(0);world.set_process(false);access.set_process(false)
	check(access.is_active() and not access.is_transitioning() and not world.flag(&"access.after"),"Waiting action includes a command deferred by installation")
	gate.allow=true;access._process(0);access.set_process(false);access._process(.5);world._process(0);world.set_process(false)
	check(access.is_open() and world.flag(&"access.after"),"Following actions run after the physical endpoint")
	access.transition_allowed=Callable();access.settings.open_event=&"test.open";access.settings.close_event=&"test.close"
	world.raise_event(&"test.close");await settle();access.set_process(false);access._process(.5)
	check(not access.is_open(),"Authored world event closes the component")
	world.raise_event(&"test.open");await settle();access.set_process(false);access._process(.5)
	check(access.is_open(),"Authored world event opens the component")
	# Distinct IDs, initial state, and older world snapshots lacking mechanism fields.
	var second := fixture(&"test.second",true);var other: Node=second.get_node("Access")
	check(other.is_open() and world.fact(&"mechanism.test.second.open",false),"Fresh initially-open state is included in snapshots without fabricated events")
	world.restore({"version":1,"facts":{}});await settle();access.set_process(false);other.set_process(false)
	check(not access.is_open() and other.is_open(),"Old saves use each instance's configured initial state")
	access.request_open();access.set_process(false);access._process(.5);save=world.snapshot();model.free();model=fixture(&"test.access");access=model.get_node("Access")
	check(access.is_open() and is_equal_approx(model.get_node("Lid").rotation.y,1.2) and other.is_open(),"Recreated level instance uses the same stable ID")
	access.request_close();access.set_process(false);access._process(.5);check(other.is_open(),"Two mechanism instances keep independent state")
	# A dedicated closing clip uses its own duration and reverse fallback can open it.
	var close_clip: Animation=model.get_node("Clips").get_animation(&"open").duplicate(true);close_clip.length=.8
	close_clip.track_set_key_value(0,0,1.2);close_clip.track_set_key_time(0,1,.8);close_clip.track_set_key_value(0,1,0.0)
	model.get_node("Clips").get_animation_library(&"").add_animation(&"close",close_clip)
	access.settings.opening_animation=&"";access.settings.closing_animation=&"close";access.request_open();access.set_process(false);access._process(.4)
	check(access.is_active() and is_equal_approx(model.get_node("Lid").rotation.y,.6),"Opening reverses a close-only animation")
	access._process(.4);access.request_close();access.set_process(false);access._process(.4)
	check(access.is_active() and is_equal_approx(model.get_node("Lid").rotation.y,.6),"Dedicated closing clip preserves its timing")
	access._process(.4)
	# Scope a shared skeleton to lid bones and descendants, preserving the rest of the rig.
	var rig := Skeleton3D.new();rig.name="Rig";model.add_child(rig)
	for name in ["body","lid","handle","piece"]:rig.add_bone(name)
	rig.set_bone_parent(1,0);rig.set_bone_parent(2,1);rig.set_bone_parent(3,0)
	var bones_clip := Animation.new();bones_clip.length=.5
	for bone in 4:
		var track := bones_clip.add_track(Animation.TYPE_POSITION_3D);bones_clip.track_set_path(track,NodePath("Rig:"+rig.get_bone_name(bone)));bones_clip.position_track_insert_key(track,0,Vector3.ZERO);bones_clip.position_track_insert_key(track,.5,Vector3(0,float(bone+1),0))
	model.get_node("Clips").get_animation_library(&"").add_animation(&"bones",bones_clip)
	access.settings.opening_animation=&"bones";access.settings.closing_animation=&"";access.settings.animated_root_path=NodePath("Rig");access.settings.bone_names=PackedStringArray(["lid"])
	access.request_open();access.set_process(false);access._process(.5)
	check(rig.get_bone_pose_position(0)==Vector3.ZERO and rig.get_bone_pose_position(3)==Vector3.ZERO,"Explicit bone mask protects body and independent piece")
	check(rig.get_bone_pose_position(1)==Vector3(0,2,0) and rig.get_bone_pose_position(2)==Vector3(0,3,0),"Explicit bone mask includes the lid's descendants")
	access.request_close();access.set_process(false);access._process(.5);check(rig.get_bone_pose_position(1)==Vector3.ZERO,"Masked skeleton closing reaches authored pose")
	# The reusable component also survives a level branch leaving and re-entering the tree.
	access.request_open();access.set_process(false);access._process(.2);root.remove_child(model);root.add_child(model);await settle();access.set_process(false)
	check(access.is_open() and rig.get_bone_pose_position(1)==Vector3(0,2,0),"Reparented mechanism settles its saved requested state")
	model.free();second.free();await settle()
	FileAccess.open("res://docs/mechanism-access-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("MECHANISM_ACCESS_OK " if failures.is_empty() else "MECHANISM_ACCESS_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
