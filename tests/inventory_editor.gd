@tool
extends RefCounted
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func run(plugin: EditorPlugin) -> void:
	check(Engine.is_editor_hint(),"Inventory authoring is checked in the real editor")
	var tree := plugin.get_tree()
	var level: Node3D=load("res://scenes/examples/inventory_demo.tscn").instantiate(); tree.root.add_child(level)
	for frame in 8: await tree.process_frame
	var pickup: Node3D=level.get_node("Objet_medkit"); var card: Node3D=level.get_node("Carte_1")
	var station: Node3D=level.get_node_or_null("MecanismeObjet")
	if not station:station=level.get_node("PlacementVanne")
	check(station.use_selection_view and station.get_node(station.camera_path) is Camera3D and station.get_node(station.placement_start_path) is Marker3D,"Existing station inherits editable fixed camera and insertion markers")
	var station_visibility: bool=station.get_node(station.installed_visual_path).visible
	check(station.prepare_piece().visible==station_visibility and not station._initial_pose,"Editor authoring preserves the artist's piece visibility and never runs the installation")
	var template: Node3D=load("res://scenes/inventory/placement_target.tscn").instantiate();tree.root.add_child(template)
	var socket: Node3D=template.get_node("Emplacements/Emplacement")
	var station_fields: Array[String]=[]
	for field in socket.get_property_list():
		if int(field.usage)&PROPERTY_USAGE_EDITOR:station_fields.append(field.name)
	for field in ["required_item","placement_socket_path","placement_start_path","wrong_item_dialogue","animation_player_path","installation_animation","placement_duration","consume_item","actions","selection_area_path","highlight_paths","selection_label"]:
		check(field in station_fields,"Inspector exposes placement setting: "+field)
	check(socket.get_node("PointInsertion") is Marker3D and template.get_node("Modele") is Node3D and template.get_node(template.camera_path) is Camera3D,"Reusable template has a model holder, scene camera and editable per-socket attachment point")
	check(socket.get_node(socket.installed_visual_path).name==&"PieceInstallee" and socket.get_node(socket.installed_visual_path).visible,"Default template uses a real visible scene branch for authoring the installed piece")
	check(socket.selection_area().get_node("Volume").shape is BoxShape3D,"Selectable socket has a visible editable box volume in the editor")
	var assembly: Node3D=load("res://scenes/inventory/placement_assembly.tscn").instantiate();tree.root.add_child(assembly)
	check(assembly.placement_targets().size()==2 and assembly.configuration_error().is_empty(),"Complete multi-socket scene has two editable independent part definitions")
	assembly.queue_free()
	check(load("res://assets/inventory/items/valve_wheel.tres").can_place() and load("res://assets/inventory/items/lever_handle.tres").can_place() and not load("res://assets/inventory/items/medkit.tres").can_place(),"Mechanisms and opt-in tools are placable; ordinary supplies stay out of the picker")
	template.queue_free()
	var authored: Node3D=load("res://scenes/inventory/placement_valve.tscn").instantiate();tree.root.add_child(authored)
	var piece: Node3D=authored.get_node(authored.installed_visual_path);var authored_transform := piece.transform
	check(authored.configuration_error().is_empty() and piece.is_visible_in_tree() and authored.has_visible_model(),"Complete placement example shows real support and piece models without launching gameplay")
	check(authored.prepare_piece()==piece and piece.visible and not authored._piece and not authored._initial_pose,"Editor inspection preserves authored geometry, visibility and poses")
	var author_animation: AnimationPlayer=authored.animation_source();author_animation.play(authored.installation_animation);author_animation.advance(.65)
	check(absf(piece.rotation.z-PI/2)<.001,"Real scene AnimationPlayer previews the piece animation in the editor")
	author_animation.stop(true);piece.transform=authored_transform
	var previous_scene=plugin.active_scene;var previous_settings=plugin.settings_node
	plugin.active_scene=authored;plugin.settings_node=null;var inspection: Dictionary=plugin._settings()
	plugin.active_scene=previous_scene;plugin.settings_node=previous_settings
	check(inspection.ambient_light_color==Color(.6,.6,.6) and not inspection.fog_enabled,"Standalone placement-scene preview stays readable without adding lights or level settings to its saved scene")
	var authored_buffer := SubViewport.new();authored_buffer.size=Vector2i(320,240);authored_buffer.own_world_3d=true;authored_buffer.world_2d=World2D.new();authored_buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;tree.root.add_child(authored_buffer)
	var authored_camera := Camera3D.new();authored_buffer.add_child(authored_camera);authored_camera.global_position=Vector3(.7,1.1,1.7);authored_camera.look_at(Vector3(0,.55,0));authored_camera.fov=45
	var authored_renderer: Node=load("res://scripts/psx_renderer.gd").new();authored_buffer.add_child(authored_renderer)
	for property in inspection:authored_renderer.set(property,inspection[property])
	authored_renderer.setup_editor(authored,authored_camera);authored_renderer.render_editor()
	await tree.process_frame;await RenderingServer.frame_post_draw
	var authored_image := authored_buffer.get_texture().get_image();authored_image.resize(960,720,Image.INTERPOLATE_NEAREST);authored_image.save_png("res://docs/placement-scene-editor.png")
	check(authored_renderer.triangle_count>100,"Standalone placement scene renders its actual meshes through the PSX preview")
	var authored_pack := PackedScene.new();check(authored_pack.pack(authored)==OK,"Placement authored as an ordinary scene can be saved")
	var authored_file := "user://placement_scene_validation.tscn";check(ResourceSaver.save(authored_pack,authored_file)==OK,"Placement scene saves with its authored content")
	var authored_saved: Node3D=load(authored_file).instantiate();tree.root.add_child(authored_saved)
	check(authored_saved.get_node(authored_saved.installed_visual_path).visible and authored_saved.animation_source().has_animation(authored_saved.installation_animation),"Saved scene retains piece visibility, relative references and animation for future map instances")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(authored_file));authored_saved.queue_free();authored_buffer.queue_free();authored.queue_free();await tree.process_frame
	check(pickup.get_script().is_tool() and pickup._visual.get_child_count()>0,"Item pickup is visible and editable without running the game")
	check(card._visual.get_child_count()==2 and is_equal_approx(card._visual.get_child(0).mesh.size.y,.3),"Card front/back preview remains at its authored 30 cm size")
	var card_field := {}
	for property in card.get_property_list():
		if property.name=="card_id": card_field=property
	check(card_field.get("hint",0)==PROPERTY_HINT_ENUM and String(card_field.get("hint_string","")).split(",").size()==15,"All fifteen cards are offered in the inspector dropdown")
	var definition: Resource=pickup.item.duplicate(); definition.kind=definition.Kind.DOCUMENT
	var fields: Array[String]=[]
	for field in definition.get_property_list():
		if int(field.usage)&PROPERTY_USAGE_EDITOR: fields.append(field.name)
	check("document_text" in fields and "use_actions" in fields and not "weapon" in fields,"Item type reveals relevant document and world action fields")
	var buffer := SubViewport.new(); buffer.size=Vector2i(320,240); buffer.own_world_3d=true; buffer.world_2d=World2D.new(); buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS; tree.root.add_child(buffer)
	var camera := Camera3D.new(); buffer.add_child(camera)
	camera.global_position=Vector3(4,1.4,5); camera.look_at(Vector3(4,.3,2)); camera.fov=60
	var renderer: Node=load("res://scripts/psx_renderer.gd").new(); buffer.add_child(renderer)
	renderer.ambient_light_color=Color(.4,.4,.4); renderer.setup_editor(level,camera); renderer.render_editor()
	await tree.process_frame; await RenderingServer.frame_post_draw
	buffer.get_texture().get_image().save_png("res://docs/inventory-editor-preview.png")
	check(renderer.native_geometry!=null and renderer.triangle_count>100,"Inventory demo and cards render with the native PSX editor renderer")
	var card_surfaces := 0
	for entry in renderer.entries:
		if card.is_ancestor_of(entry.node):
			card_surfaces+=1; check(not entry.fixed and not entry.light_occluder,"Spinning card stays dynamic without rebuilding the world light occluders")
	check(card_surfaces==2,"Both card faces retain their supplied textures in native geometry")
	camera.global_position=card.global_position+Vector3(0,.4,.7); camera.look_at(card.global_position+Vector3.UP*.21); camera.fov=50
	renderer.render_editor(); await tree.process_frame; await RenderingServer.frame_post_draw
	buffer.get_texture().get_image().save_png("res://docs/inventory-card-world.png")
	var packed := PackedScene.new(); check(packed.pack(level)==OK,"Inventory placements serialize as ordinary scene instances")
	var path := "user://inventory-editor-validation.tscn"
	check(ResourceSaver.save(packed,path)==OK,"Inventory scene can be saved")
	var saved := FileAccess.get_file_as_string(path)
	check(saved.contains("key_archives.tres") and saved.contains("card_id =") and saved.contains("required_item_id"),"Saving retains exact item IDs, selected cards and door requirements")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var result := {"ok":errors.is_empty(),"errors":errors,"card_surfaces":card_surfaces,"triangles":renderer.triangle_count}
	FileAccess.open("res://docs/inventory-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	buffer.queue_free(); level.queue_free(); await tree.process_frame
	for frame in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.process_frame
	print("INVENTORY_EDITOR_OK " if errors.is_empty() else "INVENTORY_EDITOR_FAILED ",JSON.stringify(result)); tree.quit(0 if errors.is_empty() else 1)
