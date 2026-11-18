extends SceneTree
var Target: Script
const Action=preload("res://scripts/world_events/world_action.gd")
var failures: Array[String]=[]
var game: Node3D
var inventory: Node
var controller: Node
var world: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func uid(id: StringName) -> String:
	for entry: Dictionary in inventory.model.sections[&"items"]:
		if not entry.is_empty() and entry.item.id==id:return String(entry.uid)
	return ""
func grant(id: StringName) -> void:check(inventory.give(inventory.resolve_item(id),1,{},false),"Grant "+String(id))
func target(id: StringName) -> Node3D:
	var value=load("res://scenes/inventory/item_target.tscn").instantiate();value.interaction_id=id;value.select_part_first=false;game.level.add_child(value)
	value.global_position=game.player.global_position+Vector3(0,0,-.9);return value
func finish_reply() -> void:
	game.dialogue.set_process(false)
	for tick in 500:
		if not controller._wrong_pending:break
		game.dialogue._process(.1)
	check(not controller._wrong_pending,"Wrong-item reply finishes automatically")
func rigged_target() -> Node3D:
	var value=Target.new();value.interaction_id=&"test.placement.rigged";value.required_item=load("res://assets/inventory/items/valve_wheel.tres")
	value.select_part_first=false
	value.visual_path=NodePath("Modele");value.placement_socket_path=NodePath("Modele/Rig/Fixation/PointInsertion")
	value.animation_player_path=NodePath("Modele/AnimationPlayer");value.installation_animation=&"installer"
	var model := Node3D.new();model.name="Modele";value.add_child(model)
	var sk := Skeleton3D.new();sk.name="Rig";model.add_child(sk)
	sk.add_bone("socle");sk.add_bone("fixation");sk.set_bone_parent(1,0)
	sk.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0,.73,.2)));sk.set_bone_pose_position(1,Vector3(0,.73,.2))
	var mesh := MeshInstance3D.new();mesh.name="Socle";sk.add_child(mesh);mesh.skeleton=NodePath("..")
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.15,0,0),Vector3(.15,0,0),Vector3(0,.7,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]);arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1]);arrays[Mesh.ARRAY_BONES]=PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0]);arrays[Mesh.ARRAY_WEIGHTS]=PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0])
	var geometry := ArrayMesh.new();geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.mesh=geometry
	mesh.material_override=load("res://scripts/psx_materials.gd").make(Color(.4,.4,.4))
	var skin := Skin.new();skin.add_named_bind(&"socle",Transform3D.IDENTITY);mesh.skin=skin
	var attach := BoneAttachment3D.new();attach.name="Fixation";attach.bone_name="fixation";sk.add_child(attach)
	var socket := Marker3D.new();socket.name="PointInsertion";attach.add_child(socket)
	var animation := Animation.new();animation.length=1;animation.loop_mode=Animation.LOOP_LINEAR
	var track := animation.add_track(Animation.TYPE_POSITION_3D);animation.track_set_path(track,NodePath("Rig:fixation"))
	animation.position_track_insert_key(track,0,Vector3(0,.73,.2));animation.position_track_insert_key(track,1,Vector3(.25,.73,.2))
	track=animation.add_track(Animation.TYPE_ROTATION_3D);animation.track_set_path(track,NodePath("Rig:socle"))
	animation.rotation_track_insert_key(track,0,Quaternion.IDENTITY);animation.rotation_track_insert_key(track,1,Quaternion(Vector3.UP,.6))
	var library := AnimationLibrary.new();library.add_animation(&"installer",animation)
	var player := AnimationPlayer.new();player.name="AnimationPlayer";model.add_child(player);player.add_animation_library(&"",library)
	game.level.add_child(value);value.global_position=game.player.global_position+Vector3(1,0,-1);return value
