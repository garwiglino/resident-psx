extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	for action in ["forward","back","left","right","sprint","aim","fire","reload","flashlight","shoulder","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	var viewport := SubViewport.new();viewport.size=Vector2i(320,240);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage := Node3D.new();viewport.add_child(stage)
	var p: Node3D=load("res://scenes/player.tscn").instantiate();stage.add_child(p);p.set_process(false);p.set_physics_process(false);p.set_process_unhandled_input(false);p.camera_collision_enabled=false;p.pitch=0;p.reset_camera_follow();p.get_node("Tenue").unequip()
	var camera := Camera3D.new();stage.add_child(camera);camera.position=Vector3(1.7,1.2,2.4);camera.look_at(Vector3(0,.95,0));camera.fov=40
	var renderer: Node=load("res://scripts/psx_renderer.gd").new();viewport.add_child(renderer);renderer.ambient_light_color=Color(.75,.75,.75);renderer.fog_enabled=false;renderer.dithering=false;renderer.setup_editor(stage,camera)
	var comparison := Image.create(640,480,false,Image.FORMAT_RGBA8);var m: Node3D=p.motion
	var clips := ["forward_left","backward_right"]
	for row in clips.size():
		for column in 2:
			m._restore_pose_layers();m.walk_spine.reset();m.walk_spine.enabled=column==1;m.walk_spine.response=0;m.blend_time=0;m.current="";m.play(clips[row]);m.advance_motion(.3);p._apply_upper_body_look();renderer.render_editor()
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			var picture := viewport.get_texture().get_image();comparison.blit_rect(picture,Rect2i(0,0,320,240),Vector2i(column*320,row*240))
	comparison.resize(1280,960,Image.INTERPOLATE_NEAREST);comparison.save_png("res://docs/walk-spine-before-after.png")
	for audio in p.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	await create_timer(.15).timeout;viewport.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout;print("WALK_SPINE_REVIEW_OK");quit()
