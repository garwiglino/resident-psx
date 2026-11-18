extends RefCounted
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)
func settle(plugin: EditorPlugin, frames := 8) -> void:
	for frame in frames: await plugin.get_tree().process_frame
func click_plan(plugin: EditorPlugin, from: Vector2, to: Vector2) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT
	event.position=plugin.plan.to_screen(from); event.pressed=true; plugin.plan._gui_input(event)
	var motion := InputEventMouseMotion.new(); motion.position=plugin.plan.to_screen(to); motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	plugin.plan._gui_input(motion)
	event.position=motion.position; event.pressed=false; plugin.plan._gui_input(event)
func run(plugin: EditorPlugin) -> void:
	await settle(plugin,40)
	check(plugin.panel.is_inside_tree(),"Map painting dock is installed")
	var path := "res://exports/modular/editor_roundtrip.tscn"
	plugin.create_map_at(path); await settle(plugin,30)
	var map: Node3D=EditorInterface.get_edited_scene_root()
	check(map is ModularMap3D,"New map opens in the editor")
	if not map is ModularMap3D: plugin.get_tree().quit(1); return
	plugin._set_map(map); plugin.dock.make_visible(); await settle(plugin)
	click_plan(plugin,Vector2(.2,.2),Vector2(2.8,2.8)); await settle(plugin)
	check(map.layout.cells.size()==9,"Actual plan mouse drag paints a 3x3 room")
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(map))
	check(history.has_undo(),"Paint stroke recorded in the scene undo history")
	history.undo(); await settle(plugin)
	check(map.layout.cells.is_empty(),"Undo removes the complete room")
	history.redo(); await settle(plugin)
	check(map.layout.cells.size()==9,"Redo restores the complete room")
	plugin.room_id=0
	click_plan(plugin,Vector2(3.2,.2),Vector2(5.8,2.8)); await settle(plugin)
	check(map.layout.cells.size()==18 and map.layout.rooms.size()==2,"Adjacent rooms retain separate identities")
	check(map.layout.effective_edges().size()==21,"Shared partition generated exactly once")
	plugin._buttons[3].pressed.emit()
	click_plan(plugin,Vector2(3.02,1.5),Vector2(3.02,1.5)); await settle(plugin)
	check(map.layout.edges.get("v:3:1",{}).get("kind",-1)==2,"Door tool paints a real partition edge")
	plugin._set_mode(7);click_plan(plugin,Vector2(3.02,1.5),Vector2(3.02,1.5));await settle(plugin)
	plugin.fields["required_item_id"].text="key_archives";plugin.fields["required_item_id"].text_submitted.emit("key_archives");await settle(plugin)
	var replies: Resource=load("res://assets/audio/dialogs/locked_doors_key/locked_doors_key.tres")
	plugin.reply_picker.edited_resource=replies;plugin.reply_picker.resource_changed.emit(replies);await settle(plugin)
	check(map.layout.edges["v:3:1"].get("locked_dialogue_pool")==replies,"The map dock accepts an existing DialogueSequence as a random line bank")
	var door: Node=map.generated.get_node("Bord_v_3_1/Porte")
	check(door.required_item_id==&"key_archives" and door.locked_dialogue_pool==replies and door.locked_dialogue_enabled,"Generated door receives its key and dialogue settings")
	plugin.fields["locked_dialogue_enabled"].button_pressed=false;await settle(plugin)
	check(not map.generated.get_node("Bord_v_3_1/Porte").locked_dialogue_enabled,"Door checkbox disables its replies in the generated map")
	history.undo();await settle(plugin)
	check(map.generated.get_node("Bord_v_3_1/Porte").locked_dialogue_enabled,"Undo restores the door's dialogue settings")
	plugin._buttons[4].pressed.emit(); plugin.variants.select(1)
	click_plan(plugin,Vector2(5.98,1.5),Vector2(5.98,1.5)); await settle(plugin)
	check(map.layout.edges.get("v:6:1",{}).get("variant","")=="boarded","Window selector uses the authored boarded panel")
	plugin._buttons[5].pressed.emit();click_plan(plugin,Vector2(3.02,2.5),Vector2(3.02,2.5));await settle(plugin)
	check(map.layout.edges["v:3:2"].kind==0 and not map.generated.has_node("Bord_v_3_2"),"Passage tool removes the wall and its collision without invalid kit calls")
	history.undo();await settle(plugin)
	check(map.generated.has_node("Bord_v_3_2"),"Undo restores the passage wall")
	history.redo();await settle(plugin)
	check(not map.generated.has_node("Bord_v_3_2"),"Redo opens the passage again")
	plugin._buttons[1].pressed.emit(); plugin.paint_3d.button_pressed=true
	var camera := Camera3D.new(); map.add_child(camera)
	camera.position=Vector3(6,15,14); camera.look_at(Vector3(6,0,4))
	var at := camera.unproject_position(Vector3(13,0,1))
	var mouse := InputEventMouseButton.new(); mouse.button_index=MOUSE_BUTTON_LEFT; mouse.position=at; mouse.pressed=true
	check(plugin._forward_3d_gui_input(camera,mouse)==plugin.AFTER_GUI_INPUT_STOP,"3D painting captures an authorized left click")
	mouse.pressed=false; plugin._forward_3d_gui_input(camera,mouse); await settle(plugin)
	check(map.layout.cells.has(Vector2i(6,0)),"3D ray paints the expected 2 m cell")
	mouse.button_index=MOUSE_BUTTON_RIGHT; mouse.pressed=true
	check(plugin._forward_3d_gui_input(camera,mouse)==plugin.AFTER_GUI_INPUT_PASS,"Editor camera navigation remains available")
	camera.free()
	plugin.begin_stroke(Vector3(15,0,1)); plugin.cancel_stroke(); await settle(plugin)
	check(not map.layout.cells.has(Vector2i(7,0)),"Escape cancellation restores the complete previous plan")
	EditorInterface.save_scene(); await settle(plugin)
	check(FileAccess.get_file_as_string(path).length()<12000,"Editor scene stays small without embedded mesh data")
	var saved: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	var instance: Node3D=saved.instantiate()
	check(instance.layout.cells==map.layout.cells and instance.layout.edges==map.layout.edges,"Editor save preserves cells and portal options")
	check(instance.layout.edges["v:3:1"].locked_dialogue_pool.resource_path==replies.resource_path,"Saving the map preserves its external dialogue bank reference")
	instance.free()
	await verify_storeys(plugin,map,history)
	# Capture the actual native PSX editor preview with temporary review lighting.
	# The saved fixture and the artist's level keep their authored lighting.
	map.show_ceilings_in_editor=false;map.show_other_storeys_in_editor=false
	var atmosphere: Node=map.get_node("ReglagesNiveau")
	atmosphere.ambient_light_color=Color(.65,.65,.65);atmosphere.fog_enabled=false
	plugin._set_mode(4); plugin.plan.fit()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(map)
	var driver: Node=load("res://tools/validate_editor_preview.gd").new(); plugin.add_child(driver)
	driver.process_priority=999
	driver.forced_camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	driver.forced_transform=Transform3D(Basis.IDENTITY,Vector3(15,14,16)).looking_at(Vector3(6,0,3))
	for candidate: Node in plugin.get_tree().root.find_children("*","EditorPlugin",true,false):
		if candidate.get_script() and candidate.get_script().resource_path=="res://addons/psx_viewport/plugin.gd":
			candidate._settings(); candidate.main_settings["ambient_light_color"]=Color(.65,.65,.65)
			candidate.main_settings["fog_start"]=30.0; candidate.main_settings["fog_end"]=50.0
	await settle(plugin,20)
	await RenderingServer.frame_post_draw
	for candidate: Node in plugin.get_tree().root.find_children("*","EditorPlugin",true,false):
		if candidate.get_script() and candidate.get_script().resource_path=="res://addons/psx_viewport/plugin.gd" and candidate.views.has(0):
			check(candidate.views[0].renderer.triangle_count>0,"Generated multi-storey map reaches the native PSX editor rasterizer")
			var preview: Image=candidate.views[0].buffer.get_texture().get_image()
			var lit := 0
			for y in range(0,preview.get_height(),4):
				for x in range(0,preview.get_width(),4):
					if preview.get_pixel(x,y).v>.2:lit+=1
			check(lit>100,"Editor cutaway contains visible textured geometry under review lighting")
	var image: Image=EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png("res://docs/modular-map-editor.png")
	driver.free()
	var result := {"ok":failures.is_empty(),"cells":map.layout.cells.size(),"edges":map.layout.effective_edges().size(),"errors":failures}
	var file := FileAccess.open("res://docs/modular-map-editor-validation.json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	print("MODULAR_MAP_EDITOR_OK " if failures.is_empty() else "MODULAR_MAP_EDITOR_FAILED ",JSON.stringify(result))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)

func verify_storeys(plugin: EditorPlugin,map: Node3D,history: UndoRedo) -> void:
	var initial_edges: int=map.layout.effective_edges().size()
	plugin._buttons[1].pressed.emit()
	click_plan(plugin,Vector2(10.2,5.2),Vector2(13.8,5.2));await settle(plugin)
	check(map.layout.effective_edges().size()==initial_edges,"Sol drag adds no automatic walls")
	for x in range(10,14):check(map.layout.has_floor(Vector2i(x,5)) and map.layout.floor_only.has(Vector2i(x,5)),"Fast floor drag covers every crossed cell")
	var count: int=map.layout.cells.size()
	plugin._buttons[2].pressed.emit();click_plan(plugin,Vector2(10.2,7.01),Vector2(13.8,7.01));await settle(plugin)
	check(map.layout.cells.size()==count,"Mur drag creates no floors")
	for x in range(10,14):check(map.layout.effective_edges().has("h:%d:7" % x),"Fast wall drag covers each border even without a floor")
	history.undo();await settle(plugin)
	check(not map.layout.effective_edges().has("h:11:7"),"One undo removes the whole wall stroke")
	history.redo();await settle(plugin)
	plugin.add_storey(1);await settle(plugin)
	check(plugin.current_level()==1 and map.layout.level_ids()==[0,1],"Add storey selects a separate upper plan")
	plugin._buttons[1].pressed.emit();click_plan(plugin,Vector2(1.2,2.2),Vector2(2.8,3.8));await settle(plugin)
	check(map.layout.cells_at(1).size()==2 and map.layout.effective_edges(1).is_empty(),"Upper floor paint stays independent of the ground floor")
	var camera := Camera3D.new();map.add_child(camera);camera.position=Vector3(6,16,14);camera.look_at(Vector3(6,3,4))
	var mouse := InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.position=camera.unproject_position(Vector3(13,3,1));mouse.pressed=true
	plugin._forward_3d_gui_input(camera,mouse);mouse.pressed=false;plugin._forward_3d_gui_input(camera,mouse);await settle(plugin)
	check(map.layout.has_floor(Vector2i(6,0),1) and is_equal_approx(plugin._point(camera,mouse.position).y,3),"3D painting projects onto the selected storey at Y=3")
	camera.free()
	plugin._buttons[9].pressed.emit();click_plan(plugin,Vector2(1.5,2.5),Vector2(1.5,2.5));await settle(plugin)
	check(not map.layout.has_floor(Vector2i(1,2),1) and not map.layout.has_ceiling(Vector2i(1,2)),"Tremie tool opens the upper floor and ceiling below")
	history.undo();await settle(plugin)
	check(map.layout.has_floor(Vector2i(1,2),1) and map.layout.has_ceiling(Vector2i(1,2)),"Undo restores a stair opening across both storeys")
	plugin._buttons[3].pressed.emit();click_plan(plugin,Vector2(1.5,2.01),Vector2(1.5,2.01));await settle(plugin)
	plugin._buttons[7].pressed.emit();click_plan(plugin,Vector2(1.5,2.01),Vector2(1.5,2.01));await settle(plugin)
	plugin.lock_modes.item_selected.emit(2);await settle(plugin)
	var door: Node=map.generated.get_node("Etage_1/Bord_h_1_2/Porte")
	check(door.permanently_locked and door.required_item_id==&"" and not plugin.fields["required_item_id"].visible,"Door inspector supports a permanent lock without a key")
	check(door.permanent_dialogue_pool.resource_path.ends_with("/locked_doors/locked_doors.tres"),"Permanent mode uses locked_doors.tres")
	plugin.lock_modes.item_selected.emit(0);await settle(plugin)
	check(not map.generated.get_node("Etage_1/Bord_h_1_2/Porte").permanently_locked,"Switching back to free removes the permanent lock")
	history.undo();await settle(plugin)
	check(map.generated.get_node("Etage_1/Bord_h_1_2/Porte").permanently_locked,"Door lock mode participates in scene undo")
	var stairs: Node3D=load("res://assets/props/stairs_01/stairs_01.tscn").instantiate();stairs.name="EscalierTest";map.add_child(stairs);stairs.owner=map;stairs.position=Vector3(4,0,8)
	EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(stairs);await settle(plugin)
	check(plugin.stair_opening.visible,"Selecting an exported staircase exposes the stairwell command")
	plugin.stair_opening.pressed.emit();await settle(plugin)
	check(map.layout.layer(1).floor_holes.size()==4,"Stairwell command cuts the actual transformed 2 by 4 m staircase footprint")
	check(not map.layout.has_ceiling(Vector2i(1,2)),"Stairwell command removes the ceiling below too")
	history.undo();await settle(plugin)
	check(map.layout.layer(1).floor_holes.is_empty(),"Stairwell cut can be undone in one action")
	plugin.add_storey(-1);await settle(plugin)
	check(plugin.current_level()==-1,"Basement selector handles negative storey IDs")
	plugin._buttons[8].pressed.emit();click_plan(plugin,Vector2(9.5,2.5),Vector2(9.5,2.5));await settle(plugin)
	check(map.layout.has_ceiling(Vector2i(9,2),-1) and not map.layout.has_floor(Vector2i(9,2),-1),"Ceiling tool paints independently in the basement")
	plugin.select_storey(0);await settle(plugin)
	check(not map.generated.get_node("Etage_1").visible and map.generated.get_node("Bord_v_3_1").visible,"Editor isolates the selected storey")
	plugin.other_storeys.button_pressed=true;await settle(plugin)
	check(map.generated.get_node("Etage_1").visible,"Other storeys checkbox restores the complete editor view")
	EditorInterface.save_scene();await settle(plugin)
	var saved: PackedScene=ResourceLoader.load("res://exports/modular/editor_roundtrip.tscn","PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	var restored: Node3D=saved.instantiate()
	check(restored.layout.snapshot()==map.layout.snapshot(),"Editor save preserves all storeys, openings and permanent door settings")
	restored.free()
