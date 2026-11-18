extends SceneTree
var failures: Array[String]=[]
var viewport: SubViewport
var renderer: Node
var lamp: Node3D
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func capture() -> Image:
	for frame in 3:renderer.render_editor();await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	viewport=SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	lamp=load("res://scenes/lighting/neon.tscn").instantiate();stage.add_child(lamp);lamp.position.y=1;lamp.audio_enabled=false;lamp.light_color=Color.WHITE;lamp.light_energy=2;lamp.flicker=true;lamp.flicker_amount=0;lamp.dropout_chance=0
	var floor := MeshInstance3D.new();floor.mesh=PlaneMesh.new();floor.mesh.size=Vector2(3,3);stage.add_child(floor)
	var camera := Camera3D.new();viewport.add_child(camera);camera.position=Vector3(0,.1,2.5);camera.look_at(Vector3(0,.95,0));camera.fov=45;camera.make_current()
	renderer=load("res://scripts/psx_renderer.gd").new();viewport.add_child(renderer);renderer.fog_enabled=false;renderer.dithering=false;renderer.setup_editor(stage,camera)
	check(renderer.native_geometry!=null and renderer.native_geometry.get_statistics().version>=17,"Native engine supports dynamic unlit fixture surfaces")
	var emitter_count := 0
	for entry in renderer.entries:
		if int(entry.get("unlit_light_id",0)):
			emitter_count+=1;check(not entry.light_occluder and not entry.light_static_receiver,"Luminous surfaces are unlit and do not block their own light")
	check(emitter_count==2,"Both neon tubes use the unlit path")
	var atlas_id: int=renderer.atlas_texture.get_instance_id();var material_changes := [0]
	for mesh in lamp._emissive_meshes:
		for surface in mesh.get_meta("psx_unlit_surfaces"):
			mesh.get_active_material(surface).changed.connect(func():material_changes[0]+=1)
	var sheet := Image.create(1280,240,false,Image.FORMAT_RGBA8);var tube_pixel := Vector2i.ZERO;var levels: Array=[]
	var tube: MeshInstance3D=lamp.model.get_node("Tube1")
	for i in 3:
		var gain: float=[1.0,.25,0.0][i];lamp.flicker_minimum=gain;lamp.flicker_maximum=gain
		var image := await capture();sheet.blit_rect(image,Rect2i(0,0,320,240),Vector2i(i*320,0))
		if i==0:
			var center := Vector2i(camera.unproject_position(tube.global_position));var value := -1.0
			for y in range(center.y-3,center.y+4):
				for x in range(center.x-3,center.x+4):
					var color := image.get_pixel(x,y)
					if color.get_luminance()>value:value=color.get_luminance();tube_pixel=Vector2i(x,y)
		var pixel := image.get_pixelv(tube_pixel);var expected := floorf(floorf(gain*255)/8)/31
		check(absf(pixel.r-expected)<.01 and absf(pixel.g-expected)<.01 and absf(pixel.b-expected)<.01,"Actual PSX tube pixel follows the exact light flicker multiplier: "+str(gain)+" / "+str(pixel))
		var source: Dictionary=renderer.world_lights[0]
		check(absf(float(source.energy)/lamp.light_energy-gain)<.00001 and absf(Vector3(source.fixture_emission).x-gain)<.00001,"Native vertex lighting and luminous surface receive the same sample")
		levels.append({"gain":gain,"pixel":pixel.to_html()})
	check(renderer.atlas_texture.get_instance_id()==atlas_id and material_changes[0]==0,"Flicker never rebuilds textures or edits watched material resources")
	renderer.torch_on=true;renderer.native_geometry.set_torch_light(camera.global_position,(tube.global_position-camera.global_position).normalized(),Vector3.ONE,8,10,cos(deg_to_rad(80)),cos(deg_to_rad(60)))
	renderer.native_geometry.set_shot_light(tube.global_position+Vector3(0,-.1,1),Vector3.ONE,8,10)
	var image := await capture()
	check(image.get_pixelv(tube_pixel).get_luminance()<.01,"External flashlight and muzzle flash cannot illuminate an unlit extinguished tube")
	renderer.torch_on=false;renderer.native_geometry.set_shot_light(Vector3.ZERO,Vector3.ZERO,0,1)
	lamp.flicker=false;image=await capture();sheet.blit_rect(image,Rect2i(0,0,320,240),Vector2i(960,0));sheet.save_png("res://docs/lamp-flicker-psx.png")
	renderer.fog_enabled=true;renderer.fog_start=0;renderer.fog_end=1;renderer.fog_color=Color(.08,.12,.16)
	image=await capture()
	check(image.get_pixelv(tube_pixel).get_luminance()>.1 and image.get_pixelv(tube_pixel).get_luminance()<.4,"Unlit surfaces still receive the normal PSX depth cue")
	renderer.fog_enabled=false
	# Ordinary 3D preview uses per-instance uniforms, without editing materials.
	renderer.visible=false;viewport.disable_3d=false;camera.cull_mask=(1<<20)-1
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var standard_on := viewport.get_texture().get_image()
	var standard_pixel := Vector2i(camera.unproject_position(tube.global_position));var brightest := -1.0
	for y in range(standard_pixel.y-4,standard_pixel.y+5):
		for x in range(standard_pixel.x-4,standard_pixel.x+5):
			if standard_on.get_pixel(x,y).get_luminance()>brightest:brightest=standard_on.get_pixel(x,y).get_luminance();tube_pixel=Vector2i(x,y)
	lamp.enabled=false
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	var standard_off := viewport.get_texture().get_image()
	check(standard_on.get_pixelv(tube_pixel).get_luminance()>.8 and standard_off.get_pixelv(tube_pixel).get_luminance()<.01,"Ordinary 3D editor path also switches luminous geometry on and off")
	standard_on.save_png("res://docs/lamp-standard-preview.png")
	standard_off.save_png("res://docs/lamp-standard-off.png")
	var result := {"ok":failures.is_empty(),"errors":failures,"levels":levels,"native":renderer.native_geometry.get_statistics()}
	FileAccess.open("res://docs/lamp-render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	viewport.queue_free();await process_frame;await process_frame
	print("LAMP_RENDER_OK " if failures.is_empty() else "LAMP_RENDER_FAILED ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
