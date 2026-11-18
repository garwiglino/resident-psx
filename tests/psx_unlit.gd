extends SceneTree
const Unlit=preload("res://scripts/materials/psx_unlit_material.gd")
var failures: Array[String]=[]
var checks := 0
var renderer: Node
var buffer: SubViewport
var stage: Node3D
var camera: Camera3D
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func quad() -> ArrayMesh:
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.7,-.7,0),Vector3(-.7,.7,0),Vector3(.7,.7,0),Vector3(.7,-.7,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK]);arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,1),Vector2(0,0),Vector2(1,0),Vector2(1,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3]);var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh
func mesh_node(name: String,material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=name;node.mesh=quad();node.material_override=material;stage.add_child(node);return node
func frame() -> PackedColorArray:
	renderer.render_editor()
	return renderer.primitives[0].colors if not renderer.primitives.is_empty() else PackedColorArray()
func rebuild_fixed() -> void:
	# Same fixed/dynamic classification as gameplay, while retaining the isolated camera.
	renderer.entries.clear();renderer.editor_preview=false;renderer.cache_branch(stage);renderer.editor_preview=true;renderer._finish_geometry()
func pixels() -> Image:
	frame();await process_frame;await RenderingServer.frame_post_draw;return buffer.get_texture().get_image()
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("Unlit validation timeout");quit(2))
	root.get_node("InventoryState").persist_collection=false
	var material: Material=load("res://assets/materials/psx_unlit.tres").duplicate()
	check(material is Unlit and material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,"Draggable preset is an initialized PSXUnlitMaterial")
	material.color=Color(.75,.5,.25)
	check(material.albedo_color==material.color and material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and material.specular_mode==BaseMaterial3D.SPECULAR_DISABLED,"Color control updates the ordinary nearest/unshaded editor material")
	var exposed: Array[String]=[]
	for property in material.get_property_list():
		if property.usage&PROPERTY_USAGE_EDITOR and property.usage&PROPERTY_USAGE_STORAGE:exposed.append(property.name)
	check("color" in exposed and "texture" in exposed and "metallic" not in exposed and "shading_mode" not in exposed,"Inspector exposes color and texture without modern lighting settings")
	buffer=SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	stage=Node3D.new();buffer.add_child(stage);camera=Camera3D.new();buffer.add_child(camera);camera.position.z=3;camera.fov=45;camera.make_current()
	var mesh := mesh_node("Unlit",material)
	renderer=load("res://scripts/psx_renderer.gd").new();buffer.add_child(renderer);renderer.fog_enabled=false;renderer.dithering=false;renderer.ambient_light_color=Color.BLACK;renderer.setup_editor(stage,camera);rebuild_fixed()
	check(renderer.native_geometry.get_statistics().version>=20 and renderer.entries[0].unlit and renderer.entries[0].fixed,"Gameplay fixed geometry carries native autonomous-unlit flag")
	check(renderer.entries[0].unlit_light_id==0 and stage.find_children("*","PSXLamp3D",true,false).is_empty() and renderer.world_lights.is_empty(),"Autonomous material needs no lamp, fake light or mesh metadata")
	var dark := frame();check(not dark.is_empty() and dark[0].r>.7 and dark[0].g>.45,"Untextured material stays visible with zero ambient light")
	var light: Node3D=load("res://scripts/psx_light_3d.gd").new();stage.add_child(light);light.position.z=1.5;light.light_energy=12;light.light_range=10;light.light_color=Color(0,1,1)
	renderer.ambient_light_color=Color(1,.1,.1);renderer.torch_on=true;renderer.native_geometry.set_torch_light(Vector3(0,0,2),Vector3.FORWARD,Vector3(1,0,1),15,8,.5,.9);renderer.native_geometry.set_shot_light(Vector3(0,0,1),Vector3(1,1,1),15,8)
	var bright := frame();check(dark==bright,"Ambient, PSX lights, torch and muzzle flash cannot change the unlit packet colors")
	check(renderer.native_geometry.get_statistics().shadow_rays==0,"Unlit vertices bypass light/shadow sampling")
	check(renderer.entries[0].light_occluder and not renderer.entries[0].light_static_receiver,"Opaque unlit surfaces still occlude light without receiving it")
	renderer.fog_enabled=true;renderer.fog_start=0;renderer.fog_end=6;renderer.fog_color=Color(.1,.15,.3)
	check(frame()!=bright,"PSX fog still applies to autonomous unlit surfaces")
	renderer.fog_enabled=false;renderer.saturation=0
	var grey := frame();check(absf(grey[0].r-grey[0].g)<.005 and absf(grey[0].r-grey[0].b)<.005,"Level saturation also grades unlit color")
	renderer.saturation=1;renderer.color_tint=Color.WHITE;renderer.brightness=1;renderer.apply_render_settings()
	var image := Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	for y in 4:
		for x in 2:image.set_pixel(x,y,Color(1,.2,.1,1))
	material.texture=ImageTexture.create_from_image(image);renderer.refresh_materials(stage)
	var textured := frame();check(renderer.entries[0].textured and is_equal_approx(textured[0].r,floorf(.75*128)/255.0),"Texture uses PSX neutral 0x80 modulation, with the material color")
	var picture := await pixels();var left := picture.get_pixel(140,120);var right := picture.get_pixel(205,120)
	check(left.r>.5 and left.g<.2 and right.g>.4,"Native PSX framebuffer displays the assigned texture multiplied by color")
	picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/psx-unlit-texture.png")
	# Alpha stays a hard texture cutout through the same PSX raster path.
	image.set_pixel(0,0,Color(1,1,1,0));material.texture=ImageTexture.create_from_image(image);renderer.refresh_materials(stage);picture=await pixels()
	check(picture.get_pixel(110,70).r<.1 and picture.get_pixel(180,120).r>.5,"Texture alpha creates a cutout instead of a modern translucent surface")
	# Dynamic and skinned geometry use the same unlit base color.
	mesh.add_to_group("psx_dynamic_geometry");rebuild_fixed();check(not renderer.entries[0].fixed and frame()==textured,"Moving meshes retain autonomous unlit colors")
	var rig := Skeleton3D.new();rig.name="Rig";stage.add_child(rig);rig.add_bone("part")
	var arrays := mesh.mesh.surface_get_arrays(0);arrays[Mesh.ARRAY_BONES]=PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);arrays[Mesh.ARRAY_WEIGHTS]=PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0]);var geometry := ArrayMesh.new();geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.mesh=geometry
	mesh.skeleton=mesh.get_path_to(rig);var skin := Skin.new();skin.add_named_bind(&"part",Transform3D.IDENTITY);mesh.skin=skin;renderer.rebuild_editor_geometry()
	rig.set_bone_pose_position(0,Vector3(.1,0,0));check(renderer.entries[0].skeleton==rig and frame()==textured,"Skinned unlit surfaces ignore lighting while keeping bone motion")
	mesh.skin=null;mesh.skeleton=NodePath();mesh.mesh=quad();mesh.remove_from_group("psx_dynamic_geometry");renderer.rebuild_editor_geometry()
	var converted: Material=load("res://scripts/psx_materials.gd").character_material(material,Color(.5,1,1))
	check(converted is Unlit and converted.texture==material.texture and converted.color==material.color*Color(.5,1,1),"Character/prop material preparation preserves autonomous unlit resources")
	var path := "res://exports/editor_tests/psx_unlit_roundtrip.tres";ResourceSaver.save(material,path)
	var restored: Material=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored is Unlit and restored.color==material.color and restored.texture.get_image().get_data()==material.texture.get_image().get_data(),"Color, texture and custom material survive save/load")
	restored.color=Color.GREEN;check(material.color!=restored.color,"Duplicated or separately saved presets can be edited independently")
	var lit: Material=load("res://scripts/psx_materials.gd").make(Color.WHITE);mesh.material_override=lit;renderer.refresh_materials(stage)
	check(not renderer.entries[0].unlit,"Ordinary project materials remain vertex-lit despite their Godot Unshaded setting")
	light.enabled=false;renderer.ambient_light_color=Color.BLACK;renderer.torch_on=false;renderer.native_geometry.set_shot_light(Vector3.ZERO,Vector3.ZERO,0,1)
	check(frame()[0].r==0,"Switching back to a lit material restores darkness")
	mesh.set_surface_override_material(0,material);mesh.material_override=null;renderer.rebuild_editor_geometry();check(renderer.entries[0].unlit,"Surface Override Materials supports the same draggable material")
	# Fallback must interpret the same resource when native rendering is intentionally disabled.
	renderer.native_geometry=null;renderer.native_geometry_enabled=false;renderer.rebuild_editor_geometry();var fallback := frame();light.enabled=true;renderer.ambient_light_color=Color.WHITE;renderer.torch_on=true;renderer.shot_light_energy=10
	check(not fallback.is_empty() and frame()==fallback,"GDScript path also ignores every light for the autonomous material")
	mesh.mesh=null;buffer.queue_free();await process_frame;await process_frame
	FileAccess.open("res://docs/psx-unlit-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("PSX_UNLIT_OK " if failures.is_empty() else "PSX_UNLIT_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
