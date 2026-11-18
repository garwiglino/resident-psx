extends SceneTree
var failures: Array[String]=[]
var checks := 0
var renderer: Node
var buffer: SubViewport
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func quad() -> ArrayMesh:
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.55,-.55,0),Vector3(-.55,.55,0),Vector3(.55,.55,0),Vector3(.55,-.55,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK]);arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,1),Vector2(0,0),Vector2(1,0),Vector2(1,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3]);var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh
func pixels() -> Image:
	renderer.render_editor()
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw;return buffer.get_texture().get_image()
func run() -> void:
	create_timer(35).timeout.connect(func():push_error("Unlit hover timeout");quit(2));root.get_node("InventoryState").persist_collection=false
	buffer=SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	var stage := Node3D.new();buffer.add_child(stage);var camera := Camera3D.new();buffer.add_child(camera);camera.position.z=3;camera.fov=45;camera.make_current()
	var texture_image := Image.create(4,4,false,Image.FORMAT_RGBA8);texture_image.fill(Color.WHITE)
	for y in 4:
		for x in 2:texture_image.set_pixel(x,y,Color(1,.2,.1))
	texture_image.set_pixel(0,0,Color.TRANSPARENT)
	var material: StandardMaterial3D=load("res://scripts/psx_materials.gd").make(Color.WHITE);material.albedo_texture=ImageTexture.create_from_image(texture_image)
	var left := MeshInstance3D.new();left.name="Left";left.mesh=quad();left.material_override=material;stage.add_child(left);left.position.x=-.8
	var right := MeshInstance3D.new();right.name="Right";right.mesh=left.mesh;right.material_override=material;stage.add_child(right);right.position.x=.8
	renderer=load("res://scripts/psx_renderer.gd").new();buffer.add_child(renderer);renderer.fog_enabled=false;renderer.dithering=false;renderer.ambient_light_color=Color.BLACK;renderer.setup_editor(stage,camera)
	renderer.entries.clear();renderer.editor_preview=false;renderer.cache_branch(stage);renderer.editor_preview=true;renderer._finish_geometry()
	check(renderer.native_geometry.has_method("set_unlit_overrides") and renderer.native_geometry.get_statistics().version>=22,"Native renderer supports material-lighting overrides without rebuilding geometry")
	var dark := await pixels();check(dark.get_pixel(110,120).r<.05 and dark.get_pixel(265,120).r<.05,"Both ordinary surfaces start dark")
	var atlas: int=renderer.atlas_texture.get_instance_id();var revision: int=renderer.geometry_revision
	renderer.set_hover_unlit([left]);var highlighted := await pixels()
	check(highlighted.get_pixel(65,120).r>.5 and highlighted.get_pixel(65,120).g<.4 and highlighted.get_pixel(110,120).g>.5,"Hovered surface retains its red and white texture instead of a flat silhouette")
	check(highlighted.get_pixel(265,120).r<.05,"A second mesh sharing the same material stays normally lit")
	check(highlighted.get_pixel(40,75).r<.05,"Texture transparency remains a real PSX cutout")
	check(left.get_active_material(0)==material and right.get_active_material(0)==material,"Hover never edits or replaces a shared source material")
	for tick in 100:renderer.set_hover_unlit([left])
	check(renderer.atlas_texture.get_instance_id()==atlas and renderer.geometry_revision==revision,"Repeated hover never rebuilds texture pages or cached geometry")
	renderer.ambient_light_color=Color(.3,.2,.1);renderer.torch_on=true
	renderer.native_geometry.set_torch_light(Vector3(0,0,2),Vector3.FORWARD,Vector3(1,0,1),15,8,.5,.9);renderer.native_geometry.set_shot_light(Vector3(0,0,1),Vector3(1,1,1),15,8)
	var relit := await pixels()
	check(relit.get_region(Rect2i(30,65,108,110)).get_data()==highlighted.get_region(Rect2i(30,65,108,110)).get_data(),"Ambient, torch and muzzle light do not change the hovered material")
	renderer.set_hover_unlit([]);renderer.torch_on=false;renderer.native_geometry.set_shot_light(Vector3.ZERO,Vector3.ZERO,0,1);var restored := await pixels()
	check(restored.get_pixel(110,120).r>.2 and restored.get_pixel(110,120).r<.5,"Leaving hover rebakes fixed lighting changed during the highlight")
	check(restored.get_pixel(110,120).is_equal_approx(restored.get_pixel(265,120)),"Restored shared surfaces agree with current level lighting")
	renderer.set_hover_unlit([right]);var switched := await pixels()
	check(switched.get_pixel(265,120).g>.5 and switched.get_pixel(110,120).g<.4,"Switching targets restores the previous material before highlighting the next")
	renderer.set_hover_unlit([left]);renderer.fog_enabled=true;renderer.fog_start=0;renderer.fog_end=6;renderer.fog_color=Color(.1,.15,.3);var fogged := await pixels()
	check(fogged.get_pixel(110,120)!=highlighted.get_pixel(110,120),"Level fog still applies to the selected unlit part")
	renderer.fog_enabled=false
	var rig := Skeleton3D.new();rig.name="Rig";stage.add_child(rig);rig.position=left.position;rig.add_bone("part")
	var arrays := left.mesh.surface_get_arrays(0);arrays[Mesh.ARRAY_BONES]=PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);arrays[Mesh.ARRAY_WEIGHTS]=PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0])
	var geometry := ArrayMesh.new();geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);left.mesh=geometry;left.skeleton=left.get_path_to(rig);var skin := Skin.new();skin.add_named_bind(&"part",Transform3D.IDENTITY);left.skin=skin
	renderer.rebuild_editor_geometry();rig.set_bone_pose_position(0,Vector3(.1,0,0));var posed := await pixels()
	check(posed.get_pixel(115,120).g>.5 and renderer.entries.any(func(entry: Dictionary):return entry.node==left and entry.skeleton==rig),"Unlit override survives geometry refresh and follows the authored skeleton")
	posed.resize(960,720,Image.INTERPOLATE_NEAREST);posed.save_png("res://docs/hover-unlit-native.png")
	renderer.set_hover_unlit([]);renderer.native_geometry=null;renderer.native_geometry_enabled=false;renderer.ambient_light_color=Color.BLACK;renderer.rebuild_editor_geometry();renderer.set_hover_unlit([left]);var fallback := await pixels()
	check(fallback.get_pixel(115,120).g>.5 and fallback.get_pixel(265,120).r<.05,"GDScript fallback uses the same textured unlit selection")
	renderer.set_hover_unlit([]);check((await pixels()).get_pixel(115,120).r<.05,"GDScript fallback also restores ordinary lighting")
	left.mesh=null;right.mesh=null;buffer.queue_free();await process_frame;await process_frame
	FileAccess.open("res://docs/hover-unlit-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("HOVER_UNLIT_OK " if failures.is_empty() else "HOVER_UNLIT_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
