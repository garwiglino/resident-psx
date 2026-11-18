extends SceneTree
var failures: Array[String]=[]
var checks := 0
var buffer: SubViewport
var stage: Node3D
var camera: Camera3D
var renderer: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func settle() -> void:
	for frame in 3:await process_frame
func quad(name: String,size: Vector2,position: Vector3,material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=name;node.mesh=QuadMesh.new();node.mesh.size=size;node.position=position;node.material_override=material;stage.add_child(node);return node
func pixels() -> Image:
	renderer.render_editor();await process_frame;await RenderingServer.frame_post_draw;return buffer.get_texture().get_image()
func run() -> void:
	create_timer(40).timeout.connect(func():push_error("Light shaft validation timeout");quit(2));root.get_node("InventoryState").persist_collection=false
	var unlit: Material=load("res://assets/materials/psx_unlit.tres").duplicate();unlit.color=Color(.25,.25,.25)
	var beam: Material=load("res://assets/materials/window_light_shaft.tres").duplicate();beam.color=Color.WHITE;beam.strength=1
	var image := Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE);beam.texture=ImageTexture.create_from_image(image)
	buffer=SubViewport.new();buffer.size=Vector2i(320,240);buffer.own_world_3d=true;buffer.world_2d=World2D.new();buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	stage=Node3D.new();buffer.add_child(stage);camera=Camera3D.new();buffer.add_child(camera);camera.position.z=3;camera.fov=45;camera.make_current()
	var background := quad("Background",Vector2(5,5),Vector3(0,0,-1),unlit)
	var shaft := quad("Beam",Vector2(1.8,1.8),Vector3.ZERO,beam)
	var occluder_material: Material=unlit.duplicate();occluder_material.color=Color(.125,.125,.125)
	var occluder := quad("Foreground",Vector2(.4,.6),Vector3(-.35,0,1),occluder_material)
	renderer=load("res://scripts/psx_renderer.gd").new();buffer.add_child(renderer);renderer.fog_enabled=false;renderer.dithering=false;renderer.ambient_light_color=Color.BLACK;renderer.setup_editor(stage,camera);renderer.render_editor()
	check(renderer.native_geometry.get_statistics().version>=21,"Native renderer supports ordered additive batches")
	var modes: Array=[]
	for packet in renderer.primitives:modes.append(packet.blend_mode)
	check(modes==[0,1,0],"PSX ordering table is preserved across opaque/additive/opaque packets")
	var picture := await pixels();var center := picture.get_pixel(160,120);var foreground := picture.get_pixel(108,120);var outside := picture.get_pixel(255,120)
	check(center.r>.45 and center.r<.51 and absf(center.r-center.g)<.01,"Additive RGB555 result follows B + floor(F/4), including its background")
	check(foreground.r>.08 and foreground.r<.13,"Foreground geometry masks rays without receiving their brightness")
	check(outside.r>.22 and outside.r<.29,"The rest of the world retains its original framebuffer color")
	renderer._set_raster_parameter(&"flash_opacity",.01);picture=await pixels();check(absf(picture.get_pixel(160,120).r-center.r)<.005,"Ray transparency is independent of weapon flash opacity")
	check(renderer.entries[1].unlit and renderer.entries[1].translucent and not renderer.entries[1].light_occluder and not renderer.entries[1].light_static_receiver,"Light shafts never receive or occlude vertex lighting")
	check(renderer._batch_canvases.size()==3,"Consecutive ordered packets reuse their canvas batches")
	shaft.hide();picture=await pixels();check(picture.get_pixel(160,120).r<.3 and not renderer.primitives.any(func(packet: Dictionary):return packet.blend_mode==1),"Hiding every ray returns cleanly to the ordinary one-batch renderer")
	shaft.show();picture=await pixels();check(picture.get_pixel(160,120).r>.45,"Showing a ray restores the additive path without stale draw commands")
	beam.strength=.5;renderer.refresh_materials(stage);picture=await pixels();check(picture.get_pixel(160,120).r>.32 and picture.get_pixel(160,120).r<.39,"Strength modulates source color before the fixed PSX blend ratio")
	beam.strength=1;renderer.refresh_materials(stage);renderer.fog_enabled=true;renderer.fog_start=0;renderer.fog_end=6;renderer.fog_color=Color.WHITE;renderer.render_editor()
	var additive: Dictionary=renderer.primitives.filter(func(packet: Dictionary):return packet.blend_mode==1)[0]
	check(additive.colors[0].r<.27,"Fog attenuates light shafts instead of injecting a luminous fog slab")
	# Complete authoring assets, UVs, masks and editable per-instance resources.
	background.queue_free();shaft.queue_free();occluder.queue_free();await settle()
	var effects: Array[Node3D]=[]
	for name in ["window_light_shaft","window_light_rays","thin_light_ray"]:
		var node: Node3D=load("res://scenes/effects/"+name+".tscn").instantiate();stage.add_child(node);effects.append(node)
		var arrays: Array=node.mesh.surface_get_arrays(0)
		check(not arrays[Mesh.ARRAY_VERTEX].is_empty() and arrays[Mesh.ARRAY_TEX_UV].size()==arrays[Mesh.ARRAY_VERTEX].size(),"Prefab provides real geometry with complete UVs: "+name)
		check(arrays[Mesh.ARRAY_INDEX].size()/3<=128 and node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Prefab stays lightweight and casts no modern shadow: "+name)
		var texture: Image=node.shaft_material.texture.get_image().duplicate();texture.convert(Image.FORMAT_RGBA8);var data := texture.get_data();var accurate := true
		for offset in range(0,data.size(),4):
			if (data[offset]&7)!=0 or data[offset+3] not in [0,255]:accurate=false;break
		check(texture.get_size()==Vector2i(64,128) and accurate,"Preset intensity mask uses RGB555 with binary transparency: "+name)
	var first: Node3D=effects[0];var clone: Node3D=load("res://scenes/effects/window_light_shaft.tscn").instantiate();stage.add_child(clone)
	check(first.shaft_material!=clone.shaft_material,"Duplicated window prefabs keep independently editable materials")
	var old_color: Color=first.shaft_material.color;clone.shaft_material.color=Color.RED;check(first.shaft_material.color==old_color,"Changing one window never recolors the others")
	var default_shaft := PSXLightShaft3D.new()
	var other_default_shaft := PSXLightShaft3D.new()
	stage.add_child(default_shaft)
	stage.add_child(other_default_shaft)
	var preset: PSXLightShaftMaterial=load("res://assets/materials/window_light_shaft.tres")
	check(default_shaft.mesh!=null and default_shaft.shaft_material.texture==preset.texture and
		default_shaft.shaft_material.color==preset.color and is_equal_approx(default_shaft.shaft_material.strength,preset.strength),
		"A shaft created without a saved material uses the window preset")
	check(default_shaft.shaft_material!=other_default_shaft.shaft_material and default_shaft.shaft_material!=preset,
		"Each generated shaft owns its material")
	default_shaft.queue_free()
	other_default_shaft.queue_free()
	clone.queue_free();effects[1].hide();effects[2].hide();first.position=Vector3(0,1.4,0);first.length=4.0;first.end_offset=Vector2(0,-1.3);await settle()
	check(first.mesh.get_aabb().end.z<=.001 and first.mesh.get_aabb().position.z<-3.9,"Prefab grows along local -Z from its window origin")
	var packed := PackedScene.new();first.owner=null;packed.pack(first);var path := "res://exports/editor_tests/light_shaft_roundtrip.tscn";ResourceSaver.save(packed,path)
	var saved := FileAccess.get_file_as_string(path);check(saved.length()<3500 and not saved.contains("PackedVector3Array"),"Scene saves only editable settings, without embedded generated meshes")
	var loaded: Node3D=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate();stage.add_child(loaded);check(loaded.mesh!=null and loaded.length==4.0 and loaded.shaft_material.texture!=null,"Loading a saved shaft reconstructs its mesh, UVs and material")
	loaded.queue_free();await settle()
	first.source_size=Vector2(1.4,1.6);first.end_size=Vector2(2,1.5);await settle();camera.position=Vector3(2.7,1.4,-3);camera.look_at(Vector3(0,.9,-1.6));renderer.fog_enabled=false;renderer.rebuild_editor_geometry()
	picture=await pixels();var visible := 0
	for y in 240:
		for x in 320:
			if picture.get_pixel(x,y).b>.04:visible+=1
	check(visible>100,"Real window shaft is visible from a side view in the native PSX framebuffer")
	picture.resize(960,720,Image.INTERPOLATE_NEAREST);picture.save_png("res://docs/window-light-shaft.png")
	first.rotation.y=PI;renderer.rebuild_editor_geometry();renderer.render_editor();check(renderer.triangle_count>0,"Explicit reverse faces keep the effect visible from both sides")
	for mesh: MeshInstance3D in stage.find_children("*","MeshInstance3D",true,false):mesh.mesh=null
	buffer.queue_free();await settle()
	FileAccess.open("res://docs/light-shafts-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"errors":failures},"\t"))
	print("LIGHT_SHAFTS_OK " if failures.is_empty() else "LIGHT_SHAFTS_FAILED ",checks," ",str(failures));quit(0 if failures.is_empty() else 1)
