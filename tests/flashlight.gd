extends SceneTree
var failures: Array[String]=[]
var report: Dictionary={}

func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func run() -> void:
	root.get_node("InventoryState").persist_collection=false
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	for enemy in game.enemies:enemy.set_physics_process(false)
	var p=game.player
	p.set_process(false);p.set_physics_process(false)
	var renderer=game.psx_renderer
	renderer.set_process(false)
	var motion=p.motion
	var skeleton: Skeleton3D=motion.body_skeleton
	check(motion.flashlight_bone>=0,"Flashlight uses the character chest height")
	check(p.flashlight_color==Color.WHITE,"Default flashlight is neutral white")
	check(renderer.native_geometry.has_method("set_torch_light"),"Native renderer accepts a light independent of the camera")
	var player_surfaces := 0
	for surface in renderer.entries:
		if not renderer._uses_player_depth(surface.node):continue
		player_surfaces+=1
		check(not surface.torch_receiver,"Player, clothes and held weapon ignore their own flashlight")
		check(not surface.light_occluder,"Player surfaces never cast a flashlight shadow")
	check(player_surfaces>0,"Actual player surfaces were checked")
	p.rotation=Vector3.ZERO;p.pitch=0;p.reset_camera_follow()
	p.camera_rotation_lag=0;p.camera_translation_lag=0
	p.camera_collision_enabled=false
	for aiming in [false,true]:
		motion.set_aiming(aiming,0)
		for clip in ["idle","walk","strafe_left","backward","run"]:
			motion.play(clip)
			for frame in 8:motion.advance_motion(1.0/60)
			p.look_yaw=deg_to_rad(30);p.pitch=deg_to_rad(18)
			p.update_camera_follow(1.0/60);p._apply_upper_body_look()
			renderer._update_flashlight()
			var anchor: Vector3=skeleton.global_transform*motion._flashlight_anchor
			check(renderer.torch_pos.distance_to(anchor)<.045,"Lamp stays very close to the chest")
			check(renderer.torch_dir.is_equal_approx((-p.camera.global_basis.z).normalized()),"Beam follows camera rotation exactly: "+clip)
			var initial_pos: Vector3=renderer.torch_pos
			var initial_dir: Vector3=renderer.torch_dir
			p.camera.position.x+=.4;renderer._update_flashlight()
			check(renderer.torch_pos.is_equal_approx(initial_pos) and renderer.torch_dir.is_equal_approx(initial_dir),"Moving camera alone does not move the light")
			p.camera.position.x-=.4
			motion.advance_motion(.06);p._apply_upper_body_look();renderer._update_flashlight()
			check(renderer.torch_pos.is_equal_approx(initial_pos) and renderer.torch_dir.is_equal_approx(initial_dir),"Animated torso micro-rotations do not shake the light")
			p.look_yaw=deg_to_rad(-25);p.pitch=deg_to_rad(-15)
			p.update_camera_follow(1.0/60);p._apply_upper_body_look();renderer._update_flashlight()
			check(renderer.torch_dir.dot(initial_dir)<.9,"Light follows camera yaw and pitch")
			report[clip+"_aim_"+str(aiming)]={"position":str(renderer.torch_pos),"direction":str(renderer.torch_dir)}
	# Small visible triangle isolates per-vertex lighting from the environment.
	var node := MeshInstance3D.new();root.add_child(node)
	var image := Image.create(1,1,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var vertices := PackedVector3Array([Vector3(-.3,-.2,-3),Vector3(.3,-.2,-3),Vector3(0,.3,-3)])
	var entry := {"node":node,"skeleton":null,"vertices":vertices,"normals":PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]),
		"uvs":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE]),"indices":PackedInt32Array([0,2,1]),
		"bind_indices":PackedInt32Array(),"binds":[],"color":Color(.25,.25,.25),"emission":Color.BLACK,"fixed":true,"textured":false,"texture_page":0,
		"draw_texture":texture,"logical_texture_size":Vector2.ONE,"aabb":AABB(Vector3(-.3,-.2,-3),Vector3(.6,.5,.01)),
		"static_positions":vertices,"static_normals":PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]),
		"static_light":PackedVector3Array([Vector3.ONE*.1,Vector3.ONE*.1,Vector3.ONE*.1])}
	var geometry: RefCounted=ClassDB.instantiate("PSXGeometry")
	geometry.set_world_lights([],Vector3.ONE*.4)
	geometry.configure([entry])
	var scene_fog := Vector2(renderer.fog_start,renderer.fog_end)
	renderer.fog_start=9;renderer.fog_end=33
	renderer.torch_pos=Vector3(0,0,-1);renderer.torch_dir=Vector3.FORWARD
	renderer.torch_color=Vector3.ONE;renderer.torch_on=true
	geometry.set_torch_light(renderer.torch_pos,renderer.torch_dir,renderer.torch_color,renderer.torch_energy,renderer.torch_range,renderer.torch_outer_cos,renderer.torch_inner_cos)
	var baseline: PackedColorArray=geometry.frame(Transform3D.IDENTITY,50,false,false,true)[0].colors
	var lit: PackedColorArray=geometry.frame(Transform3D.IDENTITY,50,true,false,true)[0].colors
	for vertex in 3:
		check(lit[vertex].r>baseline[vertex].r,"Cone illuminates vertices in front of the mount")
		check(is_equal_approx(lit[vertex].r,lit[vertex].g) and is_equal_approx(lit[vertex].g,lit[vertex].b),"Flashlight contribution is white")
		var fallback: Color=renderer.shade(vertices[[0,2,1][vertex]],Vector3.BACK,3,entry.color,Vector3.ONE*.1,false)
		report["lighting_"+str(vertex)]={"native":str(lit[vertex]),"fallback":str(fallback)}
		for channel in 3:check(absf(lit[vertex][channel]-fallback[channel])<.00001,"Native and fallback flashlight illumination agree")
	for direction in [Vector3.RIGHT,Vector3.BACK,Vector3(sin(deg_to_rad(30)),0,-cos(deg_to_rad(30)))]:
		geometry.set_torch_light(renderer.torch_pos,direction,Vector3.ONE,2,16,renderer.torch_outer_cos,renderer.torch_inner_cos)
		check(geometry.frame(Transform3D.IDENTITY,50,true,false,true)[0].colors==baseline,"Outside or behind the cone remains unlit")
	geometry.set_torch_light(renderer.torch_pos,Vector3.FORWARD,Vector3.ONE,2,1,renderer.torch_outer_cos,renderer.torch_inner_cos)
	check(geometry.frame(Transform3D.IDENTITY,50,true,false,true)[0].colors==baseline,"Range limits the cone")
	entry.torch_receiver=false;geometry.configure([entry])
	geometry.set_torch_light(renderer.torch_pos,Vector3.FORWARD,Vector3.ONE,2,16,renderer.torch_outer_cos,renderer.torch_inner_cos)
	var self_off: PackedColorArray=geometry.frame(Transform3D.IDENTITY,50,false,false,true)[0].colors
	var self_on: PackedColorArray=geometry.frame(Transform3D.IDENTITY,50,true,false,true)[0].colors
	check(self_on==self_off,"Self-exclusion removes only the flashlight contribution")
	geometry.set_world_lights([],Vector3.ONE*.1)
	var ambient_only: PackedColorArray=geometry.frame(Transform3D.IDENTITY,50,true,false,true)[0].colors
	geometry.set_world_lights([{"position":Vector3(0,0,-1),"color":Vector3.ONE,"energy":2.0,"range":10.0}],Vector3.ONE*.1)
	var world_lit: PackedColorArray=geometry.frame(Transform3D.IDENTITY,50,true,false,true)[0].colors
	check(world_lit[0].r>ambient_only[0].r,"A world light still illuminates a surface excluded from the flashlight")
	p.flashlight=false;renderer._update_flashlight()
	check(not renderer.torch_on,"Player toggle switches off the renderer light")
	renderer.fog_start=scene_fog.x;renderer.fog_end=scene_fog.y
	if "--visual" in OS.get_cmdline_user_args():
		p.position=Vector3(0,.05,2);p.rotation=Vector3.ZERO
		motion.set_aiming(false,0);motion.play("idle");motion.advance_motion(.1)
		for sample in [["front",0,0],["turned",30,0],["down",0,-20]]:
			p.look_yaw=deg_to_rad(sample[1]);p.pitch=deg_to_rad(sample[2])
			p.update_camera_follow(1.0/60);p._apply_upper_body_look()
			for on in [false,true]:
				p.flashlight=on;renderer._process(0)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/flashlight-%s-%s.png" % [sample[0],"on" if on else "off"])
	FileAccess.open("res://docs/flashlight-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"measurements":report,"failures":failures},"\t"))
	for audio in game.find_children("*","AudioStreamPlayer",true,false):audio.stop()
	node.queue_free();game.queue_free();await process_frame
	print("FLASHLIGHT_OK: stable chest position, camera yaw/pitch, no animated torso jitter, white cone, native/fallback, range and toggle" if failures.is_empty() else "FLASHLIGHT_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
