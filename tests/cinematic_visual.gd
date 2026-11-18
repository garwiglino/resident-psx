extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func capture(path: String) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image();image.save_png(path);return image
func run() -> void:
	var preview=load("res://scenes/cinematics/cinematic_preview.tscn").instantiate()
	var example=preview.get_node("Level/Example");example.plans=example.get_plans();example.plans.back().finish_camera_on_confirm=false
	root.add_child(preview)
	var game=preview.get_node("Level");var manager=game.cinematics;var dialogue=game.dialogue
	for index in 6:await physics_frame
	check(manager.is_active() and game.get_node("Trigger").used,"Actual F6 preview starts from its physical cube zone")
	check(is_zero_approx(manager._blend_left) and manager.camera.global_transform.is_equal_approx(game.get_node("Example/CameraA").global_transform),"Default cinematic entry cuts directly to the first shot")
	manager.set_process(false);manager._process(.45);dialogue.set_process(false);dialogue.advance()
	var first: Image=await capture("res://docs/cinematic-camera-a.png")
	check(manager.camera==game.psx_renderer.camera and root.get_camera_3d()==manager.camera,"Native and PSX cameras agree in actual rendered preview")
	check(game.psx_renderer.inverse_camera.is_equal_approx(manager.camera.get_camera_transform().affine_inverse()),"Native PSX geometry receives the cinematic view transform")
	check(is_equal_approx(game.psx_renderer.focal,120.0/tan(deg_to_rad(manager.camera.fov)*.5)),"Cinematic field of view drives native PSX projection")
	var mount: Transform3D=game.player.motion.get_flashlight_transform(game.player.flashlight_offset,game.player.camera.global_basis)
	check(game.psx_renderer.torch_dir.is_equal_approx(mount.basis.z.normalized()),"A cinematic camera does not steer the player's flashlight")
	manager._process(.75);dialogue.set_process(false)
	check(manager._camera_done and manager.waiting_for_dialogue and dialogue.is_active(),"First camera holds its final image without closing unread text")
	dialogue.advance();manager._process(.2);dialogue.set_process(false)
	var second: Image=await capture("res://docs/cinematic-camera-b.png")
	var changed := 0
	for y in 170:
		for x in 320:
			var difference := first.get_pixel(x,y)-second.get_pixel(x,y)
			if absf(difference.r)+absf(difference.g)+absf(difference.b)>.1:changed+=1
	check(changed>3000 and manager.plan_index==1 and dialogue.view.visible,"Camera cut changes actual PSX geometry while the dialogue window remains visible")
	check(not game.hud.prompt.visible and not game.hud.ammo_label.visible and not game.player.aiming,"Cinematic has no gameplay HUD or forced aim")
	var enlarged := second.duplicate();enlarged.resize(960,720,Image.INTERPOLATE_NEAREST);enlarged.save_png("res://docs/cinematic-preview.png")
	var limit := 0
	while dialogue.is_active() and limit<30:dialogue.advance();limit+=1
	check(game.player.controls_blocked and manager.is_active(),"Confirming dialogue leaves camera control with the cinematic")
	manager._process(2)
	check(not manager.is_active() and game.psx_renderer.camera==game.player.camera and not game.player.controls_blocked,"Default cinematic exit cuts immediately to gameplay with no return interpolation")
	await capture("res://docs/cinematic-return.png")
	check(not manager.is_active() and game.psx_renderer.camera==game.player.camera and not game.player.controls_blocked,"Actual rendered preview returns to shoulder gameplay")
	FileAccess.open("res://docs/cinematic-visual-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"changed_background_pixels":changed,"resolution":"320x240","native_psx":game.psx_renderer.native_geometry!=null},"\t"))
	for audio in preview.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in preview.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	preview.queue_free();await process_frame;await create_timer(.1).timeout
	print("CINEMATIC_VISUAL_OK: physical F6 trigger, native PSX cameras/FOV, persistent dialogue, flashlight independence and return to gameplay" if failures.is_empty() else "CINEMATIC_VISUAL_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
