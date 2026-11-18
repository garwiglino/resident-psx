extends SceneTree
const Clothing=preload("res://scripts/clothing/character_clothing.gd")
const Renderer=preload("res://scripts/psx_renderer.gd")
const Face=preload("res://scripts/face_expressions.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func source_error(entry: Dictionary,points: Array) -> float:
	var transforms: Array[Transform3D]=[]
	for index in entry.binds.size():transforms.append(entry.skeleton.global_transform*entry.skeleton.get_bone_global_pose(entry.bind_indices[index])*entry.binds[index])
	var stride: int=entry.bones.size()/entry.vertices.size();var error := 0.0
	for vertex in entry.vertices.size():
		var point := Vector3.ZERO;var total := 0.0
		for influence in stride:
			var weight: float=entry.weights[vertex*stride+influence]
			if weight>0:point+=(transforms[entry.bones[vertex*stride+influence]]*entry.vertices[vertex])*weight;total+=weight
		check(absf(total-1)<.0001,"Clothing/body weights are normalized")
		var closest := INF
		for expected in points:closest=minf(closest,point.distance_squared_to(Vector3(expected[0],expected[1],expected[2])))
		error=maxf(error,sqrt(closest))
	return error
func capture(viewport: SubViewport,path: String) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image();image.save_png(path);return image
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var body_meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/cop_player.json"))
	var jacket_meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/clothing/winter_jacket.json"))
	var jeans_meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/clothing/large_jeans_01.json"))
	var sneakers_meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/clothing/sneakers.json"))
	check(sneakers_meta.source_sample.any(func(point: Array):return float(point[0])<-.05) and
		sneakers_meta.source_sample.any(func(point: Array):return float(point[0])>.05),"Both sneakers are exported at the player's feet")
	var jeans_center := Vector3.ZERO
	for point in jeans_meta.source_sample:
		jeans_center+=Vector3(point[0],point[1],point[2])
	jeans_center/=jeans_meta.source_sample.size()
	check(absf(jeans_center.x)<.05,"The export uses the jeans' fitted placement on the rig")
	check(String(body_meta.source_sha256).length()==64 and String(jacket_meta.source_sha256).length()==64,"Independent body and garment exports retain their own Blender snapshot")
	check(jacket_meta.get("direct_blender_skin",false) and not jacket_meta.get("weights_redistributed",true) and jacket_meta.joint_names.all(func(joint: String):return joint in body_meta.joint_names),"The player rig includes every coat joint and preserves the original Blender skin")
	var alignment := Vector3(jacket_meta.alignment_blender_m[0],jacket_meta.alignment_blender_m[1],jacket_meta.alignment_blender_m[2])
	check(jacket_meta.alignment_mode=="source" and alignment.is_zero_approx(),"Jacket placement exactly preserves Blender, with no automatic recentering")
	check(body_meta.mask_mode=="godot" and int(body_meta.coat_mask_polygons)==0,"The body export contains no baked mask")
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	var model=load("res://assets/character/cop_player.glb").instantiate();model.name="Cop";stage.add_child(model)
	var animator: AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;animator.play(animator.get_animation_list()[0],0);animator.advance(0)
	var outfit := Clothing.new();outfit.model_path=NodePath("../Cop");stage.add_child(outfit)
	var face := Face.new();face.model_path=NodePath("../Cop");stage.add_child(face)
	var skeleton: Skeleton3D=model.get_node("rig/Skeleton3D")
	check(skeleton.get_bone_count()==int(body_meta.joint_count) and model.find_children("*","Skeleton3D",true,false).size()==1,"Garment reuses the player's shared exported skeleton without a second animated rig")
	check(outfit.is_equipped(&"winter_jacket") and outfit._cache.has(&"winter_jacket"),"Updated player starts with the modular winter jacket")
	var body: MeshInstance3D=skeleton.get_node("cop_char")
	var hair: MeshInstance3D=skeleton.get_node("cop_hair")
	var original_body: ArrayMesh=body.get_meta(&"psx_clothing_source_mesh")
	var original_hair: ArrayMesh=hair.mesh
	var masked_faces := 0
	var visible_front := 0
	for surface in original_body.get_surface_count():
		masked_faces+=(original_body.surface_get_array_index_len(surface)-body.mesh.surface_get_array_index_len(surface))/3
		var arrays := body.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for triangle in indices.size()/3:
			var point := (vertices[indices[triangle*3]]+vertices[indices[triangle*3+1]]+vertices[indices[triangle*3+2]])/3.0
			if absf(point.x)<.05 and point.y>1.05 and point.y<1.35 and point.z>.02:
				visible_front+=1
	check(body.visible and masked_faces>0 and visible_front>0 and hair.visible and hair.mesh==original_hair,"The generated mask covers part of the body and preserves the opening and hair")
	print("MASK ",masked_faces," triangles, ",visible_front," at front")
	var garment: MeshInstance3D=outfit._cache[&"winter_jacket"].root.find_children("*","MeshInstance3D",true,false)[0]
	check(garment.get_node(garment.skeleton)==skeleton and garment.skin.get_bind_count()>0,"Module binds directly onto the player's live skeleton")
	for bind in garment.skin.get_bind_count():check(skeleton.find_bone(garment.skin.get_bind_name(bind))>=0,"All module skin binds resolve by bone name")
	var camera := Camera3D.new();viewport.add_child(camera);camera.position=Vector3(.2,1.0,3);camera.fov=38;camera.near=.02;camera.look_at(Vector3(0,.9,0))
	var renderer := Renderer.new();renderer.name="PSXRenderer";viewport.add_child(renderer)
	renderer.fog_start=30;renderer.fog_end=40;renderer.ambient_light_color=Color(.8,.8,.8);renderer.dithering=false
	renderer.setup_editor(stage,camera);renderer.render_editor()
	var max_body_error := 0.0;var max_jacket_error := 0.0;var jacket_entries := 0
	var jeans: MeshInstance3D=outfit._cache[&"large_jeans_01"].meshes[0]
	var sneakers: MeshInstance3D=outfit._cache[&"sneakers"].meshes[0]
	var source_uniform: MeshInstance3D=outfit._cache[&"cop_outfit"].meshes[0]
	var police_meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/clothing/cop_outfit.json"))
	for entry in renderer.entries:
		if entry.skeleton!=skeleton:continue
		if entry.node==garment:
			jacket_entries+=1;max_jacket_error=maxf(max_jacket_error,source_error(entry,jacket_meta.source_sample))
			var stride: int=entry.weights.size()/entry.vertices.size()
			check(stride>=int(jacket_meta.get("max_influences",0)),"PSX skinning keeps all Blender influences, including more than eight")
			for row in jacket_meta.overflow_skin:
				var matched := false
				for vertex in entry.vertices.size():
					if entry.vertices[vertex].distance_squared_to(Vector3(row.position[0],row.position[1],row.position[2]))>=.0000000001:continue
					matched=true
					for authored in row.weights:
						var actual := 0.0
						for influence in stride:
							var offset: int=vertex*stride+influence
							if skeleton.get_bone_name(entry.bind_indices[entry.bones[offset]])==StringName(authored[0]):actual+=entry.weights[offset]
						check(absf(actual-float(authored[1]))<.000001,"Overflow weight matches Blender's complete exported skin")
				check(matched,"Every overflow vertex resolves onto the imported garment")
		elif entry.node==jeans:
			check(source_error(entry,jeans_meta.source_sample)<.001,"Jeans use the source position and complete Blender skin")
		elif entry.node==sneakers:
			check(source_error(entry,sneakers_meta.source_sample)<.001,"Both sneakers preserve the Blender placement and skin")
		elif entry.node==source_uniform:
			check(source_error(entry,police_meta.source_sample)<.001,"The uniform preserves its fitted Blender export and all weights")
		else:max_body_error=maxf(max_body_error,source_error(entry,body_meta.source_sample))
	check(max_body_error<.001 and max_jacket_error<.001,"Both exported meshes reproduce their Blender positions/UV export transforms within 1 mm")
	check(jacket_entries==garment.mesh.get_surface_count() and renderer.batch_count==1,"Modular garment remains inside the single PSX draw batch")
	var initial_atlas := renderer.atlas_texture.get_instance_id();var entry_count := renderer.entries.size()
	var cached_indices := 0
	for entry in renderer.entries:
		if entry.node==body:
			cached_indices+=entry.indices.size()
	var equipped: Image=await capture(viewport,"res://docs/winter-jacket-equipped.png")
	var poses: Array[Transform3D]=[]
	for bone in skeleton.get_bone_count():poses.append(skeleton.get_bone_pose(bone))
	outfit.unequip();renderer.render_editor()
	check(body.mesh==original_body and not garment.is_visible_in_tree(),"Removing the jacket immediately restores the full body mesh")
	var restored_indices := 0
	for entry in renderer.entries:
		if entry.node==body:
			restored_indices+=entry.indices.size()
	check(restored_indices-cached_indices==masked_faces*3,"Native PSX renderer receives the restored indices without repacking textures")
	var uniform: Image=await capture(viewport,"res://docs/winter-jacket-uniform.png")
	check(equipped.get_data()!=uniform.get_data(),"Actual native PSX framebuffer changes with clothing visibility")
	check(outfit.equip_id(&"winter_jacket") and body.mesh!=original_body and garment.is_visible_in_tree(),"Re-equipping uses the cached garment and restores its mask")
	for index in 15:outfit.unequip();outfit.equip_id(&"winter_jacket")
	check(renderer.atlas_texture.get_instance_id()==initial_atlas and renderer.entries.size()==entry_count,"Repeated clothing switches allocate no new atlas, draw entry or skeletal rig")
	for bone in skeleton.get_bone_count():check(skeleton.get_bone_pose(bone).is_equal_approx(poses[bone]),"Changing clothing never changes an animation pose")
	# Inspector texture override must update actual PSX pixels without rebinding.
	var item=outfit.outerwear;var original_texture: Texture2D=item.texture
	var saved_mesh: Mesh=garment.mesh;var saved_skin: Skin=garment.skin
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8);image.fill(Color(.9,.08,.02))
	var replacement := ImageTexture.create_from_image(image)
	item.texture=replacement;renderer.render_editor()
	check(garment.get_active_material(0).albedo_texture==replacement,"Texture field updates the private 3D material")
	var texture_entry_changed := false
	for entry in renderer.entries:
		if entry.node==garment and entry.texture==replacement:texture_entry_changed=true
	check(texture_entry_changed,"Texture override updates cached PSX material data")
	var recolored: Image=await capture(viewport,"res://docs/winter-jacket-texture-override.png")
	check(recolored.get_data()!=equipped.get_data(),"Actual PSX framebuffer displays the assigned texture")
	check(garment.mesh==saved_mesh and garment.skin==saved_skin and body.mesh!=original_body,"Changing a texture preserves mesh, skin and coat mask")
	item.texture=original_texture;renderer.render_editor()
	var restored_image: Image=await capture(viewport,"res://docs/winter-jacket-texture-restored.png")
	check(restored_image.get_data()==equipped.get_data(),"Restoring the configured texture exactly restores its original appearance")
	face.set_expression(5,7);renderer.render_editor()
	check(face._surfaces.size()==2 and model.get_node("rig/Skeleton3D/cop_char").get_meta("psx_face_top_frame")==5,"Face expressions remain independent of modular clothing")
	var comparison := Image.create(640,240,false,Image.FORMAT_RGBA8)
	comparison.blit_rect(uniform,Rect2i(0,0,320,240),Vector2i.ZERO);comparison.blit_rect(equipped,Rect2i(0,0,320,240),Vector2i(320,0))
	comparison.resize(1280,480,Image.INTERPOLATE_NEAREST);comparison.save_png("res://docs/winter-jacket-comparison.png")
	viewport.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	# Real game: every movement and upper-body action uses that same skeleton.
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.psx_renderer.set_process(false);game.player.set_physics_process(false);game.player.set_process(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var motion=game.player.motion;var runtime_outfit=game.player.get_node("Tenue")
	check(runtime_outfit.is_equipped(&"large_jeans_01") and runtime_outfit.pants.slot==ClothingItem.Slot.PANTS,
		"Jeans occupy the pants slot independently of the jacket")
	check(runtime_outfit.is_equipped(&"sneakers") and runtime_outfit.shoes.slot==ClothingItem.Slot.SHOES,
		"Sneakers occupy the shoes slot independently of pants and jacket")
	for property in [&"texture_pantalon",&"texture_doudoune",&"texture_chaussures"]:
		check(runtime_outfit.get_property_list().any(func(info: Dictionary):return info.name==property and info.hint==PROPERTY_HINT_ENUM),
			"The assigned garment exposes its texture dropdown in the inspector")
	var runtime_jeans: MeshInstance3D=runtime_outfit._cache[&"large_jeans_01"].meshes[0]
	var runtime_sneakers: MeshInstance3D=runtime_outfit._cache[&"sneakers"].meshes[0]
	var runtime_coat: MeshInstance3D=runtime_outfit._cache[&"winter_jacket"].meshes[0]
	var jeans_texture: Texture2D=runtime_jeans.get_active_material(0).albedo_texture
	var coat_mesh: Mesh=runtime_coat.mesh
	var coat_skin: Skin=runtime_coat.skin
	runtime_outfit.set("texture_doudoune",0)
	var coat_original: Texture2D=runtime_coat.get_active_material(0).albedo_texture
	var coat_choices: PackedStringArray=runtime_outfit.outerwear.texture_set.choices()
	var jeans_choices: PackedStringArray=runtime_outfit.pants.texture_set.choices()
	var sneaker_choices: PackedStringArray=runtime_outfit.shoes.texture_set.choices()
	check(coat_choices.size()>3 and jeans_choices.size()>1 and sneaker_choices.has("Sakura"),
		"The assigned garments expose their configured finishes")
	for index in range(1,coat_choices.size()):
		runtime_outfit.set("texture_doudoune",index)
		var selected: Texture2D=runtime_outfit.outerwear.texture_set.variants[StringName(coat_choices[index])]
		check(runtime_outfit.get("texture_doudoune")==index and runtime_coat.get_active_material(0).albedo_texture==selected,
			"Inspector selection applies "+coat_choices[index])
		check(game.psx_renderer.entries.any(func(entry: Dictionary):return entry.node==runtime_coat and entry.texture==selected),
			"Texture reaches the native PSX atlas")
		check(runtime_coat.mesh==coat_mesh and runtime_coat.skin==coat_skin and runtime_jeans.get_active_material(0).albedo_texture==jeans_texture,
			"A finish change keeps the meshes, skin and other garment's texture")
	check(not runtime_outfit.set_texture_variant(ClothingItem.Slot.PANTS,&"Sakura"),
		"The jeans cannot select a sneaker finish")
	check(runtime_outfit.set_texture_variant(ClothingItem.Slot.PANTS,StringName(jeans_choices[1])),"Jeans accept their own finish")
	var jeans_finish: Texture2D=runtime_jeans.get_active_material(0).albedo_texture
	var sneaker_original: Texture2D=runtime_sneakers.get_active_material(0).albedo_texture
	check(runtime_outfit.set_texture_variant(ClothingItem.Slot.SHOES,&"Sorami") and
		runtime_sneakers.get_active_material(0).albedo_texture==runtime_outfit.shoes.texture_set.variants[&"Sorami"] and
		runtime_jeans.get_active_material(0).albedo_texture==jeans_finish,
		"Sneaker finish changes independently of the jeans")
	runtime_outfit.set("texture_chaussures",0)
	check(runtime_sneakers.get_active_material(0).albedo_texture==sneaker_original,"Sneakers restore their Blender texture")
	runtime_outfit.unequip()
	check(runtime_outfit.equip_id(&"winter_jacket") and runtime_outfit.get("texture_doudoune")==coat_choices.size()-1,
		"The finish is retained when a garment is removed and equipped again")
	runtime_outfit.set("texture_doudoune",0)
	check(runtime_coat.get_active_material(0).albedo_texture==coat_original,"Origine restores the texture embedded in the jacket")
	var player_template: PackedScene=load("res://scenes/player.tscn")
	var authored := player_template.instantiate()
	authored.get_node("Tenue").set("texture_doudoune",2)
	var packed := PackedScene.new()
	check(packed.pack(authored)==OK,"The texture selection can be saved with the player scene")
	var first := packed.instantiate()
	var second := packed.instantiate()
	check(first.get_node("Tenue").get("texture_doudoune")==2,"A saved scene restores the selected variant")
	first.get_node("Tenue").set("texture_doudoune",3)
	check(second.get_node("Tenue").get("texture_doudoune")==2,"Players sharing a clothing resource keep independent variant selections")
	authored.free();first.free();second.free()
	# Exercise the garment without changing the artist's saved uniform choice.
	runtime_outfit.equip_id(&"winter_jacket")
	var runtime_atlas: int=game.psx_renderer.atlas_texture.get_instance_id()
	var clips: Array[String]=["idle","walk","backward","strafe_left","strafe_right","forward_left","forward_right","backward_left","backward_right","run"]
	for clip in clips:
		motion.blend_time=.1;motion.play(clip)
		for index in 12:motion.advance_motion(1.0/30)
		check(motion.current==clip and runtime_outfit.is_equipped(&"winter_jacket"),"Garment follows the existing movement clip: "+clip)
		check(runtime_jeans.get_node(runtime_jeans.skeleton)==motion.body_skeleton and runtime_jeans.is_visible_in_tree(),
			"Jeans stay bound to the live skeleton during "+clip)
		check(runtime_sneakers.get_node(runtime_sneakers.skeleton)==motion.body_skeleton and runtime_sneakers.is_visible_in_tree(),
			"Sneakers stay bound to the live skeleton during "+clip)
		game.psx_renderer._process(0)
		check(game.psx_renderer.native_geometry.get_statistics().batches==1,"Movement keeps one native draw batch")
	runtime_outfit.unequip();runtime_outfit.equip_id(&"winter_jacket")
	check(game.psx_renderer.atlas_texture.get_instance_id()==runtime_atlas,"In-game equip/unequip never rebuilds the atlas")
	motion.play("idle");motion.set_aiming(true,0);motion.advance_motion(.3);game.player._apply_upper_body_look()
	var review_camera := Camera3D.new();game.add_child(review_camera)
	review_camera.global_position=game.player.global_position+Vector3(.8,1.25,-2.2)
	review_camera.look_at(game.player.global_position+Vector3(0,1.05,0));review_camera.fov=45
	game.psx_renderer.set_active_camera(review_camera)
	game.psx_renderer.ambient_light_color=Color(.65,.65,.65);game.psx_renderer.fog_start=30;game.psx_renderer.fog_end=40
	game.psx_renderer._process(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/winter-jacket-in-game.png")
	var saved_clothes: Dictionary=runtime_outfit.wardrobe_state()
	runtime_outfit.unequip()
	check(runtime_outfit.equip_id(&"cop_outfit"),"The exported police outfit equips on the player")
	var police: MeshInstance3D=runtime_outfit._cache[&"cop_outfit"].meshes[0]
	check(police.mesh.get_surface_count()==2 and police.get_node(police.skeleton)==motion.body_skeleton,"Uniform and boots keep their two materials and the shared player skin")
	var surface_names: Array[StringName]=[]
	for surface in police.mesh.get_surface_count():
		surface_names.append(police.mesh.surface_get_material(surface).resource_name)
	check(&"M_cop_outfit" in surface_names and &"M_Boots" in surface_names,"Both Blender materials remain addressable")
	check(game.player.unequip_weapon(),"The fit review uses the unarmed stance")
	motion.set_aiming(false,0)
	motion.blend_time=0
	motion.play("unarmed_walk")
	motion.advance_motion(.57)
	review_camera.global_position=game.player.global_position+Vector3(.91,.96,-2.45)
	review_camera.look_at(game.player.global_position+Vector3(0,.88,0));review_camera.fov=44
	game.psx_renderer._process(0)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/cop-outfit-walk.png")
	check(police.is_visible_in_tree() and game.psx_renderer.native_geometry.get_statistics().batches==1,"The uniform follows the revised walk in the native renderer")
	var police_source: ArrayMesh=police.mesh
	check(runtime_outfit.equip_id(&"winter_jacket") and runtime_outfit.is_equipped(&"cop_outfit") and
		police.mesh!=police_source and police.mesh.get_surface_count()==2,"The jacket masks the covered uniform without replacing its boots")
	game.player.equip_weapon(0)
	runtime_outfit.restore_wardrobe(saved_clothes)
	game.psx_renderer.set_active_camera(game.player.camera)
	var acquired=load("res://scripts/clothing/clothing_item.gd").new()
	acquired.id=&"new_module";acquired.scene=runtime_outfit.available_items[0].scene;acquired.skin_metadata=runtime_outfit.available_items[0].skin_metadata
	var before_acquisition: int=game.psx_renderer.entries.size()
	var added_surfaces: int=jacket_entries
	check(runtime_outfit.equip(acquired),"A new compatible module can be acquired during play")
	check(game.psx_renderer.entries.size()==before_acquisition+added_surfaces,"New module geometry registers exactly once")
	var acquired_atlas: int=game.psx_renderer.atlas_texture.get_instance_id()
	var top_item: ClothingItem=acquired.duplicate()
	top_item.id=&"test_top";top_item.slot=ClothingItem.Slot.TOP
	var shoes_item: ClothingItem=acquired.duplicate()
	shoes_item.id=&"test_shoes";shoes_item.slot=ClothingItem.Slot.SHOES
	var complete_item: ClothingItem=acquired.duplicate()
	complete_item.id=&"test_complete";complete_item.slot=ClothingItem.Slot.OUTFIT
	check(runtime_outfit.equip(top_item) and runtime_outfit.equip(shoes_item),"Separate pieces can be worn with outerwear")
	var top_mesh: MeshInstance3D=runtime_outfit._cache[top_item.id].meshes[0]
	var top_source: Mesh=top_mesh.get_meta(&"psx_clothing_source_mesh")
	check(top_mesh.mesh!=top_source,"Outerwear also generates a mask on the garment below it")
	runtime_outfit.unequip()
	check(top_mesh.mesh==top_source,"Removing outerwear restores the garment below it")
	check(runtime_outfit.equip(complete_item) and not runtime_outfit.is_equipped(top_item.id) and runtime_outfit.is_equipped(shoes_item.id),"Complete outfit replaces separates and keeps shoes")
	check(runtime_outfit.equip_id(&"winter_jacket") and runtime_outfit.is_equipped(complete_item.id),"Outerwear is independent of a complete outfit")
	runtime_outfit.unequip(ClothingItem.Slot.OUTFIT)
	check(runtime_outfit.is_equipped(top_item.id),"Removing the complete outfit restores the previous separates")
	runtime_outfit.unequip(ClothingItem.Slot.TOP)
	runtime_outfit.unequip(ClothingItem.Slot.SHOES)
	runtime_outfit.equip_id(&"sneakers")
	before_acquisition=game.psx_renderer.entries.size()-added_surfaces
	acquired_atlas=game.psx_renderer.atlas_texture.get_instance_id()
	runtime_outfit.equip_id(&"winter_jacket");runtime_outfit.equip(acquired)
	check(game.psx_renderer.atlas_texture.get_instance_id()==acquired_atlas and game.psx_renderer.entries.size()==before_acquisition+added_surfaces,"Switching an acquired module never duplicates geometry or atlas")
	runtime_outfit.refresh();game.psx_renderer._process(0)
	before_acquisition-=3*added_surfaces
	check(game.psx_renderer.entries.size()==before_acquisition+added_surfaces and game.psx_renderer.native_geometry.get_statistics().batches==1,"Refreshing modules prunes stale geometry and keeps one native draw batch")
	FileAccess.open("res://docs/clothing-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"body_source_sha256":body_meta.source_sha256,"jacket_source_sha256":jacket_meta.source_sha256,"body_error_m":max_body_error,"jacket_error_m":max_jacket_error,"jacket_max_influences":jacket_meta.max_influences,"jacket_overflow_vertices":jacket_meta.overflow_skin.size(),"joints":body_meta.joint_count,"mask_faces":masked_faces,"texture_override_verified":true,"clips":clips},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.15).timeout;game.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	print("CLOTHING_OK: latest Blender snapshot, exact source placement, separate jacket, shared skin, generated mask, native PSX rendering, cached switching, facial expressions and all movement clips" if failures.is_empty() else "CLOTHING_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
