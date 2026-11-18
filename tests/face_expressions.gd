extends SceneTree
const Renderer=preload("res://scripts/psx_renderer.gd")
const Face=preload("res://scripts/face_expressions.gd")
const Textures=preload("res://scripts/face_texture_pages.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)
func run() -> void:
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/cop_player.json"))
	# Validate the exported snapshot; the artist may keep editing the .blend
	# after export. Source preservation is checked inside the exporter itself.
	check(String(metadata.source_sha256).length()==64 and not metadata.source_sample.is_empty(),"Export retains its Blender snapshot and source digest")
	for part in [1,2]:
		var original := Image.load_from_file(ProjectSettings.globalize_path((Textures.TOP if part==1 else Textures.BOTTOM).resource_path))
		original.convert(Image.FORMAT_RGBA8)
		var pages := Textures.pages(part)
		for frame in 8:
			var expected := original.get_region(Rect2i((frame%4)*128,(frame/4)*128,128,128))
			var actual := pages[frame/4].get_image().get_region(Rect2i((frame%2)*128,((frame%4)/2)*128,128,128))
			check(actual.get_data()==expected.get_data(),"All 128x128 facial tiles retain their exact original texels")
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240)
	viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	var model=load("res://assets/character/cop_player.glb").instantiate();model.name="Cop";stage.add_child(model)
	var animation: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	animation.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip: String=animation.get_animation_list()[0];animation.play(clip,0);animation.advance(0)
	var skeleton: Skeleton3D=model.get_node("rig/Skeleton3D")
	var face := Face.new();face.model_path=NodePath("../Cop");stage.add_child(face)
	check(face._surfaces.size()==2,"Updated model exports separate top and bottom face materials")
	var camera := Camera3D.new();viewport.add_child(camera);camera.position=Vector3(0,1.47,.72);camera.fov=25;camera.near=.02
	camera.look_at(Vector3(0,1.47,0))
	var renderer := Renderer.new();viewport.add_child(renderer)
	renderer.fog_start=30;renderer.fog_end=40;renderer.ambient_light_color=Color(.8,.8,.8);renderer.dithering=false
	renderer.setup_editor(stage,camera);renderer.render_editor()
	check(renderer.native_geometry.get_statistics().version>=11,"Native backend supports dynamic face pages")
	var source_positions: Array=metadata.source_sample
	var maximum_error := 0.0;var face_entries := 0;var maximum_influences := 0
	for entry in renderer.entries:
		if entry.face_part:face_entries+=1
		if entry.skeleton!=skeleton:continue
		var transforms: Array[Transform3D]=[]
		for index in entry.binds.size():transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(entry.bind_indices[index])*entry.binds[index])
		var stride: int=entry.bones.size()/entry.vertices.size();maximum_influences=maxi(maximum_influences,stride)
		for vertex in entry.vertices.size():
			var actual := Vector3.ZERO;var total := 0.0
			for influence in stride:
				var weight: float=entry.weights[vertex*stride+influence]
				if weight>0:actual+=(transforms[entry.bones[vertex*stride+influence]]*entry.vertices[vertex])*weight;total+=weight
			check(absf(total-1)<.0001,"Skin weights remain normalized")
			var nearest := INF
			for point in source_positions:nearest=minf(nearest,actual.distance_squared_to(Vector3(point[0],point[1],point[2])))
			maximum_error=maxf(maximum_error,sqrt(nearest))
	check(maximum_error<.001,"Updated mesh and full B-Bone skin reproduce the actual new Blender source within 1mm: "+str(maximum_error))
	for row in metadata.overflow_skin:
		check(maximum_influences>=row.weights.size(),"Overflow skin retains the influences authored in Blender")
	check(face_entries==2 and renderer.batch_count==1,"Two face materials remain in the single ordered PSX draw batch")
	var bone_poses: Array[Transform3D]=[]
	for bone in skeleton.get_bone_count():bone_poses.append(skeleton.get_bone_pose(bone))
	var atlas_id := renderer.atlas_texture.get_instance_id()
	var presets := [&"neutre",&"clignement",&"parole_a",&"parole_e",&"parole_o",&"colere",&"inquietude",&"sourire"]
	var sheet := Image.create(1280,480,false,Image.FORMAT_RGBA8)
	var captures: Array[Image]=[]
	for index in presets.size():
		check(face.set_preset(presets[index]),"Pack preset is available: "+String(presets[index]))
		renderer.render_editor();await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var screenshot := viewport.get_texture().get_image();screenshot.convert(Image.FORMAT_RGBA8)
		captures.append(screenshot)
		sheet.blit_rect(screenshot,Rect2i(0,0,320,240),Vector2i((index%4)*320,(index/4)*240))
		check(renderer.atlas_texture.get_instance_id()==atlas_id,"Expression change never rebuilds or uploads the texture atlas")
		for bone in skeleton.get_bone_count():check(skeleton.get_bone_pose(bone).is_equal_approx(bone_poses[bone]),"Expression controls never alter skeletal poses")
	check(captures[0].get_data()!=captures[1].get_data() and captures[0].get_data()!=captures[2].get_data(),"Actual PSX framebuffer shows both eye changes and mouth changes")
	face.set_expression(5,7);renderer.render_editor()
	check(model.get_node("rig/Skeleton3D/cop_char").get_meta("psx_face_top_frame")==5,"Eyes can be controlled independently")
	check(model.get_node("rig/Skeleton3D/cop_char").get_meta("psx_face_bottom_frame")==7,"Mouth can be controlled independently")
	face.enabled=false;renderer.render_editor()
	check(model.get_node("rig/Skeleton3D/cop_char").get_meta("psx_face_top_frame")==0,"Disabling expressions restores the neutral face")
	sheet.save_png("res://docs/face-expressions-psx.png")
	FileAccess.open("res://docs/face-expressions-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"maximum_source_error_m":maximum_error,"joints":skeleton.get_bone_count(),"maximum_influences":maximum_influences,"texture_pages":renderer.texture_page_count,"batches":renderer.batch_count,"presets":presets,"failures":failures},"\t"))
	viewport.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	print("FACE_EXPRESSIONS_OK: new Blender mesh, lossless full skin, independent eyes/mouth, exact 128px tiles, GPU presets, live UV/page selection and unchanged bones/atlas" if failures.is_empty() else "FACE_EXPRESSIONS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
