extends SceneTree
const Appearance=preload("res://scripts/character_appearance.gd")
const Face=preload("res://scripts/face_expressions.gd")
const Clothing=preload("res://scripts/clothing/character_clothing.gd")
const Renderer=preload("res://scripts/psx_renderer.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func capture(viewport: SubViewport,path: String) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image();image.save_png(path);return image
func run() -> void:
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	var model=load("res://assets/character/cop_player.glb").instantiate();model.name="Cop";stage.add_child(model)
	var animation: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	animation.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;animation.play(animation.get_animation_list()[0],0);animation.advance(0)
	var face := Face.new();face.model_path=NodePath("../Cop");stage.add_child(face);face.set_expression(5,7)
	var appearance := Appearance.new();appearance.model_path=NodePath("../Cop");stage.add_child(appearance)
	var outfit := Clothing.new();outfit.model_path=NodePath("../Cop");stage.add_child(outfit)
	var body: MeshInstance3D=model.get_node("rig/Skeleton3D/cop_char")
	var original_body: Mesh=body.get_meta(&"psx_clothing_source_mesh")
	check(appearance._surfaces.size()==2,"Appearance controls the body and preserves the separate hair material")
	var face_state: Array=[]
	for surface in face._surfaces:
		face_state.append([surface.material,surface.material.albedo_texture,surface.material.uv1_scale,surface.material.uv1_offset])
	for node in model.find_children("*","MeshInstance3D",true,false):
		for index in node.mesh.get_surface_count():
			var material: StandardMaterial3D=node.get_active_material(index)
			check(material!=null,"Every player and garment surface has a valid PSX material")
			if not material:continue
			check(material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and material.specular_mode==BaseMaterial3D.SPECULAR_DISABLED and material.metallic_specular==0 and material.metallic==0 and material.roughness==1,"Body, face and jacket cannot add Godot specular lighting to the native Gouraud pass")
			check(not material.normal_enabled and not material.clearcoat_enabled and not material.heightmap_enabled and not material.rim_enabled and not material.emission_enabled and material.next_pass==null and material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST,"Player materials discard PBR maps, extra passes and smoothing filters")
	var garment: MeshInstance3D=outfit._cache[&"winter_jacket"].root.find_children("*","MeshInstance3D",true,false)[0]
	var jacket_texture: Texture2D=garment.get_active_material(0).albedo_texture
	# Another instance shares the imported Mesh resource but owns its materials.
	var other := Node3D.new();viewport.add_child(other)
	var other_model=load("res://assets/character/cop_player.glb").instantiate();other_model.name="Cop";other.add_child(other_model)
	var other_appearance := Appearance.new();other_appearance.model_path=NodePath("../Cop");other.add_child(other_appearance)
	var other_texture: Texture2D=other_appearance._surfaces[0].material.albedo_texture
	var camera := Camera3D.new();viewport.add_child(camera);camera.position=Vector3(.2,1.0,3);camera.fov=38;camera.near=.02;camera.look_at(Vector3(0,.9,0))
	var renderer := Renderer.new();renderer.name="PSXRenderer";viewport.add_child(renderer)
	renderer.fog_start=30;renderer.fog_end=40;renderer.ambient_light_color=Color(.8,.8,.8);renderer.dithering=false
	renderer.setup_editor(stage,camera);renderer.render_editor()
	outfit.unequip();renderer.render_editor()
	var original: Image=await capture(viewport,"res://docs/player-body-original.png")
	var entry_count := renderer.entries.size()
	var skeleton: Skeleton3D=model.get_node("rig/Skeleton3D")
	var poses: Array[Transform3D]=[]
	for bone in skeleton.get_bone_count():poses.append(skeleton.get_bone_pose(bone))
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8);image.fill(Color(.95,.07,.015))
	var replacement := ImageTexture.create_from_image(image);appearance.texture_corps=replacement;renderer.render_editor()
	for surface in appearance._surfaces:check(surface.material.albedo_texture==(replacement if surface.body_texture else surface.original_texture),"The assigned texture applies to the body and preserves the hair")
	var textured: Image=await capture(viewport,"res://docs/player-body-texture-override.png")
	check(textured.get_data()!=original.get_data(),"Body texture changes the actual native PSX framebuffer")
	for entry in renderer.entries:
		if String(entry.node.name) in ["cop_char","cop_coat_mask"] and not entry.face_part:check(entry.texture==replacement,"PSX cache picks up the replacement body texture")
	for index in face._surfaces.size():
		var material: StandardMaterial3D=face._surfaces[index].material
		check(material==face_state[index][0] and material.albedo_texture==face_state[index][1] and material.uv1_scale==face_state[index][2] and material.uv1_offset==face_state[index][3],"Body texture leaves the exact facial material, atlas and expression UVs intact")
	check(other_appearance._surfaces[0].material.albedo_texture==other_texture,"Assigning a body texture does not modify another player instance")
	check(garment.get_active_material(0).albedo_texture==jacket_texture,"Body texture never replaces the separate jacket texture")
	outfit.equip_id(&"winter_jacket");check(body.mesh!=original_body,"Body texture changes preserve the equipped jacket's body mask")
	outfit.unequip();check(body.mesh==original_body,"Removing the jacket reveals the body mask with its updated texture")
	appearance.refresh();check(appearance._surfaces[0].material.albedo_texture==replacement,"Refreshing or reimporting the body preserves the assigned texture")
	appearance.texture_corps=null;renderer.render_editor()
	var restored: Image=await capture(viewport,"res://docs/player-body-texture-restored.png")
	check(restored.get_data()==original.get_data(),"Clearing the field exactly restores the original body appearance")
	check(renderer.entries.size()==entry_count and renderer.native_geometry.get_statistics().batches==1,"Texture changes retain the single PSX batch without adding geometry")
	for bone in skeleton.get_bone_count():check(skeleton.get_bone_pose(bone).is_equal_approx(poses[bone]),"Changing texture never modifies the rig or pose")
	# Close-up of the real rendered face: expressions must keep their pixels,
	# even when a deliberately solid red texture replaces the whole body atlas.
	camera.position=Vector3(0,1.47,.72);camera.fov=25;camera.look_at(Vector3(0,1.47,0));renderer.render_editor()
	var original_face: Image=await capture(viewport,"res://docs/player-face-before-body-texture.png")
	appearance.texture_corps=replacement;renderer.render_editor()
	var replaced_face: Image=await capture(viewport,"res://docs/player-face-after-body-texture.png")
	var face_changed := 0
	var face_differences: Array=[]
	# Sample eyes, nose and mouth inside the facial polygons; the neck and
	# hair are outside these sample regions.
	for region in [Rect2i(132,94,16,16),Rect2i(153,94,34,16),Rect2i(146,112,27,20),Rect2i(145,136,29,12)]:
		for y in range(region.position.y,region.end.y):
			for x in range(region.position.x,region.end.x):
				if original_face.get_pixel(x,y)!=replaced_face.get_pixel(x,y):
					face_changed+=1
					if face_differences.size()<12:face_differences.append([x,y,str(original_face.get_pixel(x,y)),str(replaced_face.get_pixel(x,y))])
	if face_changed:print("FACE_DIFFERENCES ",face_changed," ",face_differences)
	check(face_changed==0,"Actual facial pixels stay identical when changing the body texture")
	appearance.texture_corps=null
	FileAccess.open("res://docs/player-appearance-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"body_surfaces":appearance._surfaces.size(),"face_surfaces":face._surfaces.size(),"native_psx":true,"batches":renderer.native_geometry.get_statistics().batches},"\t"))
	viewport.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	print("PLAYER_APPEARANCE_OK: live body texture, masked faces, independent expressions and clothing, instance isolation, no modern material effects and one native PSX batch" if failures.is_empty() else "PLAYER_APPEARANCE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
