extends SceneTree
var game: Node3D
var manager: Node
var inventory: Node
var world: Node
var failures: Array[String]=[]
var simulated_mouse: Variant=null
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func settle(frames := 3) -> void:
	for frame in frames:
		await process_frame
		# Real Windows mouse events can arrive alongside this test's synthetic input.
		if simulated_mouse!=null:move(simulated_mouse)
func capture(name: String) -> Image:
	await settle();await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image();var enlarged := picture.duplicate();enlarged.resize(960,720,Image.INTERPOLATE_NEAREST);enlarged.save_png("res://docs/placement-hotspot-"+name+".png");return picture
func uid(id: StringName) -> String:
	for entry: Dictionary in inventory.model.sections[&"items"]:
		if not entry.is_empty() and entry.item.id==id:return entry.uid
	return ""
func point(part: Node3D) -> Vector2:return manager.camera.unproject_position(part.selection_area().global_position)
func move(at: Vector2) -> void:
	simulated_mouse=at
	var event := InputEventMouseMotion.new();event.position=at;event.global_position=at;root.push_input(event,true)
	if is_instance_valid(manager):manager._physics_process(0)
func click(at: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func rigged_scene() -> Node3D:
	var value: Node3D=load("res://scenes/inventory/placement_assembly.tscn").instantiate();value.interaction_id=&"test.assembly.rigged"
	value.get_node("Emplacements/Levier").free();value.get_node("Modele/FixationLevier").free();value.get_node("Modele/FixationRoue").free()
	var part: Node3D=value.get_node("Emplacements/Roue");var model: Node3D=value.get_node("Modele")
	var skeleton := Skeleton3D.new();skeleton.name="Rig";model.add_child(skeleton);skeleton.add_bone("fixation")
	var rest := Transform3D(Basis.IDENTITY,Vector3(-.35,.8,.12));skeleton.set_bone_rest(0,rest);skeleton.set_bone_pose_position(0,rest.origin)
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.09,-.09,0),Vector3(.09,-.09,0),Vector3(0,.1,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]);arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1]);arrays[Mesh.ARRAY_BONES]=PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0]);arrays[Mesh.ARRAY_WEIGHTS]=PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0])
	var mesh := MeshInstance3D.new();mesh.name="SupportSkinned";var geometry := ArrayMesh.new();geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.mesh=geometry
	mesh.material_override=load("res://scripts/psx_materials.gd").make(Color(.6,.6,.5));mesh.skeleton=NodePath("..");var skin := Skin.new();skin.add_named_bind(&"fixation",Transform3D.IDENTITY);mesh.skin=skin;skeleton.add_child(mesh)
	var attach := BoneAttachment3D.new();attach.name="Fixation";attach.bone_name="fixation";skeleton.add_child(attach)
	var socket: Node3D=part.get_node("PointInsertion");socket.owner=null;socket.reparent(attach,false);socket.position=Vector3(0,0,.08)
	var area: Area3D=part.selection_area();area.owner=null;area.reparent(attach,false);area.position=Vector3(0,0,.08)
	part.placement_socket_path=part.get_path_to(socket);part.installed_visual_path=part.get_path_to(socket.get_node("PieceInstallee"));part.selection_area_path=part.get_path_to(area)
	part.highlight_paths.assign([part.get_path_to(mesh)])
	var animation := Animation.new();animation.length=.8;var track := animation.add_track(Animation.TYPE_POSITION_3D);animation.track_set_path(track,NodePath("Rig:fixation"));animation.position_track_insert_key(track,0,rest.origin);animation.position_track_insert_key(track,.8,rest.origin+Vector3(.12,0,0))
	var player := AnimationPlayer.new();player.name="AnimationRig";model.add_child(player);var library := AnimationLibrary.new();library.add_animation(&"installer",animation);player.add_animation_library(&"",library)
	part.animation_player_path=part.get_path_to(player);part.installation_animation=&"installer"
	return value
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("Placement validation timed out");quit(2))
	root.size=Vector2i(320,240);inventory=root.get_node("InventoryState");inventory.persist_collection=false;world=root.get_node("WorldEvents");world.reset_run()
	game=load("res://scenes/main.tscn").instantiate()
	for area in game.find_children("*","Area3D",true,false):
		if area is DialogueTrigger3D or area is CinematicTrigger3D:area.enabled=false
	root.add_child(game);game.pickup_feedback.enabled=false;game.set_process(false)
	game.player.set_process(false);game.player.set_physics_process(false);game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	manager=game.item_placement
	for id: StringName in [&"valve_wheel",&"lever_handle",&"fuse_16a"]:inventory.give(inventory.resolve_item(id),1,{},false)
	var scene: Node3D=load("res://scenes/inventory/placement_assembly.tscn").instantiate();scene.interaction_id=&"test.assembly";game.level.add_child(scene);scene.position=Vector3(1000,0,1000)
	var wheel: Node3D=scene.get_node("Emplacements/Roue");var lever: Node3D=scene.get_node("Emplacements/Levier")
	game.psx_renderer.ambient_light_color=Color(.8,.8,.8)
	await physics_frame;await settle()
	check(scene.configuration_error().is_empty(),"Multi-socket scene is configured")
	check(not wheel.can_interact() and not lever.can_interact() and scene.can_interact(),"Only the scene root offers E; children are picked inside its inspection view")
	check(wheel._id()!=lever._id() and String(wheel._id()).begins_with("test.assembly."),"Child state derives stable independent IDs from the map instance")
	check(scene.interact(game.player),"E opens the assembly scene");manager.set_process(false)
	check(manager.phase==manager.Phase.INSPECTING and not manager.menu.canvas.visible and not paused,"Inspection opens before the inventory without freezing the world")
	var atlas: int=game.psx_renderer.atlas_texture.get_instance_id()
	move(Vector2(10,10));await physics_frame;await settle();var idle: Image=await capture("idle")
	move(point(wheel));await physics_frame;await settle()
	check(manager.hovered==wheel and manager.inspection.selected==wheel,"Real pointer movement picks the visible left socket")
	var highlighted: Image=await capture("hover")
	var changed_pixels := 0
	for y in 240:
		for x in 320:
			if idle.get_pixel(x,y)!=highlighted.get_pixel(x,y):changed_pixels+=1
	check(changed_pixels>30 and not game.psx_renderer._hover_unlit_ids.is_empty(),"Selected visible mesh is rendered unlit in the native PSX image")
	check(manager.inspection.find_children("*","SubViewport",true,false).is_empty(),"Hover no longer creates a silhouette mask or a 2D outline")
	click(point(wheel));await physics_frame;await settle()
	check(game.psx_renderer._hover_unlit_ids.is_empty(),"Opening the item picker restores the normal surface lighting")
	check(manager.phase==manager.Phase.CHOOSING and manager.target==wheel and manager.menu.canvas.visible,"A real click opens the inventory for that specific socket")
	check(manager.menu.entries.size()==3,"All owned placable items remain available, including wrong choices")
	check(manager.menu.panel.get_global_rect().position.y>=150 and Rect2(Vector2.ZERO,Vector2(320,240)).encloses(manager.menu.panel.get_global_rect()),"Bottom inventory panel stays wholly inside the PSX frame")
	check(manager.menu.grid.columns==manager.menu.entries.size(),"Items use exactly one horizontal row")
	await capture("inventory")
	# More than one screen of objects must scroll horizontally, never wrap/crop.
	for index in 10:
		var extra: Resource=load("res://scripts/inventory/item_definition.gd").new();extra.id=StringName("test.part.%d" % index);extra.display_name="Piece %d" % index;extra.kind=8;extra.placeable=true
		check(inventory.give(extra,1,{},false),"Extra placable item fits the test inventory")
	await settle();var scroll: ScrollContainer=manager.menu.grid.get_parent()
	check(scroll.get_h_scroll_bar().visible and manager.menu.grid.size.y==32,"Long inventories stay on one row with a horizontal scrollbar")
	scroll.scroll_horizontal=10000;await settle();var last: Control=manager.menu.grid.get_child(manager.menu.grid.get_child_count()-1)
	check(last.get_global_rect().end.x<=scroll.get_global_rect().end.x+.1 and last.get_global_rect().position.x>=scroll.get_global_rect().position.x,"Last slot can be reached entirely inside the bottom strip")
	await capture("inventory-scroll")
	for index in 10:inventory.remove_item(StringName("test.part.%d" % index),1)
	manager.back();await settle();check(manager.phase==manager.Phase.INSPECTING and not manager.menu.canvas.visible,"Back closes the item strip and returns to part selection")
	# An occluding wall must prevent picking and drawing through it.
	var blocker := StaticBody3D.new();var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(.5,.5,.1);shape.shape=box;blocker.add_child(shape);scene.add_child(blocker);blocker.global_position=wheel.selection_area().global_position+Vector3(0,0,.45)
	await physics_frame;await physics_frame;move(point(wheel));await physics_frame;await settle()
	check(manager.hovered==null,"A wall in front of a socket blocks pointer selection")
	blocker.queue_free();await physics_frame;await physics_frame
	# Wrong item dialogue returns to this same socket, without consuming it.
	manager.select_part(wheel);manager.choose(uid(&"lever_handle"));game.dialogue.set_process(false)
	for tick in 500:
		if not manager._wrong_pending:break
		game.dialogue._process(.1)
	check(manager.target==wheel and manager.menu.canvas.visible and inventory.count(&"lever_handle")==1,"Wrong-item random reply keeps the chosen socket and every object")
	manager.choose(uid(&"valve_wheel"));manager._process(.7)
	check(manager.phase==manager.Phase.INSPECTING and world.interaction_used(wheel._id()) and not world.interaction_used(lever._id()),"First installation returns to inspection while the other part remains missing")
	check(not world.interaction_used(scene._id()) and inventory.count(&"valve_wheel")==0,"Whole mechanism is not complete before every socket is filled")
	await physics_frame;move(point(wheel));await physics_frame;await settle();check(manager.hovered==null,"Already installed socket is no longer selectable")
	manager.cancel();check(not game.player.controls_blocked and game.state=="playing","Closing a partially completed assembly returns normal controls")
	var saved: Dictionary=world.snapshot()
	check(scene.interact(game.player),"Partially installed scene can be inspected again");manager.set_process(false)
	move(point(lever));await physics_frame;await settle();check(manager.hovered==lever,"Right socket remains independently selectable")
	manager.select_part(lever);manager.choose(uid(&"lever_handle"));manager._process(.7)
	check(not manager.is_active() and world.interaction_used(scene._id()) and inventory.count(&"lever_handle")==0,"Last piece completes the assembly and returns the gameplay camera")
	check(game.psx_renderer.atlas_texture.get_instance_id()==atlas,"Hovering, selecting and inserting never rebuild texture pages")
	world.restore(saved);await settle(5)
	check(wheel.prepare_piece().visible and not lever.prepare_piece().visible and scene.can_interact(),"Partial save restores each socket independently")
	# Shared skinned body, external bone socket and animation outside the part.
	inventory.give(inventory.resolve_item(&"valve_wheel"),1,{},false)
	var rigged := rigged_scene();game.level.add_child(rigged);rigged.position=Vector3(1005,0,1000);await settle()
	var rig_part: Node3D=rigged.get_node("Emplacements/Roue");var skeleton: Skeleton3D=rigged.get_node("Modele/Rig");var initial := skeleton.get_bone_pose(0)
	check(rigged.configuration_error().is_empty() and rigged.interact(game.player),"Rigged assembly can inspect a piece attached outside the part subtree");manager.set_process(false)
	move(point(rig_part));await physics_frame;await settle();check(manager.hovered==rig_part,"Bone-attached selection zone follows its socket")
	await capture("rigged-hover");check(game.psx_renderer._hover_unlit_ids.has(rigged.get_node("Modele/Rig/SupportSkinned").get_instance_id()),"The selected skinned support uses real unlit rendering on its posed geometry")
	manager.select_part(rig_part);manager.choose(uid(&"valve_wheel"));manager._process(.7);manager._process(.4);manager.cancel()
	check(skeleton.get_bone_pose(0).is_equal_approx(initial) and inventory.count(&"valve_wheel")==1,"Cancelling restores the shared rig, including bones outside the selected part")
	rigged.interact(game.player);manager.set_process(false);manager.select_part(rig_part);manager.choose(uid(&"valve_wheel"));manager._process(.7);manager._process(1)
	check(world.interaction_used(rigged._id()) and absf(skeleton.get_bone_pose_position(0).x-(initial.origin.x+.12))<.001,"Shared rig reaches its authored installed pose")
	check(rig_part.prepare_piece().global_transform.is_equal_approx(rig_part.socket_node().global_transform*rig_part._piece_final),"Installed piece follows the animated bone in the shared model")
	saved=world.snapshot();skeleton.set_bone_pose_position(0,Vector3.ZERO);world.restore(saved);await settle(5)
	check(absf(skeleton.get_bone_pose_position(0).x-(initial.origin.x+.12))<.001 and rig_part.prepare_piece().visible,"World restore samples the shared rig's installed pose without replaying gameplay")
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await create_timer(.15).timeout
	FileAccess.open("res://docs/placement-hotspots-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"errors":failures,"highlight_changed_pixels":changed_pixels},"\t"))
	print("PLACEMENT_HOTSPOTS_OK " if failures.is_empty() else "PLACEMENT_HOTSPOTS_FAILED ",str(failures));quit(0 if failures.is_empty() else 1)
