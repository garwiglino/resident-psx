@tool
extends Node
var failures: Array[String]=[]
var report: Dictionary={}
var plugin: EditorPlugin
var forced_camera: Camera3D
var forced_transform := Transform3D(Basis.IDENTITY,Vector3(.5,1.4,5.8))
var forced_projection := Camera3D.PROJECTION_PERSPECTIVE
var forced_fov := 55.0
func _process(_delta: float) -> void:
	if is_instance_valid(forced_camera):
		forced_camera.global_transform=forced_transform;forced_camera.fov=forced_fov
		forced_camera.projection=forced_projection;forced_camera.size=6
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func settle(frames := 8) -> void:
	for frame in frames:await get_tree().process_frame
func capture(path: String) -> Image:
	EditorInterface.set_main_screen_editor("3D")
	await get_tree().create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	var image := EditorInterface.get_editor_viewport_3d(0).get_texture().get_image()
	image.save_png(path);return image
func run(owner_plugin: EditorPlugin) -> void:
	plugin=owner_plugin
	process_priority=999
	await settle(30)
	EditorInterface.open_scene_from_path("res://scenes/couloir_pieces.tscn")
	EditorInterface.set_main_screen_editor("3D")
	await settle(20)
	plugin.toggle.button_pressed=true
	var scene := EditorInterface.get_edited_scene_root()
	check(scene!=null,"Edited scene exists without running the project")
	check(not EditorInterface.is_playing_scene(),"No game process is launched")
	var source_file := scene.scene_file_path
	var before_hash := FileAccess.get_sha256(source_file)
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	var previous_transform := camera.global_transform
	var previous_fov := camera.fov;var previous_projection := camera.projection;var previous_size := camera.size
	var previous_mask := camera.cull_mask;var previous_environment := camera.environment
	var previous_max_fps := Engine.max_fps
	forced_camera=camera
	camera.global_transform=Transform3D(Basis.IDENTITY,Vector3(.5,1.4,5.8));camera.fov=55;camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	EditorInterface.get_selection().clear()
	await settle(20)
	check(plugin.views.has(0),"PSX view is installed inside the editor viewport")
	if not plugin.views.has(0):get_tree().quit(1);return
	var view=plugin.views[0]
	check(view.renderer.editor_preview and view.renderer.native_geometry!=null,"Same native rasterizer is used by editor preview")
	check(view.renderer.triangle_count>0,"Edited geometry reaches the PSX rasterizer")
	check(camera.cull_mask==previous_mask and camera.environment==previous_environment,"Camera properties remain available for normal picking and are not modified")
	check(view.renderer.get_viewport()!=viewport and view.buffer.disable_3d,"PSX framebuffer is separate from the editable 3D viewport")
	check(not viewport.disable_3d,"Editor gizmos keep their normal 3D rendering pass")
	var baseline: Image=await capture("res://docs/editor-preview-perspective.png")
	get_tree().root.get_texture().get_image().save_png("res://docs/editor-preview-editor-window.png")
	var pixel_buffer: Image=view.buffer.get_texture().get_image()
	pixel_buffer.save_png("res://docs/editor-preview-buffer.png")
	report.viewport_size=str(viewport.size);report.native_statistics=view.renderer.native_geometry.get_statistics()
	report.camera_mask=previous_mask
	report.render_rect=str(view.surface.frame_rect())
	# Compare the center of each upscaled texel with the native framebuffer.
	# Disable helper layers only for this pixel comparison, then restore them.
	camera.cull_mask=(1<<20)-1
	var plain: Image=await capture("res://docs/editor-preview-no-gizmos.png")
	pixel_buffer=view.buffer.get_texture().get_image()
	var rect: Rect2=view.surface.frame_rect();var maximum_error := 0.0
	for y in range(8,232,8):
		for x in range(8,312,8):
			var point := rect.position+(Vector2(x,y)+Vector2.ONE*.5)*rect.size/Vector2(320,240)
			var actual := plain.get_pixel(clampi(floori(point.x),0,plain.get_width()-1),clampi(floori(point.y),0,plain.get_height()-1))
			var expected := pixel_buffer.get_pixel(x,y)
			for channel in 3:maximum_error=maxf(maximum_error,absf(actual[channel]-expected[channel]))
	report.maximum_viewport_color_error=maximum_error
	check(maximum_error<.025,"Editor view preserves actual PSX framebuffer colors")
	camera.cull_mask=previous_mask
	var lamp: Node
	for source in get_tree().get_nodes_in_group("psx_world_lights"):
		if scene.is_ancestor_of(source):lamp=source;break
	if lamp:
		var old_color: Color=lamp.light_color;var old_energy: float=lamp.light_energy
		var old_position: Vector3=lamp.position
		EditorInterface.get_selection().add_node(lamp)
		EditorInterface.edit_node(lamp)
		lamp.light_color=Color(.15,.4,1);lamp.light_energy=3;lamp.position=Vector3(-.5,1.7,3)
		var relit: Image=await capture("res://docs/editor-preview-light-gizmo.png")
		get_tree().root.get_texture().get_image().save_png("res://docs/editor-preview-selected-window.png")
		check(relit.get_data()!=baseline.get_data(),"Light edits are visible immediately without play")
		var projected := camera.unproject_position(lamp.global_position)
		var raster_projected: Vector2=view.camera.unproject_position(lamp.global_position)
		var aligned: Vector2=view.surface.frame_rect().position+raster_projected*view.surface.frame_rect().size/Vector2(320,240)
		report.projection_alignment_error=projected.distance_to(aligned)
		check(projected.distance_to(aligned)<.1,"PSX projection aligns with the editor picking and manipulation projection")
		camera.cull_mask=(1<<20)-1
		var relit_plain: Image=await capture("res://docs/editor-preview-light-without-gizmos.png")
		check(relit.get_data()!=relit_plain.get_data(),"Selected object's actual editor gizmos remain visible above the PSX image")
		camera.cull_mask=previous_mask
		plugin.toggle.button_pressed=false
		await capture("res://docs/editor-preview-selected-standard.png")
		plugin.toggle.button_pressed=true
		lamp.light_color=old_color;lamp.light_energy=old_energy;lamp.position=old_position
	EditorInterface.get_selection().clear()
	# Add, move, edit and remove real geometry in the edited scene, without saving.
	var probe := MeshInstance3D.new();probe.mesh=BoxMesh.new();probe.mesh.size=Vector3.ONE*.4
	var material := StandardMaterial3D.new();material.albedo_color=Color.RED
	material.emission_enabled=true;material.emission=Color.RED;probe.material_override=material
	probe.position=Vector3(.5,1.4,3);scene.add_child(probe)
	var rebuilds_before: int=view.rebuilds
	var added: Image=await capture("res://docs/editor-preview-mesh-added.png")
	check(view.rebuilds>rebuilds_before,"Adding geometry refreshes the cached PSX mesh and atlas")
	probe.position.x+=.8
	var moved: Image=await capture("res://docs/editor-preview-mesh-moved.png")
	check(moved.get_data()!=added.get_data(),"Editor transforms update the PSX mesh immediately")
	rebuilds_before=view.rebuilds;material.albedo_color=Color.GREEN;material.emission=Color.GREEN
	EditorInterface.inspect_object(material);plugin._property_edited(&"albedo_color")
	var recolored: Image=await capture("res://docs/editor-preview-material-edited.png")
	check(recolored.get_data()!=moved.get_data() and view.rebuilds>rebuilds_before,"Material edits rebuild the texture and vertex color data")
	probe.free()
	await capture("res://docs/editor-preview-mesh-removed.png")
	for entry in view.renderer.entries:check(is_instance_valid(entry.node),"Removing geometry clears its native renderer reference")
	# Fog settings use the same inspector-backed main scene values.
	var settings_before: Dictionary=plugin.main_settings.duplicate()
	plugin.main_settings["fog_start"]=0.0;plugin.main_settings["fog_end"]=9.0;plugin.main_settings["fog_color"]=Color(.32,.4,.45)
	var fogged: Image=await capture("res://docs/editor-preview-fog.png")
	check(fogged.get_data()!=baseline.get_data(),"Native PSX depth cue updates in the editor")
	plugin.main_settings=settings_before
	forced_projection=Camera3D.PROJECTION_ORTHOGONAL
	await capture("res://docs/editor-preview-orthographic.png")
	check(view.renderer._orthographic_size>0 and view.renderer.triangle_count>0,"Orthographic editor views use the PSX rasterizer too")
	plugin.toggle.button_pressed=false
	await capture("res://docs/editor-preview-disabled.png")
	check(not view.background.visible,"Preview toggle restores the ordinary editor view")
	check(camera.cull_mask==previous_mask and camera.environment==previous_environment,"Disabling the preview preserves the editor camera settings")
	forced_camera=null
	camera.global_transform=previous_transform;camera.fov=previous_fov;camera.size=previous_size;camera.projection=previous_projection
	plugin.toggle.button_pressed=true
	EditorInterface.get_selection().clear()
	check(FileAccess.get_sha256(source_file)==before_hash,"Preview never saves or rewrites the edited scene")
	check(scene.find_children("*","AudioStreamPlayer",true,false).is_empty(),"Preview does not initialize gameplay audio")
	check(Engine.max_fps==previous_max_fps,"Editor preview never changes the editor frame limiter")
	# Verify the actual @tool controls on the player scene, still without playing.
	var player_path := "res://scenes/player.tscn"
	var player_hash := FileAccess.get_sha256(player_path)
	EditorInterface.open_scene_from_path(player_path);EditorInterface.set_main_screen_editor("3D")
	await settle(15)
	var edited_player := EditorInterface.get_edited_scene_root()
	var face=edited_player.get_node("Visage")
	var eyes_before: int=face.top_frame;var mouth_before: int=face.bottom_frame
	var player_camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var old_player_camera := player_camera.global_transform
	var old_player_fov := player_camera.fov;var old_player_projection := player_camera.projection
	forced_camera=player_camera;forced_projection=Camera3D.PROJECTION_PERSPECTIVE;forced_fov=25
	forced_transform=Transform3D(Basis(Vector3.UP,PI),Vector3(0,1.47,-.72))
	var face_settings: Dictionary=plugin.main_settings.duplicate()
	plugin.main_settings["ambient_light_color"]=Color(.8,.8,.8)
	plugin.main_settings["fog_start"]=30.0;plugin.main_settings["fog_end"]=40.0
	var player_mask := player_camera.cull_mask;player_camera.cull_mask=(1<<20)-1
	face.set_expression(0,0)
	var neutral: Image=await capture("res://docs/face-editor-neutral.png")
	face.set_expression(2,3)
	var expression: Image=await capture("res://docs/face-editor-expression.png")
	check(neutral.get_data()!=expression.get_data(),"Eyes and mouth inspector controls change the actual PSX editor viewport without play")
	check(not EditorInterface.is_playing_scene(),"Face preview never launches the game")
	# StandardMaterial3D must select the same poses when the PSX preview is off.
	# AtlasTexture.region is ignored by the standard 3D sampler: this catches it.
	plugin.toggle.button_pressed=false
	face.set_expression(0,0)
	var standard_neutral: Image=await capture("res://docs/face-editor-standard-neutral.png")
	face.set_expression(2,3)
	var standard_expression: Image=await capture("res://docs/face-editor-standard-expression.png")
	check(standard_neutral.get_data()!=standard_expression.get_data(),"Actual standard editor viewport samples different facial tiles when expressions change")
	for surface in face._surfaces:
		check(surface.material.albedo_texture is not AtlasTexture,"Standard 3D materials sample the original atlas with explicit UV transforms")
		check(surface.material.uv1_scale.is_equal_approx(Vector3(.25,.5,1)),"Standard editor selects one full 128x128 tile")
	face.set_expression(4,7)
	await capture("res://docs/face-editor-standard-anger.png")
	plugin.toggle.button_pressed=true
	face.set_expression(eyes_before,mouth_before);forced_camera=null
	plugin.main_settings=face_settings;player_camera.cull_mask=player_mask
	player_camera.global_transform=old_player_camera;player_camera.fov=old_player_fov;player_camera.projection=old_player_projection
	check(FileAccess.get_sha256(player_path)==player_hash,"Face preview never saves the player scene")
	report.failures=failures
	FileAccess.open("res://docs/editor-preview-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EDITOR_PREVIEW_OK: real 3D editor, native rendering, live lights/fog, gizmo pass, both projections, source preservation and no game launch" if failures.is_empty() else "EDITOR_PREVIEW_FAILED "+str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