func run() -> void:
	inventory=root.get_node("InventoryState");inventory.persist_collection=false;world=root.get_node("WorldEvents");world.reset_run()
	Target=load("res://scripts/inventory/item_target.gd")
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false);game.pickup_feedback.enabled=false
	game.player.set_process(false);game.player.set_physics_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	controller=game.item_placement;controller.set_process(false)
	grant(&"valve_wheel");grant(&"lever_handle");grant(&"fuse_16a")
	var station := target(&"test.placement.valve")
	var piece_collision := StaticBody3D.new();piece_collision.collision_layer=8;piece_collision.collision_mask=1;station.prepare_piece().add_child(piece_collision)
	station._show_installed(false)
	check(piece_collision.collision_layer==0,"Missing piece never leaves an invisible collider")
	var action := Action.new();action.kind=Action.Kind.ADD_COUNTER;action.id=&"test.placement.finished";station.actions.append(action)
	var previous: Camera3D=game.psx_renderer.camera;var count_before: int=inventory.count(&"valve_wheel")
	check(station.interact(game.player),"E opens the reusable station interaction");controller.set_process(false)
	check(game.state=="cinematic" and game.player.controls_blocked and not paused,"Only gameplay controls are locked; simulation stays alive")
	check(game.psx_renderer.camera==controller.camera and controller.camera.is_current(),"Fixed camera owns the native PSX view")
	check(not game.player.visual.visible,"Player cannot obscure the close-up camera")
	var ids: Array=[]
	for entry in controller.menu.entries:ids.append(entry.item.id)
	check(&"valve_wheel" in ids and &"lever_handle" in ids and &"fuse_16a" in ids and not &"medkit" in ids,"Picker lists all placable owned items, including incorrect choices")
	check(inventory.count(&"valve_wheel")==count_before and not world.interaction_used(station._id()),"Opening the picker never consumes or completes anything")
	check(not station.interact(game.player),"Repeated interaction cannot reopen an owned station")
	var lines: Array[String]=[];controller.wrong_item_selected.connect(func(_item: Resource,line: Resource):if line:lines.append(line.text))
	for index in 3:
		check(not controller.choose(uid(&"lever_handle")),"Wrong part is rejected")
		check(game.dialogue.is_active() and game.dialogue.is_automatic() and not controller.menu.canvas.visible,"One random wrong_item line uses the existing automatic audio/dialogue system")
		finish_reply();check(controller.menu.canvas.visible and game.psx_renderer.camera==controller.camera,"Same fixed view and complete picker return after the reply")
	check(lines.size()==3 and lines[0]!=lines[1] and lines[1]!=lines[2],"Wrong-item selection avoids consecutive duplicate replies")
	check(inventory.count(&"lever_handle")==1 and inventory.count(&"valve_wheel")==count_before,"Wrong choices leave all objects untouched")
	var atlas_id: int=game.psx_renderer.atlas_texture.get_instance_id()
	var wheel: Node3D=station.prepare_piece();var final := wheel.transform
	check(controller.choose(uid(&"valve_wheel")),"Matching part starts insertion");controller._process(station.placement_duration*.5)
	check(wheel.visible and not wheel.transform.is_equal_approx(final) and inventory.count(&"valve_wheel")==count_before,"Part moves smoothly before inventory consumption")
	var elapsed: float=controller._elapsed;game.pause_game();controller._process(3)
	check(controller._elapsed==elapsed and not controller.menu.canvas.visible,"Pause freezes insertion and hides its UI")
	game.start_game();controller.set_process(false);controller._process(station.placement_duration)
	check(not controller.is_active() and wheel.visible and wheel.transform.is_equal_approx(final),"Inserted part reaches the exact authored transform")
	check(inventory.count(&"valve_wheel")==count_before-1 and world.interaction_used(station._id()),"Successful installation consumes and persists exactly once")
	check(piece_collision.collision_layer==8 and piece_collision.collision_mask==1,"Installed piece regains its exact authored collision layers")
	check(game.psx_renderer.camera==previous and game.player.visual.visible and not game.player.controls_blocked and game.state=="playing","Camera, player visibility and controls are restored")
	check(game.dialogue.reservation_owner()==null,"Dialogue reservation is released")
	for frame in 5:await process_frame
	check(world.count(&"test.placement.finished")==1 and not station.can_interact(),"Completion world actions run once after returning camera ownership")
	check(game.psx_renderer.atlas_texture.get_instance_id()==atlas_id,"Choosing and placing never rebuild texture pages")
	var saved: Dictionary=world.snapshot();wheel.hide();check(world.restore(saved),"World snapshot restores")
	for frame in 3:await process_frame
	check(wheel.visible and inventory.count(&"valve_wheel")==0 and world.count(&"test.placement.finished")==1,"Reloaded installation does not consume or replay completion actions")
	# Cancellation and a removed source roll back the still-uncommitted piece.
	grant(&"valve_wheel");var cancelled := target(&"test.placement.cancel")
	check(cancelled.interact(game.player),"Another station can open");controller.set_process(false);controller.choose(uid(&"valve_wheel"));controller._process(.2);controller.cancel()
	check(inventory.count(&"valve_wheel")==1 and not cancelled.prepare_piece().visible and not world.interaction_used(cancelled._id()),"Cancelled insertion restores the missing part without consuming inventory")
	check(cancelled.interact(game.player),"Cancelled station remains reusable");controller.set_process(false);cancelled.queue_free();await process_frame
	check(not controller.is_active() and not game.player.controls_blocked and game.psx_renderer.camera==previous,"Deleting the source cannot strand the camera or controls")
	# Rigged socket, private animation, rollback, exact endpoint and silent restore.
	var rigged := rigged_target();var sk: Skeleton3D=rigged.get_node("Modele/Rig")
	var initial := sk.get_bone_pose(0);var clip: Animation=rigged.animation_source().get_animation(&"installer")
	check(rigged.interact(game.player),"A rigged mechanism uses the same station workflow");controller.set_process(false);controller.choose(uid(&"valve_wheel"));controller._process(.7);controller._process(.5)
	check(controller.is_active() and not sk.get_bone_pose(0).is_equal_approx(initial),"Mechanism animation runs after insertion")
	controller.cancel();check(sk.get_bone_pose(0).is_equal_approx(initial) and inventory.count(&"valve_wheel")==1,"Cancelling rigged installation restores the exact previous skeleton pose")
	check(rigged.interact(game.player),"Rigged installation can retry");controller.set_process(false);controller.choose(uid(&"valve_wheel"));controller._process(.7);controller._process(1.1)
	var socket: Node3D=rigged.socket_node();rigged.sync_socket()
	check(world.interaction_used(rigged._id()) and inventory.count(&"valve_wheel")==0,"Rigged installation commits after the mechanism animation")
	check(rigged.prepare_piece().global_transform.is_equal_approx(socket.global_transform*rigged._piece_final),"Installed piece follows the animated bone socket")
	check(absf(sk.get_bone_pose_rotation(0).angle_to(Quaternion(Vector3.UP,.6)))<.001,"Mechanism holds the exact final pose")
	check(clip.loop_mode==Animation.LOOP_LINEAR,"Original shared animation resources are never modified")
	saved=world.snapshot();sk.set_bone_pose_rotation(0,Quaternion.IDENTITY);world.restore(saved)
	for frame in 3:await process_frame
	check(absf(sk.get_bone_pose_rotation(0).angle_to(Quaternion(Vector3.UP,.6)))<.001,"Restored rig samples its installed pose without replaying animation events")
	# A level can leave/reenter the tree without losing private geometry.
	var rig_mesh: MeshInstance3D=rigged.get_node("Modele/Rig/Socle");var geometry: Mesh=rig_mesh.mesh
	game.level.remove_child(rigged);game.level.add_child(rigged)
	for frame in 3:await process_frame
	check(rig_mesh.mesh==geometry and world.interaction_used(rigged._id()),"Reparenting a level restores render geometry and installation")
	world.reset_run()
	for frame in 3:await process_frame
	check(sk.get_bone_pose(0).is_equal_approx(initial) and not rigged.prepare_piece().visible,"Resetting world state restores the mechanism's original missing-piece pose")
	# Empty inventory still permits inspecting the pedestal and backing out.
	var empty := target(&"test.placement.empty");inventory.remove_item(&"lever_handle",1);inventory.remove_item(&"fuse_16a",1)
	check(empty.interact(game.player),"Pedestal can be inspected without the correct part");controller.set_process(false)
	check(controller.menu.entries.is_empty() and controller.menu.empty_label.visible,"Empty picker stays understandable")
	controller.cancel()
	grant(&"valve_wheel");var interrupted := target(&"test.placement.death")
	check(interrupted.interact(game.player),"Final interruption fixture opens");controller.set_process(false);controller.choose(uid(&"valve_wheel"));controller._process(.2)
	game.player.health=0;controller._process(.1)
	check(not controller.is_active() and inventory.count(&"valve_wheel")==1 and not world.interaction_used(interrupted._id()) and not game.player.controls_blocked,"Death during placement cancels without consuming the piece or stranding controls")
	game.player.health=game.player.max_health
	# The artist builds one ordinary scene, then places independent instances.
	var authored: Node3D=load("res://scenes/inventory/placement_valve.tscn").instantiate()
	authored.interaction_id=&"test.placement.authored";game.level.add_child(authored)
	authored.position=Vector3(5,0,2);authored.rotation.y=.8;authored.scale=Vector3.ONE*1.2
	var second: Node3D=load("res://scenes/inventory/placement_valve.tscn").instantiate()
	second.interaction_id=&"test.placement.authored.second";game.level.add_child(second);second.position=Vector3(-5,0,2)
	var authored_piece: Node3D=authored.get_node(authored.installed_visual_path)
	var expected_camera: Transform3D=authored.get_node(authored.camera_path).get_camera_transform()
	check(not authored_piece.visible and authored_piece==authored.prepare_piece(),"Saved visible editor piece is reused and hidden at runtime, without an extra generated copy")
	check(authored.interact(game.player),"Authored placement scene works as a map instance");controller.set_process(false)
	check(controller.phase==controller.Phase.INSPECTING and not controller.menu.canvas.visible,"Scene opens with inspection before inventory")
	check(controller.select_part(authored),"Click selection opens the single-scene socket")
	check(controller.camera.global_transform.is_equal_approx(expected_camera),"Authored fixed camera follows the placed scene's transform")
	controller.choose(uid(&"valve_wheel"));controller._process(.7);controller._process(.7)
	check(not controller.is_active() and world.interaction_used(authored._id()) and authored_piece.visible,"Map instance completes its authored insertion and AnimationPlayer clip")
	check(absf(authored_piece.rotation.z-PI/2)<.001,"Authored scene animation holds its exact final piece pose")
	check(not world.interaction_used(second._id()) and not second.prepare_piece().visible and second.can_interact(),"Another instance of the same placement scene keeps its own missing-piece state")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/item-placement-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures,"wrong_replies":lines},"\t"))
	print("ITEM_PLACEMENT_OK " if failures.is_empty() else "ITEM_PLACEMENT_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
