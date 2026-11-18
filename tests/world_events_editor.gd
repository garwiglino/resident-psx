@tool
extends RefCounted
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run(plugin: EditorPlugin) -> void:
	check(Engine.is_editor_hint(),"Validation uses actual editor/tool mode")
	var root := plugin.get_tree().root
	var buffer := SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	var map=load("res://scenes/couloir_pieces.tscn").instantiate();root.add_child(map)
	var holder: Node=map.get_node("Gameplay/Ennemis")
	check(holder.get_child_count()==4,"Four map enemy instances exist before launching gameplay")
	for enemy in holder.get_children():
		check(enemy.get_script().is_tool() and not enemy.is_physics_processing(),"Enemy preview is visible without AI running in the editor")
		check(enemy.find_children("*","MeshInstance3D",true,false).size()==12,"Editor preview includes the original low-poly silhouette")
		var fields: Array[String]=[]
		for field in enemy.get_property_list():
			if int(field.usage)&PROPERTY_USAGE_EDITOR:fields.append(field.name)
		check("enemy_id" in fields and "death_event" in fields and "death_actions" in fields,"Death event, actions and identity are exposed in the native inspector")
	var camera := Camera3D.new();buffer.add_child(camera)
	var target: Node3D=holder.get_child(0)
	camera.global_position=target.global_position+Vector3(.8,1.35,3.2);camera.look_at(target.global_position+Vector3(0,.9,0));camera.fov=48
	var renderer=load("res://scripts/psx_renderer.gd").new();buffer.add_child(renderer)
	renderer.ambient_light_color=Color(.5,.5,.5);renderer.setup_editor(map,camera);renderer.render_editor()
	await plugin.get_tree().process_frame;await plugin.get_tree().process_frame;await RenderingServer.frame_post_draw
	buffer.get_texture().get_image().save_png("res://docs/world-enemy-editor-preview.png")
	check(renderer.native_geometry!=null and renderer.triangle_count>100,"PSX editor preview renders the authored map and enemies")
	# Native scene serialization preserves their placement, IDs and direct action resources.
	var packed := PackedScene.new();check(packed.pack(map)==OK,"Map serializes with editor-placed enemies")
	check(ResourceSaver.save(packed,"user://world-events-map-validation.tscn")==OK,"Editable map instances save successfully")
	var saved := FileAccess.get_file_as_string("user://world-events-map-validation.tscn")
	check(saved.count('instance=ExtResource("')>=4 and saved.contains('enemy_id = &"couloir.archives"'),"Saving preserves enemy prefab instances and IDs")
	FileAccess.open("res://docs/world-events-editor-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"enemy_instances":holder.get_child_count(),"triangles":renderer.triangle_count},"\t"))
	buffer.queue_free();map.queue_free();await plugin.get_tree().process_frame
	for step in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning():break
		await plugin.get_tree().process_frame
	print("WORLD_EVENTS_EDITOR_OK: four editable enemy instances, visible tool previews, inspector death actions and scene serialization" if failures.is_empty() else "WORLD_EVENTS_EDITOR_FAILED "+str(failures))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
