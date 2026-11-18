extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	var sources: Array[Node3D]=[]
	for name in ["neon","applique","plafonnier"]:
		var source: Node3D=load("res://scenes/lighting/"+name+".tscn").instantiate();stage.add_child(source);source.audio_enabled=false;sources.append(source)
	var camera := Camera3D.new();viewport.add_child(camera);camera.fov=40
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();viewport.add_child(renderer);renderer.fog_enabled=false;renderer.ambient_light_color=Color(.6,.6,.6)
	var sheet := Image.create(960,240,false,Image.FORMAT_RGBA8)
	var positions := [Vector3(.25,-.5,1.4),Vector3(.45,.15,-.8),Vector3(.35,-.65,.7)]
	for i in sources.size():
		for j in sources.size():sources[j].visible=i==j
		camera.position=positions[i];camera.look_at(Vector3.ZERO)
		renderer.setup_editor(stage,camera)
		for frame in 4:renderer.render_editor();await process_frame
		await RenderingServer.frame_post_draw
		sheet.blit_rect(viewport.get_texture().get_image(),Rect2i(0,0,320,240),Vector2i(i*320,0))
	sheet.save_png("res://docs/lamps-models-psx.png")
	viewport.queue_free();await process_frame;quit()
