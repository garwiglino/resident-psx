extends SceneTree
const Light=preload("res://scripts/psx_light_3d.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var view := SubViewport.new();view.size=Vector2i(320,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate();view.add_child(game)
	for source in get_nodes_in_group("psx_world_lights"):
		if game.is_ancestor_of(source):source.enabled=false
	game.set_process(false);game.set_process_input(false);game.psx_renderer.set_process(false);game.hud.visible=false
	for enemy in game.enemies:enemy.set_physics_process(false);enemy.visible=false
	var p=game.player;p.set_process(false);p.set_physics_process(false);p.motion.set_process(false)
	p.position=Vector3(0,.05,4.5);p.rotation=Vector3.ZERO;p.reset_camera_follow();p._process(0)
	var lamp := Light.new();lamp.light_range=7;lamp.light_energy=3;lamp.light_color=Color(1,.55,.2)
	game.level.get_node("Lumieres").add_child(lamp);lamp.position=Vector3(-.8,2.2,2.5)
	for setting in ["none","point","moved","torch"]:
		p.flashlight=setting=="torch";lamp.enabled=setting in ["point","moved"]
		if setting=="moved":lamp.position=Vector3(1.0,1.8,.5);lamp.light_color=Color(.2,.55,1)
		game.psx_renderer._process(0)
		for render in 3:await process_frame
		RenderingServer.force_draw(false)
		view.get_texture().get_image().save_png("res://docs/manual-lights-%s.png" % setting)
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.1).timeout;view.queue_free();await process_frame;await create_timer(.08).timeout
	print("MANUAL_LIGHTS_REVIEW_OK: no default lighting, manual warm/blue point sources and preserved torch")
	quit()
