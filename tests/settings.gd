extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool,message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.psx_renderer.set_process(false)
	var p=game.player
	var properties: Dictionary={}
	for property in p.get_property_list():
		if property.usage&PROPERTY_USAGE_EDITOR:
			properties[property.name]=true
	for name in ["walk_speed","run_speed","aim_walk_speed","acceleration","braking","gravity","root_motion_enabled","root_motion_scale","root_motion_playback_speed","run_animation_speed","root_motion_rotation_enabled","root_motion_steer_with_input","animation_blend_time","torso_follow_enabled","torso_yaw_limit_degrees","torso_pitch_limit_degrees","body_turn_threshold_degrees","body_turn_recenter_degrees","body_turn_speed_degrees","body_turn_response","camera_offset","camera_fov","camera_near","camera_far","mouse_sensitivity","aim_mouse_sensitivity","invert_y","pitch_min_degrees","pitch_max_degrees","camera_collision_radius","camera_collision_margin","model_scale","starting_weapons","starting_weapon_slot"]:
		check(properties.has(name),"Inspector property missing: "+name)
	check(p.camera.get_parent()==p.arm,"Camera rig must be editable scene nodes")
	for name in ["aim_pose_enabled","aim_pose_blend_time","aim_camera_offset","aim_camera_fov","aim_camera_transition_time"]:
		check(properties.has(name),"Aim inspector property missing: "+name)
	for name in ["footstep_contact_height","footstep_lift_height","footstep_min_interval"]:
		check(properties.has(name),"Footstep contact setting is exposed: "+name)
	p.camera_offset=Vector3(.5,1.6,2.4)
	p.camera_fov=45
	p.camera_near=.15
	p.model_scale=1.2
	p.collision_height=1.9
	p.apply_settings()
	p.reset_camera_follow()
	check(is_equal_approx(p.camera.fov,45) and is_equal_approx(p.camera.near,.15),"Camera settings applied")
	check(is_equal_approx(p.camera_pivot.global_position.y-p.global_position.y,1.6) and is_equal_approx(p.arm.spring_length,2.4),"Camera offset applied")
	check(p.motion.scale.is_equal_approx(Vector3.ONE*1.2),"Model scale applied")
	check(is_equal_approx(p.get_node("CollisionShape3D").shape.height,1.9),"Capsule height applied")
	p.walk_speed=2.75
	var packed := PackedScene.new()
	check(packed.pack(p)==OK,"Player settings can be packed")
	var restored: Node=packed.instantiate()
	check(restored.walk_speed==2.75 and restored.camera_fov==45,"Tuning survives scene save/load")
	restored.free()
	p.import_blender_camera()
	check(absf(p.camera_fov-30.219150726)<.00001,"Blender reset restores exact vertical FOV")
	check(absf(p.camera_offset.z-1.7886838913)<.00001,"Blender reset restores exact position")
	p.magazine_capacity=6
	p.ammo=2
	p.reserve=3
	p.reload_duration=.05
	p.reload_weapon()
	for i in 10:
		await physics_frame
	check(p.ammo==2 and p.reserve==3,"Authored reload timing takes priority over the fallback duration")
	await create_timer(p.motion.get_reload_duration()).timeout
	check(p.ammo==5 and p.reserve==0,"Custom magazine refills after the authored reload completes")
	var renderer=game.psx_renderer
	check(renderer.native_geometry!=null,"Native accelerated geometry is loaded")
	check(renderer.native_geometry.get_statistics().version>=9,"Native renderer supports light types, editable fog, affine control, shot effects and chest-mounted torch")
	var defaults: Node=renderer.get_script().new()
	check(is_equal_approx(defaults.affine_texture_strength,1.0),"Authentic affine interpolation is the default before scene overrides")
	defaults.free()
	renderer.affine_texture_strength=.4
	renderer.apply_render_settings()
	check(is_equal_approx(renderer.raster.get_shader_parameter("affine_texture_strength"),.4),"Affine texture control reaches the shader")
	renderer.affine_texture_strength=1.0
	renderer.apply_render_settings()
	check(renderer.texture_page_count>1,"Texture page table is populated")
	for entry in renderer.entries:check(entry.page_index>=0 and entry.page_index<renderer.texture_page_count,"Every registered surface references a valid logical texture page")
	for entry in renderer.entries:
		check(entry.logical_texture_size.x<=256 and entry.logical_texture_size.y<=256,"Logical PSX texture pages are at most 256x256")
	renderer.target_fps=75
	renderer.vertex_snapping=false
	renderer.dithering=false
	renderer.apply_render_settings()
	check(Engine.max_fps==75,"FPS setting applied")
	check(not renderer.raster.get_shader_parameter("dither_enabled"),"Dithering setting applied")
	check(not game.materials.snap_enabled,"Vertex snapping setting applied")
	renderer.target_fps=60
	renderer.vertex_snapping=true
	renderer.dithering=true
	renderer.apply_render_settings()
	for audio in game.find_children("*","AudioStreamPlayer",true,false):
		audio.stop()
	for audio in game.find_children("*","AudioStreamPlayer3D",true,false):audio.stop()
	await create_timer(.08).timeout
	game.queue_free()
	await process_frame
	print("SETTINGS_OK: inspector, live camera/collision/scale, persistence, Blender reset, weapon, render settings" if failures.is_empty() else "SETTINGS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
